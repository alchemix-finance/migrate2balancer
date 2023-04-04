// SPDX-License-Identifier: GPL-3
pragma solidity ^0.8.15;

interface IMigrator {
    /**
     * @notice Represents the addresses, migration details, and calculations required for migration
     */
    struct MigrationParams {
        // 80/20 TOKEN/WETH Balancer Pool Token
        address balancerPoolToken;
        // UniV2 50/50 TOKEN/WETH LP Token
        address lpToken;
        // ERC4626 Aura pool address
        address auraPool;
        // UniV2 Router for unwrapping the LP token
        address router;
        // Indicates whether to stake the migrated BPT in the Aura pool
        bool stakeBpt;
        // Amount of LP tokens to be migrated
        uint256 lpAmount;
        // Minimum amount of Tokens to be received from the LP
        uint256 amountTokenMin;
        // Minimum amount of WETH to be received from the LP
        uint256 amountWethMin;
        // Amount of WETH required to create an 80/20 TOKEN/WETH balance
        uint256 wethRequired;
        // Minimum amount of Tokens from swapping excess WETH due to the 80/20 TOKEN/WETH rebalance (amountWethMin is always > wethRequired)
        uint256 minAmountTokenOut;
        // Amount of BPT to be received given the rebalanced Token and WETH amounts
        uint256 amountBptOut;
        // Amount of auraBPT to be received given the amount of BPT deposited
        uint256 amountAuraBptOut;
    }

    /**
     * @notice Emitted when an account migrates from SLP to BPT or auraBPT
     * @param account The account migrating
     * @param lpAmountMigrated Amount of LP tokens migrated
     * @param amountReceived The amount of BPT or auraBPT received
     * @param staked Indicates if the account received auraBPT
     */
    event Migrated(address indexed account, uint256 lpAmountMigrated, uint256 amountReceived, bool staked);

    /**
     * @notice Migrate SLP position into BPT position
     * @param _params Migration addresses, details, and calculations
     */
    function migrate(MigrationParams calldata _params) external;
}
