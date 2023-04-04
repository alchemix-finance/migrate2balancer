// SPDX-License-Identifier: GPL-3
pragma solidity ^0.8.15;

import "src/interfaces/IMigrator.sol";
import "src/interfaces/sushi/IUniswapV2Pair.sol";
import "src/interfaces/sushi/IUniswapV2Router02.sol";
import "src/interfaces/balancer/IVault.sol";
import "src/interfaces/balancer/WeightedPoolUserData.sol";
import "src/interfaces/balancer/IBasePool.sol";
import "src/interfaces/balancer/IAsset.sol";
import "src/interfaces/balancer/IBalancerPoolToken.sol";
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

    WETH public immutable weth = WETH(payable(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2));

    /*
        External functions
    */

    /// @inheritdoc IMigrator
    function migrate(MigrationParams calldata _params) external {
        bytes32 balancerPoolId = IBasePool(_params.balancerPoolToken).getPoolId();
        IVault balancerVault = IBalancerPoolToken(_params.balancerPoolToken).getVault();
        address token = IUniswapV2Pair(_params.lpToken).token1();
        (IERC20[] memory tokens, , ) = balancerVault.getPoolTokens(balancerPoolId);

        require(address(tokens[0]) == address(weth), "Migrator intended to be used for WETH/TOKEN Balancer pools");
        require(address(tokens[1]) == token, "LP and Balancer LP pairs do not match");

        _setApprovals(
            address(balancerVault),
            token,
            _params.balancerPoolToken,
            _params.auraPool,
            _params.lpToken,
            _params.router
        );

        ERC20(_params.lpToken).safeTransferFrom(msg.sender, address(this), _params.lpAmount);

        // Unrwap LP into TOKEN and WETH
        IUniswapV2Router02(_params.router).removeLiquidityETH(
            token,
            _params.lpAmount,
            _params.amountTokenMin,
            _params.amountWethMin,
            address(this),
            block.timestamp
        );
        weth.deposit{ value: address(this).balance }();

        require(weth.balanceOf(address(this)) > _params.wethRequired, "Contract doesn't have enough weth");

        // Swap excess WETH for TOKEN to have balanced 80/20 TOKEN/WETH

        IVault.SingleSwap memory singleSwap = IVault.SingleSwap({
            poolId: balancerPoolId,
            kind: IVault.SwapKind.GIVEN_IN,
            assetIn: IAsset(address(weth)),
            assetOut: IAsset(token),
            amount: (weth.balanceOf(address(this)) - _params.wethRequired),
            userData: bytes("")
        });

        IVault.FundManagement memory funds = IVault.FundManagement({
            sender: address(this),
            fromInternalBalance: false,
            recipient: payable(address(this)),
            toInternalBalance: false
        });

        balancerVault.swap(singleSwap, funds, _params.minAmountTokenOut, block.timestamp);

        // Deposit into TOKEN/WETH 80/20 balancer pool

        uint256[] memory amountsIn = new uint256[](2);
        amountsIn[0] = ERC20(address(tokens[0])).balanceOf(address(this));
        amountsIn[1] = ERC20(address(tokens[1])).balanceOf(address(this));

        IAsset[] memory poolAssets = new IAsset[](2);
        poolAssets[0] = IAsset(address(tokens[0]));
        poolAssets[1] = IAsset(address(tokens[1]));

        bytes memory _userData = abi.encode(
            WeightedPoolUserData.JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT,
            amountsIn,
            _params.amountBptOut
        );

        IVault.JoinPoolRequest memory request = IVault.JoinPoolRequest({
            assets: poolAssets,
            maxAmountsIn: amountsIn,
            userData: _userData,
            fromInternalBalance: false
        });

        balancerVault.joinPool(balancerPoolId, address(this), address(this), request);

        uint256 amountReceived = ERC20(_params.balancerPoolToken).balanceOf(address(this));

        // msg.sender receives auraBPT or BPT depending on their choice to deposit into Aura pool
        if (_params.stakeBpt) {
            require(_params.balancerPoolToken == IRewardPool4626(_params.auraPool).asset(), "Invalid Aura pool");

            IRewardPool4626(_params.auraPool).deposit(amountReceived, address(msg.sender));

            require(
                ERC20(_params.auraPool).balanceOf(address(msg.sender)) >= _params.amountAuraBptOut,
                "Invalid auraBpt amount out"
            );
        } else {
            ERC20(_params.balancerPoolToken).safeTransferFrom(address(this), msg.sender, amountReceived);
        }

        emit Migrated(msg.sender, _params.lpAmount, amountReceived, _params.stakeBpt);
    }

    /**
     * @notice Set approvals necessary for migration
     */
    function _setApprovals(
        address _balancerVault,
        address _token,
        address _balancerPoolToken,
        address _auraPool,
        address _lpToken,
        address _router
    ) internal {
        ERC20(address(weth)).safeApprove(_balancerVault, type(uint256).max);
        ERC20(_token).safeApprove(_balancerVault, type(uint256).max);
        ERC20(_balancerPoolToken).safeApprove(_auraPool, type(uint256).max);
        ERC20(_lpToken).safeApprove(_router, type(uint256).max);
    }

    receive() external payable {
        require(msg.sender != address(weth));
    }
}
