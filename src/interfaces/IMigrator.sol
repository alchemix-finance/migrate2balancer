// SPDX-License-Identifier: GPL-3
pragma solidity ^0.8.15;

interface IMigrator {
    /**
     * @notice Represents the addresses required for migration
     */
    struct MigrationAddresses {
        address token; // Token in the TOKEN/WETH LP position
        address balancerPoolToken; // 80/20 TOKEN/WETH Balancer Pool Token
        address lpToken; // UniV2 50/50 TOKEN/WETH LP Token
        address auraPool; // ERC4626 Aura pool address
        address router; // UniV2 Router for unwrapping the LP token
        address balancerVault; // Balancer Vault for swapping WETH to TOKEN and joining the TOKEN/WETH 80/20 pool
    }

    /**
     * @notice Represents the migration details and calculations
     */
    struct MigrationDetails {
        bool stakeBpt; // Indicates whether to stake the migrated BPT in the Aura pool
        uint256 amountTokenMin; // Minimum amount of Tokens to be received from the LP
        uint256 amountWethMin; // Minimum amount of WETH to be received from the LP
        uint256 wethRequired; // Amount of WETH required to create an 80/20 TOKEN/WETH balance
        uint256 minAmountTokenOut; // Minimum amount of Tokens from swapping excess WETH due to the 80/20 TOKEN/WETH rebalance (amountWethMin is always > wethRequired)
        uint256 amountBptOut; // Amount of BPT to be received given the rebalanced Token and WETH amounts
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
     * @param _addresses Migration addresses struct
     * @param _details Migration details struct
     */
    function migrate(MigrationAddresses memory _addresses, MigrationDetails memory _details) external;
}
