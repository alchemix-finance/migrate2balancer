// SPDX-License-Identifier: GPL-3
pragma solidity ^0.8.15;

interface IMigrator {
    /**
     * @notice Parameters to initialize Migrator
     */
    struct InitializationParams {
        address weth;
        address token;
        address bpt;
        address auraBpt;
        address slp;
        address auraPool;
        address tokenPrice;
        address wethPrice;
        address sushiRouter;
        address balancerVault;
    }

    /**
     * @notice Emitted when an account migrates from SLP to BPT or auraBPT
     * @param account The account migrating
     * @param amountSlp The amount of SLP migrated
     * @param staked Indicates if the account received auraBPT
     */
    event Migrated(address indexed account, uint256 amountSlp, bool staked);

    /**
     * @notice Initialize the contract
     * @param params The contract initialization params
     */
    function initialize(InitializationParams memory params) external;

    /**
     * @notice Update the slippage for unwraping SLP tokens
     * @param _amount The updated slippage amount in bps
     * @dev This function is only callable by the contract owner.
     */
    function setUnrwapSlippage(uint256 _amount) external;

    /**
     * @notice Update the slippage for swapping WETH for TOKEN
     * @param _amount The updated slippage amount in bps
     * @dev This function is only callable by the contract owner.
     */
    function setSwapSlippage(uint256 _amount) external;

    /**
     * @notice Set max approvals for contract tokens
     */
    function setApprovals() external;

    /**
     * @notice Migrate SLP position into BPT position
     * @param stakeBpt indicate if staking BPT in Aura
     */
    function migrate(bool stakeBpt) external;

    /**
     * @notice Deposits msg.senders BPT balance into a rewards pool
     * @dev Way for users to deposit into Aura pool if they already have BPT
     */
    function userDepositIntoRewardsPool() external;
}
