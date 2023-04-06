// SPDX-License-Identifier: GPL-3
pragma solidity ^0.8.15;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "solmate/src/tokens/ERC20.sol";
import "solmate/src/tokens/WETH.sol";
import "solmate/src/utils/SafeTransferLib.sol";

import "src/interfaces/IMigrator.sol";
import "src/interfaces/balancer/IVault.sol";
import "src/interfaces/balancer/WeightedPoolUserData.sol";
import "src/interfaces/balancer/IBasePool.sol";
import "src/interfaces/balancer/IAsset.sol";
import "src/interfaces/balancer/IBalancerPoolToken.sol";

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

        IVault vault = params.balancerPoolToken.getVault();

        // Grab the tokens in the balancer vault. It is expected that the vault only has two tokens. If the vault
        // has more than two tokens, then the migration will fail.
        bytes32 poolId = params.balancerPoolToken.getPoolId();
        (IERC20[] memory tokens, /* uint256[] memory balances */, /* uint256 lastChangeBlock */) = vault.getPoolTokens(poolId);
        require(tokens.length == 2, "Invalid pool tokens length");

        // Find which token is not WETH, that is the companion token.
        IERC20 companionToken = tokens[1] == IERC20(address(weth)) ? tokens[0] : tokens[1];

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

        // [IMPORTANT]: APPROVAL NEEDED / WETH

        vault.swap({
            singleSwap: IVault.SingleSwap({
                poolId: poolId,
                kind: IVault.SwapKind.GIVEN_IN,
                assetIn: IAsset(address(weth)),
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

        // [IMPORTANT]: APPROVAL NEEDED / WETH + Companion

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

        uint256 poolTokensReceived = params.balancerPoolToken.balanceOf(address(this));

        if (params.stake) {
            // [IMPORTANT]: APPROVAL NEEDED / BPT
            uint256 shares = params.auraPool.deposit(poolTokensReceived, msg.sender);
            require(shares >= params.amountAuraSharesMinimum, "Invalid auraBpt amount out");
        } else {
            ERC20(address(params.balancerPoolToken)).safeTransfer(msg.sender, poolTokensReceived);
        }

        emit Migrated(msg.sender, params.uniswapPoolTokensIn, poolTokensReceived, params.stake);
    }
}
