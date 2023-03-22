// SPDX-License-Identifier: GPL-3
pragma solidity ^0.8.15;

interface IMigrator {
    struct InitializationParams {
        uint256 alchemixPoolId;
        uint256 sushiPoolId;
        address weth;
        address alcx;
        address sushi;
        address bpt;
        address slp;
        address auraPool;
        address alchemixStakingPool;
        address sushiStakingPool;
        address priceFeed;
        address sushiRouter;
        address balancerVault;
    }

    /**
     * @notice Withdraw SLP from sushi staking pool, claiming any ALCX and SUSHI rewards
     * @dev SUSHI rewards are sent to the account that is migrating
     */
    function withdrawFromSushiPool() external;

    /**
     * @notice Withdraw SLP from alchemix staking pool, claiming any ALCX rewards
     */
    function withdrawFromAlchemixPool() external;

    /**
     * @notice Unrwap SLP into ALCX and ETH
     */
    function unwrapSlp() external;

    /**
     * @notice Swap ETH for ALCX to have balanced 80/20 ALCX/ETH
     */
    function swapEthForAlcx() external;

    /**
     * @notice Get the amount of ETH or WETH required to create balanced pool deposit
     * @param _alcxAmount Amount of ALCX to deposit
     * @return uint256 Amount of ETH or WETH required to create 80/20 balanced deposit
     * @return uint256[] Normalized weights of the pool. Prevents an additional lookup of weights
     */
    function calculateEthWeight(uint256 _alcxAmount) external view returns (uint256, uint256[] memory);

    /**
     * @notice Deposit into ALCX/WETH 80/20 balancer pool
     * @param _wethAmount Amount of WETH to deposit into pool
     * @param _alcxAmount Amount of ALCX to deposit into pool
     * @param _normalizedWeights Weight of ALCX and WETH
     */
    function depositIntoBalancerPool(
        uint256 _wethAmount,
        uint256 _alcxAmount,
        uint256[] memory _normalizedWeights
    ) external;

    /**
     * @notice Deposit BPT into rewards pool
     */
    function depositIntoRewardsPool() external;

    /**
     * @notice Migrate SLP position into BPT position
     * @param fromSlpFarm indicate if migrating from sushi staking pool
     * @param fromAlcxFarm indicate if migrating from alchemix staking pool
     * @param stakeBpt indicate if staking BPT in Aura
     */
    function migrate(bool fromSlpFarm, bool stakeBpt, bool fromAlcxFarm) external;
}
