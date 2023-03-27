// SPDX-License-Identifier: GPL-3
pragma solidity ^0.8.15;

import "lib/forge-std/src/console2.sol";

import "src/interfaces/IMigrator.sol";
import "src/interfaces/IWETH9.sol";
import "src/interfaces/chainlink/AggregatorV3Interface.sol";
import "src/interfaces/alchemix/IStakingPools.sol";
import "src/interfaces/sushi/IMiniChefV2.sol";
import "src/interfaces/sushi/IUniswapV2Pair.sol";
import "src/interfaces/sushi/IUniswapV2Router02.sol";
import "src/interfaces/balancer/IVault.sol";
import "src/interfaces/balancer/WeightedPoolUserData.sol";
import "src/interfaces/balancer/IBasePool.sol";
import "src/interfaces/balancer/IAsset.sol";
import "src/interfaces/balancer/IManagedPool.sol";
import "src/interfaces/balancer/FixedPoint.sol";
import "src/interfaces/balancer/WeightedMath.sol";
import "src/interfaces/aura/IRewardPool4626.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";

/**
 * @title  Sushi to Balancer migrator
 * @notice Tool to facilitate migrating a sushi SLP position into a balancer BPT position
 */
contract Migrator is IMigrator, Ownable {
    using SafeERC20 for IERC20;

    uint256 internal constant BPS = 10000;
    uint256 public slippage = 10; // 0.1%
    uint256 public bpsEthToSwap = 6000; // 60%

    uint256 public alchemixPoolId;
    uint256 public sushiPoolId;

    bytes32 public balancerPoolId;

    address public admin;

    IWETH9 public weth;
    IERC20 public alcx;
    IERC20 public bpt;
    IUniswapV2Pair public slp;
    IRewardPool4626 public auraPool;
    AggregatorV3Interface public priceFeed;
    IUniswapV2Router02 public sushiRouter;
    IVault public balancerVault;
    IBasePool public balancerPool;
    IAsset[] public poolAssets = new IAsset[](2);

    constructor(InitializationParams memory params) Ownable() {
        alchemixPoolId = params.alchemixPoolId;
        sushiPoolId = params.sushiPoolId;

        weth = IWETH9(params.weth);
        alcx = IERC20(params.alcx);
        bpt = IERC20(params.bpt);
        slp = IUniswapV2Pair(params.slp);
        auraPool = IRewardPool4626(params.auraPool);
        priceFeed = AggregatorV3Interface(params.priceFeed);
        sushiRouter = IUniswapV2Router02(params.sushiRouter);
        balancerVault = IVault(params.balancerVault);
        balancerPool = IBasePool(address(bpt));
        balancerPoolId = balancerPool.getPoolId();
        poolAssets[0] = IAsset(address(weth));
        poolAssets[1] = IAsset(params.alcx);

        weth.approve(address(balancerVault), type(uint256).max);
    }

    /*
        Admin functions
    */

    /// @inheritdoc IMigrator
    function setUnrwapSlippage(uint256 _amount) external onlyOwner {
        require(_amount <= BPS, "slippage too high");
        slippage = _amount;
    }

    /*
        Public functions
    */

    /// @inheritdoc IMigrator
    function calculateSlpAmounts(uint256 _slpAmount) public view returns (uint256, uint256) {
        uint256 slpSupply = slp.totalSupply();
        (uint256 wethReserves, uint256 alcxReserves, ) = slp.getReserves();

        // Calculate the amount of tokens and ETH the user will receive
        uint256 amountToken = (_slpAmount * alcxReserves) / slpSupply;
        uint256 amountEth = (_slpAmount * wethReserves) / slpSupply;

        // Calculate the minimum amounts with slippage tolerance
        uint256 amountTokenMin = (amountToken * (BPS - slippage)) / BPS;
        uint256 amountEthMin = (amountEth * (BPS - slippage)) / BPS;

        return (amountTokenMin, amountEthMin);
    }

    /// @inheritdoc IMigrator
    function unwrapSlp() public {
        uint256 deadline = block.timestamp + 300;
        uint256 slpAmount = slp.balanceOf(msg.sender);
        // uint256 slpRatio = FixedPoint.divDown(slpAmount, slpSupply);

        (uint256 amountTokenMin, uint256 amountEthMin) = calculateSlpAmounts(slpAmount);

        // uint256 amountEthMin = FixedPoint.mulDown(wethReserves, slpRatio);
        // uint256 amountAlcxMin = FixedPoint.mulDown(alcxReserves, slpRatio);

        slp.approve(address(sushiRouter), slpAmount);
        sushiRouter.removeLiquidityETH(address(alcx), slpAmount, amountTokenMin, amountEthMin, address(this), deadline);
    }

    /// @inheritdoc IMigrator
    function swapEthForAlcx() public {
        (uint256 ethRequired, ) = calculateEthWeight(alcx.balanceOf(address(this)));
        require(address(this).balance > ethRequired, "contract doesn't have enough eth");

        // logic to sell fixed % of eth
        (, int256 alcxEthPrice, , , ) = priceFeed.latestRoundData();
        // uint256 amountEth = (address(this).balance * bpsEthToSwap) / BPS;

        uint256 amountEth = address(this).balance - ethRequired;
        uint256 minAmountOut = (amountEth * uint256(alcxEthPrice)) / 1 ether;
        uint256 deadline = block.timestamp;

        IVault.SingleSwap memory singleSwap = IVault.SingleSwap({
            poolId: balancerPoolId,
            kind: IVault.SwapKind.GIVEN_IN,
            assetIn: IAsset(address(0)),
            assetOut: IAsset(address(alcx)),
            amount: amountEth,
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
    function calculateEthWeight(uint256 _alcxAmount) public view returns (uint256, uint256[] memory) {
        (, int256 alcxEthPrice, , , ) = priceFeed.latestRoundData();

        uint256[] memory normalizedWeights = IManagedPool(address(balancerPool)).getNormalizedWeights();

        uint256 amount = (((_alcxAmount * uint256(alcxEthPrice)) / 1 ether) * normalizedWeights[0]) /
            normalizedWeights[1];

        return (amount, normalizedWeights);
    }

    /// @inheritdoc IMigrator
    function depositIntoBalancerPool(
        uint256 _wethAmount,
        uint256 _alcxAmount,
        uint256[] memory _normalizedWeights
    ) public {
        (, uint256[] memory balances, ) = balancerVault.getPoolTokens(balancerPoolId);

        uint256[] memory amountsIn = new uint256[](2);
        amountsIn[0] = _wethAmount;
        amountsIn[1] = _alcxAmount;

        uint256 bptAmountOut = WeightedMath._calcBptOutGivenExactTokensIn(
            balances,
            _normalizedWeights,
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

        bpt.approve(address(auraPool), amount);
        auraPool.deposit(amount, address(this));
    }

    /*
        External functions
    */

    function migrate(bool stakeBpt) external {
        IERC20(address(slp)).safeTransferFrom(msg.sender, address(this), slp.balanceOf(msg.sender));

        unwrapSlp();

        swapEthForAlcx();

        uint256 alcxAmount = alcx.balanceOf(address(this));
        (uint256 ethAmount, uint256[] memory normalizedWeights) = calculateEthWeight(alcxAmount);

        // weth.deposit{ value: ethAmount }();

        depositIntoBalancerPool(ethAmount, alcxAmount, normalizedWeights);

        if (stakeBpt) depositIntoRewardsPool();
        else bpt.safeTransferFrom(address(this), msg.sender, bpt.balanceOf(address(this)));
    }

    receive() external payable {}
}
