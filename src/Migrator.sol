// SPDX-License-Identifier: GPL-3
pragma solidity ^0.8.15;

import "src/interfaces/IMigrator.sol";
import "src/interfaces/sushi/IUniswapV2Pair.sol";
import "src/interfaces/sushi/IUniswapV2Router02.sol";
import "src/interfaces/balancer/IVault.sol";
import "src/interfaces/balancer/WeightedPoolUserData.sol";
import "src/interfaces/balancer/IBasePool.sol";
import "src/interfaces/balancer/IAsset.sol";
import "src/interfaces/aura/IRewardPool4626.sol";
import "solmate/src/tokens/ERC20.sol";
import "solmate/src/tokens/WETH.sol";
import "solmate/src/utils/SafeTransferLib.sol";

/**
 * @title UniV2 LP to Balancer LP migrator
 * @notice Tool to facilitate migrating UniV2 LPs to Balancer or Aura
 * @dev LP: IUniswapV2Pair LP Token
 * @dev BPT: 20WETH-80TOKEN Balancer Pool Token
 * @dev auraBPT: 20WETH-80TOKEN Aura Deposit Vault
 */
contract Migrator is IMigrator {
    using SafeTransferLib for ERC20;

    uint256 public immutable BPS = 10000;
    WETH public immutable weth = WETH(payable(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2));

    /*
        External functions
    */

    /// @inheritdoc IMigrator
    function migrate(MigrationAddresses memory _addresses, MigrationDetails memory _details) external {
        _setApprovals(_addresses);

        uint256 lpAmount = ERC20(_addresses.lpToken).balanceOf(msg.sender);
        bytes32 balancerPoolId = IBasePool(_addresses.balancerPoolToken).getPoolId();

        ERC20(_addresses.lpToken).safeTransferFrom(msg.sender, address(this), lpAmount);

        // Unrwap LP into TOKEN and WETH
        IUniswapV2Router02(_addresses.router).removeLiquidityETH(
            _addresses.token,
            lpAmount,
            _details.amountTokenMin,
            _details.amountWethMin,
            address(this),
            block.timestamp
        );
        weth.deposit{ value: address(this).balance }();

        require(weth.balanceOf(address(this)) > _details.wethRequired, "contract doesn't have enough weth");

        // Swap excess WETH for TOKEN to have balanced 80/20 TOKEN/WETH

        IVault.SingleSwap memory singleSwap = IVault.SingleSwap({
            poolId: balancerPoolId,
            kind: IVault.SwapKind.GIVEN_IN,
            assetIn: IAsset(address(weth)),
            assetOut: IAsset(_addresses.token),
            amount: (weth.balanceOf(address(this)) - _details.wethRequired),
            userData: bytes("")
        });

        IVault.FundManagement memory funds = IVault.FundManagement({
            sender: address(this),
            fromInternalBalance: false,
            recipient: payable(address(this)),
            toInternalBalance: false
        });

        IVault(_addresses.balancerVault).swap(singleSwap, funds, _details.minAmountTokenOut, block.timestamp);

        // Deposit into TOKEN/WETH 80/20 balancer pool

        uint256[] memory amountsIn = new uint256[](2);
        amountsIn[0] = weth.balanceOf(address(this));
        amountsIn[1] = ERC20(_addresses.token).balanceOf(address(this));

        IAsset[] memory poolAssets = new IAsset[](2);
        poolAssets[0] = IAsset(address(weth));
        poolAssets[1] = IAsset(_addresses.token);

        bytes memory _userData = abi.encode(
            WeightedPoolUserData.JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT,
            amountsIn,
            _details.amountBptOut
        );

        IVault.JoinPoolRequest memory request = IVault.JoinPoolRequest({
            assets: poolAssets,
            maxAmountsIn: amountsIn,
            userData: _userData,
            fromInternalBalance: false
        });

        IVault(_addresses.balancerVault).joinPool(balancerPoolId, address(this), address(this), request);

        uint256 amountReceived = ERC20(_addresses.balancerPoolToken).balanceOf(address(this));

        // msg.sender receives auraBPT or BPT depending on their choice to deposit into Aura pool
        if (_details.stakeBpt) {
            IRewardPool4626(_addresses.auraPool).deposit(amountReceived, msg.sender);
        } else {
            ERC20(_addresses.balancerPoolToken).safeTransferFrom(address(this), msg.sender, amountReceived);
        }

        emit Migrated(msg.sender, lpAmount, amountReceived, _details.stakeBpt);
    }

    /**
     * @notice Set approvals necessary for migration
     * @param _addresses struct containing necessary addresses
     */
    function _setApprovals(MigrationAddresses memory _addresses) internal {
        ERC20(address(weth)).safeApprove(_addresses.balancerVault, type(uint256).max);
        ERC20(_addresses.token).safeApprove(_addresses.balancerVault, type(uint256).max);
        ERC20(_addresses.balancerPoolToken).safeApprove(_addresses.auraPool, type(uint256).max);
        ERC20(_addresses.lpToken).safeApprove(_addresses.router, type(uint256).max);
    }

    receive() external payable {
        require(msg.sender != address(weth));
    }
}
