// SPDX-License-Identifier: GPL-3
pragma solidity ^0.8.15;

interface IMigrator {
    struct InitializationParams {
        uint256 alchemixPoolId;
        uint256 sushiPoolId;
        address weth;
        address alcx;
        address bpt;
        address auraBpt;
        address slp;
        address auraPool;
        address priceFeed;
        address sushiRouter;
        address balancerVault;
    }

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
     * @notice Update the slippage for swapping WETH for ALCX
     * @param _amount The updated slippage amount in bps
     * @dev This function is only callable by the contract owner.
     */
    function setSwapSlippage(uint256 _amount) external;

    /**
     * @notice Calculate the min amount of ALCX and WETH for a given SLP amount
     * @param _slpAmount The amount of SLP
     * @return Return values for min amount out of ALCX and WETH with unwrap slippage
     */
    function calculateSlpAmounts(uint256 _slpAmount) external view returns (uint256, uint256);

    /**
     * @notice Unrwap SLP into ALCX and WETH
     */
    function unwrapSlp() external;

    /**
     * @notice Swap WETH for ALCX to have balanced 80/20 ALCX/WETH
     */
    function swapWethForAlcxBalancer() external;

    /**
     * @notice Get the amount WETH required to create balanced pool deposit
     * @param _alcxAmount Amount of ALCX to deposit
     * @return uint256 Amount of WETH required to create 80/20 balanced deposit
     */
    function calculateWethWeight(uint256 _alcxAmount) external view returns (uint256);

    /**
     * @notice Deposit into ALCX/WETH 80/20 balancer pool
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
