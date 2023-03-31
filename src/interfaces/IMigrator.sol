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
        address sushiLpToken;
        address auraPool;
        address tokenPrice;
        address sushiRouter;
        address balancerVault;
    }

    /**
     * @notice Emitted when an account migrates from SLP to BPT or auraBPT
     * @param account The account migrating
     * @param amountBpt The amount of BPT minted
     * @param staked Indicates if the account received auraBPT
     */
    event Migrated(address indexed account, uint256 amountBpt, bool staked);

    /**
     * @notice Migrate SLP position into BPT position
     * @param _stakeBpt Indicate if staking BPT in Aura
     * @param _amountTokenMin Min amount of Token out when unwrapping SLP
     * @param _amountWethMin Min amount of WETH out when unwrapping SLP
     * @param _wethRequired Amount of WETH required to get 80/20 balance when SLP is unwrapped
     * @param _minAmountTokenOut Amount of Token out when swapping excess WETH after rebalanced to 80/20
     * @param _amountBptOut Amount of BPT out given Tokens and WETH deposit into Balancer
     */
    function migrate(
        bool _stakeBpt,
        uint256 _amountTokenMin,
        uint256 _amountWethMin,
        uint256 _wethRequired,
        uint256 _minAmountTokenOut,
        uint256 _amountBptOut
    ) external;

    /**
     * @notice Set max approvals for contract tokens
     */
    function setApprovals() external;
}
