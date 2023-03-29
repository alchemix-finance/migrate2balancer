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
import "openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";
import "openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

/**
 * @title  Sushi to Balancer migrator
 * @notice Tool to facilitate migrating a sushi SLP position to a BPT or auraBPT position
 */
contract Migrator is IMigrator, Initializable, Ownable {
    using SafeTransferLib for ERC20;

    uint256 public constant BPS = 10000;
    uint256 public unrwapSlippage = 10; // 0.1%
    uint256 public swapSlippage = 10; // 0.1%

    bytes32 public balancerPoolId;

    WETH public weth;
    ERC20 public token;
    ERC20 public bpt;
    ERC20 public auraBpt;
    IUniswapV2Pair public slp;
    IRewardPool4626 public auraPool;
    AggregatorV3Interface public tokenPrice;
    AggregatorV3Interface public wethPrice;
    IUniswapV2Router02 public sushiRouter;
    IVault public balancerVault;
    IBasePool public balancerPool;
    IAsset public poolAssetWeth;
    IAsset public poolAssetToken;

    /*
        Admin functions
    */

    /// @inheritdoc IMigrator
    function initialize(InitializationParams memory params) external initializer onlyOwner {
        weth = WETH(payable(params.weth));
        token = ERC20(params.token);
        bpt = ERC20(params.bpt);
        auraBpt = ERC20(params.auraBpt);
        slp = IUniswapV2Pair(params.slp);
        auraPool = IRewardPool4626(params.auraPool);
        tokenPrice = AggregatorV3Interface(params.tokenPrice);
        wethPrice = AggregatorV3Interface(params.wethPrice);
        sushiRouter = IUniswapV2Router02(params.sushiRouter);
        balancerVault = IVault(params.balancerVault);
        balancerPool = IBasePool(address(bpt));
        balancerPoolId = balancerPool.getPoolId();
        poolAssetWeth = IAsset(address(weth));
        poolAssetToken = IAsset(params.token);

        setApprovals();
    }

    /// @inheritdoc IMigrator
    function setUnrwapSlippage(uint256 _amount) external onlyOwner {
        require(_amount <= BPS, "unwrap slippage too high");
        unrwapSlippage = _amount;
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
        bpt.safeApprove(address(auraPool), type(uint256).max);
        ERC20(address(slp)).safeApprove(address(sushiRouter), type(uint256).max);
    }

    /*
        External functions
    */

    /// @inheritdoc IMigrator
    function migrate(bool _stakeBpt) external {
        uint256 slpBalance = slp.balanceOf(msg.sender);

        ERC20(address(slp)).safeTransferFrom(msg.sender, address(this), slpBalance);

        _unwrapSlp();

        _swapWethForTokenBalancer();

        _depositIntoBalancerPool();

        // msg.sender receives auraBPT or BPT depending on their choice to deposit into Aura pool
        if (_stakeBpt) _depositIntoRewardsPool();
        else bpt.safeTransferFrom(address(this), msg.sender, bpt.balanceOf(address(this)));

        emit Migrated(msg.sender, slpBalance, _stakeBpt);
    }

    /// @inheritdoc IMigrator
    function userDepositIntoRewardsPool() external {
        uint256 amount = bpt.balanceOf(msg.sender);
        bpt.safeTransferFrom(msg.sender, address(this), amount);
        auraPool.deposit(amount, msg.sender);
    }

    receive() external payable {
        if (msg.value > 0) {
            weth.deposit{ value: msg.value }();
        }
    }

    /*
        Internal functions
    */

    /**
     * @notice Calculate the min amount of TOKEN and WETH for a given SLP amount
     * @param _slpAmount The amount of SLP
     * @return Return values for min amount out of TOKEN and WETH with unwrap slippage
     */
    function _calculateSlpAmounts(uint256 _slpAmount) internal view returns (uint256, uint256) {
        uint256 tokenPriceEth = _tokenPrice();
        uint256 wethPriceUsd = _wethPrice();
        uint256 slpSupply = slp.totalSupply();
        (uint256 wethReserves, uint256 tokenReserves, ) = slp.getReserves();

        // Convert reserves into current USD price
        uint256 tokenReservesUsd = ((tokenReserves * tokenPriceEth) * wethPriceUsd) / 1 ether;
        uint256 wethReservesUsd = wethReserves * wethPriceUsd;

        // Get amounts in USD given the amount of SLP with slippage
        uint256 amountTokenUsd = (((_slpAmount * tokenReservesUsd) / slpSupply) * (BPS - unrwapSlippage)) / BPS;
        uint256 amountWethUsd = (((_slpAmount * wethReservesUsd) / slpSupply) * (BPS - unrwapSlippage)) / BPS;

        // Return tokens denominated in ETH
        uint256 amountTokenMin = (amountTokenUsd * 1 ether) / (tokenPriceEth * wethPriceUsd);
        uint256 amountWethMin = (amountWethUsd) / wethPriceUsd;

        return (amountTokenMin, amountWethMin);
    }

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
    function _unwrapSlp() internal {
        uint256 deadline = block.timestamp;
        uint256 slpAmount = slp.balanceOf(address(this));

        (uint256 amountTokenMin, uint256 amountWethMin) = _calculateSlpAmounts(slpAmount);

        sushiRouter.removeLiquidityETH(
            address(token),
            slpAmount,
            amountTokenMin,
            amountWethMin,
            address(this),
            deadline
        );
    }

    /**
     * @notice Swap WETH for TOKEN to have balanced 80/20 TOKEN/WETH
     */
    function _swapWethForTokenBalancer() internal {
        uint256 wethRequired = _calculateWethWeight(token.balanceOf(address(this)));
        uint256 wethBalance = weth.balanceOf(address(this));
        require(wethBalance > wethRequired, "contract doesn't have enough weth");

        uint256 amountWeth = wethBalance - wethRequired;
        uint256 minAmountOut = (((amountWeth * _tokenPrice()) / (1 ether)) * (BPS - swapSlippage)) / BPS;
        uint256 deadline = block.timestamp;

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

        balancerVault.swap(singleSwap, funds, minAmountOut, deadline);
    }

    function _swapWethForTokenAggregator() internal {}

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
        uint256 amount = bpt.balanceOf(address(this));

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

    /**
     * @notice Get the price of weth
     * @dev Make sure price is not stale or incorrect
     * @return Return the correct price
     */
    function _wethPrice() internal view returns (uint256) {
        (uint80 roundId, int256 price, , uint256 timestamp, uint80 answeredInRound) = wethPrice.latestRoundData();

        require(answeredInRound >= roundId, "Stale price");
        require(timestamp != 0, "Round not complete");
        require(price > 0, "Chainlink answer reporting 0");

        return uint256(price);
    }
}
