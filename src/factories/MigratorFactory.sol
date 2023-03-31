// SPDX-License-Identifier: GPL-3
pragma solidity ^0.8.15;

import "src/Migrator.sol";

contract MigratorFactory {
    function createMigrator(IMigrator.InitializationParams memory params) external returns (address) {
        return address(new Migrator(params));
    }
}
