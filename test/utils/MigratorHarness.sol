// SPDX-License-Identifier: GPL-3
pragma solidity ^0.8.15;

import "src/Migrator.sol";

/**
 * @title  Migrator Harness Contract
 * @notice Harness contract only for testing internal functions on Migrator
 */
contract MigratorHarness is Migrator {
    constructor(InitializationParams memory params) Migrator(params) {}

    function exposed_calculateWethWeight(uint256 _tokenAmount) external view returns (uint256) {
        return _calculateWethWeight(_tokenAmount);
    }

    function exposed_unwrapSlp(uint256 _amountTokenMin, uint256 _amountWethMin) external {
        return _unwrapSlp(_amountTokenMin, _amountWethMin);
    }

    function exposed_swapWethForTokenBalancer() external {
        return _swapWethForTokenBalancer();
    }

    function exposed_depositIntoBalancerPool() external {
        return _depositIntoBalancerPool();
    }

    function exposed_depositIntoRewardsPool() external {
        return _depositIntoRewardsPool();
    }

    function exposed_tokenPrice() external view returns (uint256) {
        return _tokenPrice();
    }
}
