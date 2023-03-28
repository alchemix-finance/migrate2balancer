// SPDX-License-Identifier: GPL-3
pragma solidity ^0.8.15;

import "src/interfaces/IMigrator.sol";
import "src/interfaces/IWETH9.sol";
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
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";
import "openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";
import "openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

/**
 * @title  Sushi to Balancer migrator
 * @notice Tool to facilitate migrating a sushi SLP position to a BPT or auraBPT position
 */
contract Migrator is IMigrator, Initializable, Ownable {
    using SafeERC20 for IERC20;

    uint256 public constant BPS = 10000;
    uint256 public unrwapSlippage = 10; // 0.1%
    uint256 public swapSlippage = 10; // 0.1%

    bytes32 public balancerPoolId;

    IWETH9 public weth;
    IERC20 public token;
    IERC20 public bpt;
    IERC20 public auraBpt;
    IUniswapV2Pair public slp;
    IRewardPool4626 public auraPool;
    AggregatorV3Interface public priceFeed;
    IUniswapV2Router02 public sushiRouter;
    IVault public balancerVault;
    IBasePool public balancerPool;
    IAsset[] public poolAssets = new IAsset[](2);

    /*
        Admin functions
    */

    /// @inheritdoc IMigrator
    function initialize(InitializationParams memory params) external initializer onlyOwner {
        weth = IWETH9(params.weth);
        token = IERC20(params.token);
        bpt = IERC20(params.bpt);
        auraBpt = IERC20(params.auraBpt);
        slp = IUniswapV2Pair(params.slp);
        auraPool = IRewardPool4626(params.auraPool);
        priceFeed = AggregatorV3Interface(params.priceFeed);
        sushiRouter = IUniswapV2Router02(params.sushiRouter);
        balancerVault = IVault(params.balancerVault);
        balancerPool = IBasePool(address(bpt));
        balancerPoolId = balancerPool.getPoolId();
        poolAssets[0] = IAsset(address(weth));
        poolAssets[1] = IAsset(params.token);

        weth.approve(address(balancerVault), type(uint256).max);
        token.approve(address(balancerVault), type(uint256).max);
        bpt.approve(address(auraPool), type(uint256).max);
        slp.approve(address(sushiRouter), type(uint256).max);
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

    /*
        Public functions
    */

    /// @inheritdoc IMigrator
    function calculateSlpAmounts(uint256 _slpAmount) public view returns (uint256, uint256) {
        uint256 slpSupply = slp.totalSupply();
        (uint256 wethReserves, uint256 tokenReserves, ) = slp.getReserves();

        // Calculate the amount of tokens and WETH the user will receive
        uint256 amountToken = (_slpAmount * tokenReserves) / slpSupply;
        uint256 amountWeth = (_slpAmount * wethReserves) / slpSupply;

        // Calculate the minimum amounts with unrwapSlippage tolerance
        uint256 amountTokenMin = (amountToken * (BPS - unrwapSlippage)) / BPS;
        uint256 amountWethMin = (amountWeth * (BPS - unrwapSlippage)) / BPS;

        return (amountTokenMin, amountWethMin);
    }

    /// @inheritdoc IMigrator
    function calculateWethWeight(uint256 _tokenAmount) public view returns (uint256) {
        (, int256 tokenEthPrice, , , ) = priceFeed.latestRoundData();

        uint256[] memory normalizedWeights = IManagedPool(address(balancerPool)).getNormalizedWeights();

        uint256 amount = (((_tokenAmount * uint256(tokenEthPrice)) / 1 ether) * normalizedWeights[0]) /
            normalizedWeights[1];

        return (amount);
    }

    /// @inheritdoc IMigrator
    function unwrapSlp() public {
        uint256 deadline = block.timestamp + 300;
        uint256 slpAmount = slp.balanceOf(address(this));

        (uint256 amountTokenMin, uint256 amountWethMin) = calculateSlpAmounts(slpAmount);

        sushiRouter.removeLiquidityETH(
            address(token),
            slpAmount,
            amountTokenMin,
            amountWethMin,
            address(this),
            deadline
        );
    }

    /// @inheritdoc IMigrator
    function swapWethForTokenBalancer() public {
        uint256 wethRequired = calculateWethWeight(token.balanceOf(address(this)));
        uint256 wethBalance = weth.balanceOf(address(this));
        require(wethBalance > wethRequired, "contract doesn't have enough weth");

        (, int256 tokenEthPrice, , , ) = priceFeed.latestRoundData();

        uint256 amountWeth = wethBalance - wethRequired;
        uint256 minAmountOut = (((amountWeth * uint256(tokenEthPrice)) / (1 ether)) * (BPS - swapSlippage)) / BPS;
        uint256 deadline = block.timestamp;

        IVault.SingleSwap memory singleSwap = IVault.SingleSwap({
            poolId: balancerPoolId,
            kind: IVault.SwapKind.GIVEN_IN,
            assetIn: IAsset(address(weth)),
            assetOut: IAsset(address(token)),
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

    /// @inheritdoc IMigrator
    function depositIntoBalancerPool() public {
        uint256[] memory normalizedWeights = IManagedPool(address(balancerPool)).getNormalizedWeights();
        (, uint256[] memory balances, ) = balancerVault.getPoolTokens(balancerPoolId);

        uint256 wethAmount = weth.balanceOf(address(this));
        uint256 tokenAmount = token.balanceOf(address(this));

        uint256[] memory amountsIn = new uint256[](2);
        amountsIn[0] = wethAmount;
        amountsIn[1] = tokenAmount;

        uint256 bptAmountOut = WeightedMath._calcBptOutGivenExactTokensIn(
            balances,
            normalizedWeights,
            amountsIn,
            IERC20(address(balancerPool)).totalSupply(),
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

    /// @inheritdoc IMigrator
    function depositIntoRewardsPool() public {
        uint256 amount = bpt.balanceOf(address(this));

        auraPool.deposit(amount, msg.sender);
    }

    /// @inheritdoc IMigrator
    function userDepositIntoRewardsPool() public {
        uint256 amount = bpt.balanceOf(msg.sender);
        bpt.safeTransferFrom(msg.sender, address(this), amount);
        auraPool.deposit(amount, msg.sender);
    }

    /*
        External functions
    */

    /// @inheritdoc IMigrator
    function migrate(bool _stakeBpt) external {
        uint256 slpBalance = slp.balanceOf(msg.sender);

        IERC20(address(slp)).safeTransferFrom(msg.sender, address(this), slpBalance);

        unwrapSlp();

        swapWethForTokenBalancer();

        depositIntoBalancerPool();

        // msg.sender receives auraBPT or BPT depending on their choice to deposit into Aura pool
        if (_stakeBpt) depositIntoRewardsPool();
        else bpt.safeTransferFrom(address(this), msg.sender, bpt.balanceOf(address(this)));

        emit Migrated(msg.sender, slpBalance, _stakeBpt);
    }

    receive() external payable {
        if (msg.value > 0) {
            weth.deposit{ value: msg.value }();
        }
    }
}
