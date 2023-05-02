// SPDX-License-Identifier: GPL-3
pragma solidity ^0.8.15;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "solmate/src/tokens/ERC20.sol";
import "solmate/src/tokens/WETH.sol";
import "solmate/src/utils/SafeTransferLib.sol";

import "src/interfaces/balancer/IVault.sol";
import "src/interfaces/balancer/WeightedPoolUserData.sol";
import "src/interfaces/balancer/IAsset.sol";
import "src/interfaces/balancer/IBalancerPoolToken.sol";
import "src/interfaces/balancer/IBasePool.sol";
import "src/interfaces/aura/IRewardPool4626.sol";
import "src/interfaces/univ2/IUniswapV2Pair.sol";
import "src/interfaces/univ2/IUniswapV2Router02.sol";
import "src/interfaces/univ2/IUniswapV2Factory.sol";

interface IMigrator {
    /**
     * @notice Represents the addresses, migration details, and calculations required for migration
     */
    struct MigrationParams {
        // 80/20 TOKEN/WETH Balancer Pool Token
        IBasePool balancerPoolToken;
        // UniV2 50/50 TOKEN/WETH LP Token
        IUniswapV2Pair sushiPoolToken;
        // ERC4626 Aura pool address
        IRewardPool4626 auraPool;
        // Amount of LP tokens to be migrated
        uint256 sushiPoolTokensIn;
        // Minimum amount of Tokens to be received from the LP
        uint256 amountCompanionMinimumOut;
        // Minimum amount of WETH to be received from the LP
        uint256 amountWETHMinimumOut;
        // Amount of WETH required to create an 80/20 TOKEN/WETH balance
        uint256 wethRequired;
        // Minimum amount of Tokens from swapping excess WETH due to the 80/20 TOKEN/WETH rebalance (amountWethMin is always > wethRequired)
        uint256 minAmountTokenOut;
        // Amount of BPT to be received given the rebalanced Token and WETH amounts
        uint256 amountBalancerLiquidityOut;
        // Amount of auraBPT to be received given the amount of BPT deposited
        uint256 amountAuraSharesMinimum;
        // Indicates whether to stake the migrated BPT in the Aura pool
        bool stake;
    }

    /**
     * @notice Emitted when an account migrates from UniV2 LP to BPT or auraBPT
     * @param account The account migrating
     * @param lpAmountMigrated Amount of LP tokens migrated
     * @param amountReceived The amount of BPT received
     * @param staked Indicates if the account is staking BPT in the Aura pool
     */
    event Migrated(address indexed account, uint256 lpAmountMigrated, uint256 amountReceived, bool staked);

    /**
     * @notice Migrate UniV2 LP position into BPT position
     * @param params Migration addresses, details, and calculations
     */
    function migrate(MigrationParams calldata params) external;
}
