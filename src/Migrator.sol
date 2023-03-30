// SPDX-License-Identifier: GPL-3
pragma solidity ^0.8.15;

import "src/interfaces/IMigrator.sol";
import "src/interfaces/chainlink/AggregatorV3Interface.sol";
import "src/interfaces/sushi/IUniswapV2Pair.sol";
import "src/interfaces/sushi/IUniswapV2Router02.sol";
import "src/interfaces/balancer/IVault.sol";
import "src/interfaces/balancer/WeightedPoolUserData.sol";
import "src/interfaces/balancer/IBasePool.sol";
import "src/interfaces/balancer/IAsset.sol";
import "src/interfaces/balancer/IManagedPool.sol";
import "src/interfaces/balancer/WeightedMath.sol";
import "src/interfaces/aura/IRewardPool4626.sol";
import "solmate/src/tokens/ERC20.sol";
import "solmate/src/tokens/WETH.sol";
import "solmate/src/utils/SafeTransferLib.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";

/**
 * @title  Sushi to Balancer LP migrator
 * @notice Tool to facilitate migrating Sushi LPs to Balancer or Aura
 * @dev SLP: SushiSwap LP Token
 * @dev BPT: 20WETH-80TOKEN Balancer Pool Token
 * @dev auraBPT: 20WETH-80TOKEN Aura Deposit Vault
 */
contract Migrator is IMigrator, Ownable {
    using SafeTransferLib for ERC20;

    uint256 public swapSlippage = 10; // 0.1%

    uint256 public immutable BPS = 10000;
    bytes32 public immutable balancerPoolId;
    WETH public immutable weth;
    ERC20 public immutable token;
    ERC20 public immutable balancerPoolToken;
    ERC20 public immutable auraDepositToken;
    IUniswapV2Pair public immutable sushiLpToken;
    IRewardPool4626 public immutable auraPool;
    AggregatorV3Interface public immutable tokenPrice;
    IUniswapV2Router02 public immutable sushiRouter;
    IVault public immutable balancerVault;
    IBasePool public immutable balancerPool;
    IAsset public immutable poolAssetWeth;
    IAsset public immutable poolAssetToken;

    /*
        Admin functions
    */

    constructor(InitializationParams memory params) Ownable() {
        weth = WETH(payable(params.weth));
        token = ERC20(params.token);
        balancerPoolToken = ERC20(params.balancerPoolToken);
        auraDepositToken = ERC20(params.auraDepositToken);
        sushiLpToken = IUniswapV2Pair(params.sushiLpToken);
        auraPool = IRewardPool4626(params.auraPool);
        tokenPrice = AggregatorV3Interface(params.tokenPrice);
        sushiRouter = IUniswapV2Router02(params.sushiRouter);
        balancerVault = IVault(params.balancerVault);
        balancerPool = IBasePool(address(balancerPoolToken));
        balancerPoolId = balancerPool.getPoolId();
        poolAssetWeth = IAsset(address(weth));
        poolAssetToken = IAsset(params.token);

        setApprovals();
    }

    /// @inheritdoc IMigrator
    function setSwapSlippage(uint256 _amount) external onlyOwner {
        require(_amount <= BPS, "swap slippage too high");
        swapSlippage = _amount;
    }

    /// @inheritdoc IMigrator
    function setApprovals() public onlyOwner {
        ERC20(address(weth)).safeApprove(address(balancerVault), type(uint256).max);
        token.safeApprove(address(balancerVault), type(uint256).max);
        balancerPoolToken.safeApprove(address(auraPool), type(uint256).max);
        ERC20(address(sushiLpToken)).safeApprove(address(sushiRouter), type(uint256).max);
    }

    /*
        External functions
    */

    /// @inheritdoc IMigrator
    function migrate(bool _stakeBpt, uint256 _amountTokenMin, uint256 _amountWethMin) external {
        uint256 slpBalance = sushiLpToken.balanceOf(msg.sender);

        ERC20(address(sushiLpToken)).safeTransferFrom(msg.sender, address(this), slpBalance);

        _unwrapSlp(_amountTokenMin, _amountWethMin);

        _swapWethForTokenBalancer();

        _depositIntoBalancerPool();

        // msg.sender receives auraBPT or BPT depending on their choice to deposit into Aura pool
        if (_stakeBpt) {
            _depositIntoRewardsPool();
        } else {
            balancerPoolToken.safeTransferFrom(address(this), msg.sender, balancerPoolToken.balanceOf(address(this)));
        }

        emit Migrated(msg.sender, slpBalance, _stakeBpt);
    }

    receive() external payable {
        require(msg.sender != address(weth), "WETH cannot be sent directly");
    }

    /*
        Internal functions
    */

    /**
     * @notice Get the amount WETH required to create balanced pool deposit
     * @param _tokenAmount Amount of TOKEN to deposit
     * @return uint256 Amount of WETH required to create 80/20 balanced deposit
     */
    function _calculateWethWeight(uint256 _tokenAmount) internal view returns (uint256) {
        uint256[] memory normalizedWeights = IManagedPool(address(balancerPool)).getNormalizedWeights();

        uint256 amount = (((_tokenAmount * _tokenPrice()) / 1 ether) * normalizedWeights[0]) / normalizedWeights[1];

        return (amount);
    }

    /**
     * @notice Unrwap SLP into TOKEN and WETH
     */
    function _unwrapSlp(uint256 _amountTokenMin, uint256 _amountWethMin) internal {
        uint256 slpAmount = sushiLpToken.balanceOf(address(this));

        sushiRouter.removeLiquidityETH(
            address(token),
            slpAmount,
            _amountTokenMin,
            _amountWethMin,
            address(this),
            block.timestamp
        );

        weth.deposit{ value: address(this).balance }();
    }

    /**
     * @notice Swap WETH for TOKEN to have balanced 80/20 TOKEN/WETH
     */
    function _swapWethForTokenBalancer() internal {
        uint256 wethRequired = _calculateWethWeight(token.balanceOf(address(this)));
        uint256 wethBalance = weth.balanceOf(address(this));
        require(wethBalance > wethRequired, "contract doesn't have enough weth");

        // Amount of excess WETH to swap
        uint256 amountWeth = wethBalance - wethRequired;
        uint256 minAmountOut = (((amountWeth * _tokenPrice()) / (1 ether)) * (BPS - swapSlippage)) / BPS;

        IVault.SingleSwap memory singleSwap = IVault.SingleSwap({
            poolId: balancerPoolId,
            kind: IVault.SwapKind.GIVEN_IN,
            assetIn: poolAssetWeth,
            assetOut: poolAssetToken,
            amount: amountWeth,
            userData: bytes("")
        });

        IVault.FundManagement memory funds = IVault.FundManagement({
            sender: address(this),
            fromInternalBalance: false,
            recipient: payable(address(this)),
            toInternalBalance: false
        });

        balancerVault.swap(singleSwap, funds, minAmountOut, block.timestamp);
    }

    /**
     * @notice Deposit into TOKEN/WETH 80/20 balancer pool
     */
    function _depositIntoBalancerPool() internal {
        uint256[] memory normalizedWeights = IManagedPool(address(balancerPool)).getNormalizedWeights();
        (, uint256[] memory balances, ) = balancerVault.getPoolTokens(balancerPoolId);

        uint256 wethAmount = weth.balanceOf(address(this));
        uint256 tokenAmount = token.balanceOf(address(this));

        uint256[] memory amountsIn = new uint256[](2);
        amountsIn[0] = wethAmount;
        amountsIn[1] = tokenAmount;

        IAsset[] memory poolAssets = new IAsset[](2);
        poolAssets[0] = poolAssetWeth;
        poolAssets[1] = poolAssetToken;

        uint256 bptAmountOut = WeightedMath._calcBptOutGivenExactTokensIn(
            balances,
            normalizedWeights,
            amountsIn,
            ERC20(address(balancerPool)).totalSupply(),
            balancerPool.getSwapFeePercentage()
        );

        bytes memory _userData = abi.encode(
            WeightedPoolUserData.JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT,
            amountsIn,
            bptAmountOut
        );

        IVault.JoinPoolRequest memory request = IVault.JoinPoolRequest({
            assets: poolAssets,
            maxAmountsIn: amountsIn,
            userData: _userData,
            fromInternalBalance: false
        });

        balancerVault.joinPool(balancerPoolId, address(this), address(this), request);
    }

    /**
     * @notice Deposit BPT into rewards pool
     */
    function _depositIntoRewardsPool() internal {
        uint256 amount = balancerPoolToken.balanceOf(address(this));

        auraPool.deposit(amount, msg.sender);
    }

    /**
     * @notice Get the price of a token
     * @dev Make sure price is not stale or incorrect
     * @return Return the correct price
     */
    function _tokenPrice() internal view returns (uint256) {
        (uint80 roundId, int256 price, , uint256 timestamp, uint80 answeredInRound) = tokenPrice.latestRoundData();

        require(answeredInRound >= roundId, "Stale price");
        require(timestamp != 0, "Round not complete");
        require(price > 0, "Chainlink answer reporting 0");

        return uint256(price);
    }
}
