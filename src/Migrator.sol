// SPDX-License-Identifier: GPL-3
pragma solidity ^0.8.15;

import "src/interfaces/IMigrator.sol";

/**
 * @title Sushi LP to Balancer LP migrator
 * @notice Tool to facilitate migrating Sushi LPs to Balancer or Aura
 * @dev LP: IUniswapV2Pair LP Token
 * @dev BPT: 20WETH-80TOKEN Balancer Pool Token
 * @dev auraBPT: 20WETH-80TOKEN Aura Deposit Vault
 */
contract Migrator is IMigrator {
    using SafeTransferLib for ERC20;

    WETH public immutable weth;
    IVault public immutable balancerVault;
    IUniswapV2Router02 public immutable router;

    constructor(address wethAddress, address balancerVaultAddress, address routerAddress) {
        weth = WETH(payable(wethAddress));
        balancerVault = IVault(balancerVaultAddress);
        router = IUniswapV2Router02(routerAddress);
    }
    
    /**
     * @inheritdoc IMigrator
     */
    function migrate(MigrationParams calldata params) external {
        validatePairAddress(params.sushiPoolToken);

        // If the user is staking, then the Aura pool asset must be the same as the Balancer pool token
        if (params.stake) {
            require(address(params.balancerPoolToken) == params.auraPool.asset(), "Invalid Aura pool");
        }

        // Grab the two tokens in the balancer vault. If the vault has more than two tokens, the migration will fail.
        bytes32 poolId = params.balancerPoolToken.getPoolId();
        (IERC20[] memory balancerPoolTokens, /* uint256[] memory balances */, /* uint256 lastChangeBlock */) = balancerVault.getPoolTokens(poolId);
        require(balancerPoolTokens.length == 2, "Invalid balancer pool");

        // Require the pool tokens to be the same as the Balancer pool tokens (order agnostic)
        require(
            (params.sushiPoolToken.token0() == address(balancerPoolTokens[0]) && 
             params.sushiPoolToken.token1() == address(balancerPoolTokens[1])) 
            || 
            (params.sushiPoolToken.token0() == address(balancerPoolTokens[1]) && 
             params.sushiPoolToken.token1() == address(balancerPoolTokens[0])),
            "LP token pairs do not match"
        );

        // Transfer the pool tokens to this contract before we conduct any mutations
        ERC20(address(params.sushiPoolToken)).safeTransferFrom(msg.sender, address(this), params.sushiPoolTokensIn);

        // Find which token is not WETH, that is the companion token.
        IERC20 companionToken = balancerPoolTokens[1] == IERC20(address(weth)) ? balancerPoolTokens[0] : balancerPoolTokens[1];

        // Check if the pool token has been approved for the Sushiswap router
        if (params.sushiPoolToken.allowance(address(this), address(router)) < params.sushiPoolTokensIn) {
            ERC20(address(params.sushiPoolToken)).safeApprove(address(router), type(uint256).max);
        }

        // The ordering of `tokenA` and `tokenB` is handled upstream by the Sushiswap router
        router.removeLiquidity({
            tokenA:     address(companionToken),
            tokenB:     address(weth),
            liquidity:  params.sushiPoolTokensIn,
            amountAMin: params.amountCompanionMinimumOut,
            amountBMin: params.amountWETHMinimumOut,
            to:         address(this),
            deadline:   block.timestamp
        });

        require(weth.balanceOf(address(this)) > params.wethRequired, "Contract doesn't have enough weth");

        // Approve the balancer vault to swap and deposit WETH
        ERC20(address(weth)).safeApprove(address(balancerVault), type(uint256).max);

        balancerVault.swap({
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
        assets[0] = IAsset(address(balancerPoolTokens[0]));
        assets[1] = IAsset(address(balancerPoolTokens[1]));

        uint256[] memory maximumAmountsIn = new uint256[](2);
        if (balancerPoolTokens[0] == IERC20(address(weth))) {
            maximumAmountsIn[0] = weth.balanceOf(address(this));
            maximumAmountsIn[1] = companionToken.balanceOf(address(this));
        } else {
            maximumAmountsIn[0] = companionToken.balanceOf(address(this));
            maximumAmountsIn[1] = weth.balanceOf(address(this));
        }

        // Check if the balancer vault has been approved to spend the companion token
        if (ERC20(address(companionToken)).allowance(address(this), address(balancerVault)) < companionToken.balanceOf(address(this))) {
            ERC20(address(companionToken)).safeApprove(address(balancerVault), companionToken.balanceOf(address(this)));
        }

        balancerVault.joinPool({
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

        // Indiate who migrated, amount of LP tokens in, amount of BPT out, and whether the user is staking
        emit Migrated(msg.sender, params.sushiPoolTokensIn, poolTokensReceived, params.stake);
    }

    // Validate the sushi pool address
    function validatePairAddress(IUniswapV2Pair sushiPoolToken) internal view {
        // Get sushi factory
        IUniswapV2Factory sushiFactory = IUniswapV2Factory(router.factory());
        
        // Get the tokens in the pool
        address tokenA = sushiPoolToken.token0();
        address tokenB = sushiPoolToken.token1();

        // Sort the tokens
        if (tokenA > tokenB) {
            (tokenA, tokenB) = (tokenB, tokenA);
        }
        
        // Get the expected pool address
        address expectedPoolAddress = address(uint160(uint256(keccak256(abi.encodePacked(
            hex'ff',
            address(IUniswapV2Factory(router.factory())),
            keccak256(abi.encodePacked(tokenA, tokenB)),
            // Init hash for the SushiSwap factory
            hex'e18a34eb0e04b04f7a0ac29a6e80748dca96319b42c54d679cb821dca90c6303' 
        )))));

        // Get the actual pool address
        address actualPoolAddress = sushiFactory.getPair(tokenA, tokenB);

        // Verify the pool address
        require(expectedPoolAddress == actualPoolAddress, "Pool address verification failed");
    }
}
