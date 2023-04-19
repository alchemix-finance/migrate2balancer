// SPDX-License-Identifier: GPL-3
pragma solidity ^0.8.15;

import "src/interfaces/IMigrator.sol";

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

    /**
     * @inheritdoc IMigrator
     */
    function migrate(MigrationParams calldata params) external {
        // If the user is staking, then the Aura pool asset must be the same as the Balancer pool token
        if (params.stake) {
            require(address(params.balancerPoolToken) == params.auraPool.asset(), "Invalid Aura pool");
        }

        // Preemptively transfer the Uniswap pool tokens to this contract before we conduct any mutations
        ERC20(address(params.uniswapPoolToken)).safeTransferFrom(msg.sender, address(this), params.uniswapPoolTokensIn);

        IVault vault = IBalancerPoolToken(address(params.balancerPoolToken)).getVault();

        // Grab the two tokens in the balancer vault. If the vault has more than two tokens, the migration will fail.
        bytes32 poolId = params.balancerPoolToken.getPoolId();
        (IERC20[] memory tokens, /* uint256[] memory balances */, /* uint256 lastChangeBlock */) = vault.getPoolTokens(poolId);
        require(tokens.length == 2, "Invalid pool tokens length");

        // Find which token is not WETH, that is the companion token.
        IERC20 companionToken = tokens[1] == IERC20(address(weth)) ? tokens[0] : tokens[1];

        // Check if the Uniswap pool token has been approved for the Uniswap router
        if (params.uniswapPoolToken.allowance(address(this), address(params.router)) < params.uniswapPoolTokensIn) {
            ERC20(address(params.uniswapPoolToken)).safeApprove(address(params.router), type(uint256).max);
        }

        // The ordering of `tokenA` and `tokenB` is handled upstream by the Uniswap router
        params.router.removeLiquidity({
            tokenA:     address(companionToken),
            tokenB:     address(weth),
            liquidity:  params.uniswapPoolTokensIn,
            amountAMin: params.amountCompanionMinimumOut,
            amountBMin: params.amountWETHMinimumOut,
            to:         address(this),
            deadline:   block.timestamp
        });

        require(weth.balanceOf(address(this)) > params.wethRequired, "Contract doesn't have enough weth");

        // Approve the balancer vault to swap and deposit WETH
        ERC20(address(weth)).safeApprove(address(vault), type(uint256).max);

        vault.swap({
            singleSwap:  IVault.SingleSwap({
                poolId: poolId,
                kind: IVault.SwapKind.GIVEN_IN,
                assetIn:  IAsset(address(weth)),
                assetOut: IAsset(address(companionToken)),
                amount: weth.balanceOf(address(this)) - params.wethRequired,
                userData: bytes("")
            }),
            funds: IVault.FundManagement({
                sender: address(this),
                fromInternalBalance: false,
                recipient: payable(address(this)),
                toInternalBalance: false
            }),
            limit: params.minAmountTokenOut,
            deadline: block.timestamp
        });

        IAsset[] memory assets = new IAsset[](2);
        assets[0] = IAsset(address(tokens[0]));
        assets[1] = IAsset(address(tokens[1]));

        uint256[] memory maximumAmountsIn = new uint256[](2);
        if (tokens[0] == IERC20(address(weth))) {
            maximumAmountsIn[0] = weth.balanceOf(address(this));
            maximumAmountsIn[1] = companionToken.balanceOf(address(this));
        } else {
            maximumAmountsIn[0] = companionToken.balanceOf(address(this));
            maximumAmountsIn[1] = weth.balanceOf(address(this));
        }

        // Check if the balancer vault has been approved to spend the companion token
        if (ERC20(address(companionToken)).allowance(address(this), address(vault)) < companionToken.balanceOf(address(this))) {
            ERC20(address(companionToken)).safeApprove(address(vault), companionToken.balanceOf(address(this)));
        }

        vault.joinPool({
            poolId: poolId,
            sender: address(this),
            recipient: address(this),
            request: IVault.JoinPoolRequest({
                assets: assets,
                maxAmountsIn: maximumAmountsIn,
                userData: abi.encode(
                    WeightedPoolUserData.JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT,
                    maximumAmountsIn,
                    params.amountBalancerLiquidityOut
                ),
                fromInternalBalance: false
            })
        });

        // Get the amount of BPT received since joinPool does not return the amount
        uint256 poolTokensReceived = params.balancerPoolToken.balanceOf(address(this));

        // If the user is staking, we deposit BPT into the Aura pool on the user's behalf
        // Otherwise, we transfer the BPT to the user
        if (params.stake) {
            ERC20(address(params.balancerPoolToken)).safeApprove(address(params.auraPool), poolTokensReceived);
            uint256 shares = params.auraPool.deposit(poolTokensReceived, msg.sender);
            require(shares >= params.amountAuraSharesMinimum, "Invalid auraBpt amount out");
        } else {
            ERC20(address(params.balancerPoolToken)).safeTransfer(msg.sender, poolTokensReceived);
        }

        // Indiate who migrated, amount of UniV2 LP tokens in, amount of BPT out, and whether the user is staking
        emit Migrated(msg.sender, params.uniswapPoolTokensIn, poolTokensReceived, params.stake);
    }
}
