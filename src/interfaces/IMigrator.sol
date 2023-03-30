// SPDX-License-Identifier: GPL-3
pragma solidity ^0.8.15;

import "solmate/src/tokens/WETH.sol";

interface IMigrator {
    /**
     * @notice Parameters to initialize Migrator
     */
    struct InitializationParams {
        address weth;
        address token;
        address balancerPoolToken;
        address auraDepositToken;
        address sushiLpToken;
        address auraPool;
        address tokenPrice;
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
     * @param _stakeBpt Indicate if staking BPT in Aura
     * @param _amountTokenMin Min amount of token out when unwrapping SLP
     * @param _amountWethMin Min amount of WETH out when unwrapping SLP
     */
    function migrate(bool _stakeBpt, uint256 _amountTokenMin, uint256 _amountWethMin) external;
}
