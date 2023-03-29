// SPDX-License-Identifier: GPL-3
pragma solidity ^0.8.15;

import "src/Migrator.sol";

contract MigratorHarness is Migrator {
    function exposed_calculateSlpAmounts(uint256 _slpAmount) external view returns (uint256, uint256) {
        return _calculateSlpAmounts(_slpAmount);
    }

    function exposed_calculateWethWeight(uint256 _tokenAmount) external view returns (uint256) {
        return _calculateWethWeight(_tokenAmount);
    }

    function exposed_unwrapSlp() external {
        return _unwrapSlp();
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
}
