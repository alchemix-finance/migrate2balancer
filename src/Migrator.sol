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

/**
 * @title  Sushi to Balancer LP migrator
 * @notice Tool to facilitate migrating Sushi LPs to Balancer or Aura
 * @dev SLP: SushiSwap LP Token
 * @dev BPT: 20WETH-80TOKEN Balancer Pool Token
 * @dev auraBPT: 20WETH-80TOKEN Aura Deposit Vault
 */
contract Migrator is IMigrator {
    using SafeTransferLib for ERC20;

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

    constructor(InitializationParams memory params) {
        weth = WETH(payable(params.weth));
        token = ERC20(params.token);
        balancerPoolToken = ERC20(params.balancerPoolToken);
        auraDepositToken = ERC20(params.auraPool);
        sushiLpToken = IUniswapV2Pair(params.sushiLpToken);
        auraPool = IRewardPool4626(params.auraPool);
        tokenPrice = AggregatorV3Interface(params.tokenPrice);
        sushiRouter = IUniswapV2Router02(params.sushiRouter);
        balancerVault = IVault(params.balancerVault);
        balancerPool = IBasePool(address(balancerPoolToken));
        balancerPoolId = balancerPool.getPoolId();
        poolAssetWeth = IAsset(address(weth));
        poolAssetToken = IAsset(params.token);

        ERC20(address(weth)).safeApprove(address(balancerVault), type(uint256).max);
        token.safeApprove(address(balancerVault), type(uint256).max);
        balancerPoolToken.safeApprove(address(auraPool), type(uint256).max);
        ERC20(address(sushiLpToken)).safeApprove(address(sushiRouter), type(uint256).max);
    }

    /*
        External functions
    */

    /// @inheritdoc IMigrator
    function migrate(
        bool _stakeBpt,
        uint256 _amountTokenMin,
        uint256 _amountWethMin,
        uint256 _wethRequired,
        uint256 _minAmountTokenOut,
        uint256 _amountBptOut
    ) external {
        // uint256 slpBalance = sushiLpToken.balanceOf(msg.sender);

        ERC20(address(sushiLpToken)).safeTransferFrom(msg.sender, address(this), sushiLpToken.balanceOf(msg.sender));

        // Unrwap SLP into TOKEN and WETH
        sushiRouter.removeLiquidityETH(
            address(token),
            sushiLpToken.balanceOf(address(this)),
            _amountTokenMin,
            _amountWethMin,
            address(this),
            block.timestamp
        );
        weth.deposit{ value: address(this).balance }();

        require(weth.balanceOf(address(this)) > _wethRequired, "contract doesn't have enough weth");

        // Swap excess WETH for TOKEN to have balanced 80/20 TOKEN/WETH

        IVault.SingleSwap memory singleSwap = IVault.SingleSwap({
            poolId: balancerPoolId,
            kind: IVault.SwapKind.GIVEN_IN,
            assetIn: poolAssetWeth,
            assetOut: poolAssetToken,
            amount: (weth.balanceOf(address(this)) - _wethRequired),
            userData: bytes("")
        });

        IVault.FundManagement memory funds = IVault.FundManagement({
            sender: address(this),
            fromInternalBalance: false,
            recipient: payable(address(this)),
            toInternalBalance: false
        });

        balancerVault.swap(singleSwap, funds, _minAmountTokenOut, block.timestamp);

        // Deposit into TOKEN/WETH 80/20 balancer pool

        uint256[] memory amountsIn = new uint256[](2);
        amountsIn[0] = weth.balanceOf(address(this));
        amountsIn[1] = token.balanceOf(address(this));

        IAsset[] memory poolAssets = new IAsset[](2);
        poolAssets[0] = poolAssetWeth;
        poolAssets[1] = poolAssetToken;

        bytes memory _userData = abi.encode(
            WeightedPoolUserData.JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT,
            amountsIn,
            _amountBptOut
        );

        IVault.JoinPoolRequest memory request = IVault.JoinPoolRequest({
            assets: poolAssets,
            maxAmountsIn: amountsIn,
            userData: _userData,
            fromInternalBalance: false
        });

        balancerVault.joinPool(balancerPoolId, address(this), address(this), request);

        // msg.sender receives auraBPT or BPT depending on their choice to deposit into Aura pool
        if (_stakeBpt) {
            auraPool.deposit(balancerPoolToken.balanceOf(address(this)), msg.sender);
        } else {
            balancerPoolToken.safeTransferFrom(address(this), msg.sender, balancerPoolToken.balanceOf(address(this)));
        }

        emit Migrated(msg.sender, balancerPoolToken.balanceOf(address(this)), _stakeBpt);
    }

    /// @inheritdoc IMigrator
    function setApprovals() external {
        ERC20(address(weth)).safeApprove(address(balancerVault), type(uint256).max);
        token.safeApprove(address(balancerVault), type(uint256).max);
        balancerPoolToken.safeApprove(address(auraPool), type(uint256).max);
        ERC20(address(sushiLpToken)).safeApprove(address(sushiRouter), type(uint256).max);
    }

    receive() external payable {
        require(msg.sender != address(weth));
    }
}
