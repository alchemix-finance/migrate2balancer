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
        address priceFeed;
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
     * @notice Calculate the min amount of TOKEN and WETH for a given SLP amount
     * @param _slpAmount The amount of SLP
     * @return Return values for min amount out of TOKEN and WETH with unwrap slippage
     */
    function calculateSlpAmounts(uint256 _slpAmount) external returns (uint256, uint256);

    /**
     * @notice Unrwap SLP into TOKEN and WETH
     */
    function unwrapSlp() external;

    /**
     * @notice Swap WETH for TOKEN to have balanced 80/20 TOKEN/WETH
     */
    function swapWethForTokenBalancer() external;

    /**
     * @notice Get the amount WETH required to create balanced pool deposit
     * @param _tokenAmount Amount of TOKEN to deposit
     * @return uint256 Amount of WETH required to create 80/20 balanced deposit
     */
    function calculateWethWeight(uint256 _tokenAmount) external returns (uint256);

    /**
     * @notice Deposit into TOKEN/WETH 80/20 balancer pool
     */
    function depositIntoBalancerPool() external;

    /**
     * @notice Deposit BPT into rewards pool
     */
    function depositIntoRewardsPool() external;

    /**
     * @notice Deposits msg.senders BPT balance into a rewards pool
     * @dev Way for users to deposit into Aura pool if they already have BPT
     */
    function userDepositIntoRewardsPool() external;

    /**
     * @notice Migrate SLP position into BPT position
     * @param stakeBpt indicate if staking BPT in Aura
     */
    function migrate(bool stakeBpt) external;
}
