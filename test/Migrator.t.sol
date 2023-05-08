// SPDX-License-Identifier: GPL-3
pragma solidity 0.8.19;

import "./BaseTest.sol";

contract MigratorTest is BaseTest {
    // Test migrating from UniV2 LP to auraBPT
    function test_migrateToAuraBpt(uint256 amount) external {
        // Set amount migrating to be less than 10% of UniV2 LP supply
        uint256 lpSupply = poolToken.totalSupply();
        hevm.assume(amount <= ((lpSupply * 1000) / BPS) && amount > 1 ether);

        // Seed user with UniV2 LP tokens
        deal(address(poolToken), user, amount);

        // User should only have UniV2 LP tokens to start
        assertEq(poolToken.balanceOf(user), amount);
        assertEq(balancerPoolToken.balanceOf(user), 0);
        assertEq(auraPool.balanceOf(user), 0);

        // Get calculation parameters
        MigrationCalcs.MigrationCalcParams memory migrationCalcParams = getMigrationCalcParams(true, amount);

        // Get migration parameters
        IMigrator.MigrationParams memory migrationParams = migrationCalcs.getMigrationParams(migrationCalcParams);

        // Migrate
        hevm.startPrank(user);
        poolToken.approve(address(migrator), amount);
        migrator.migrate(migrationParams);
        hevm.stopPrank();

        // User should only have auraBPT (auraBPT amount > original LP amount)
        assertEq(poolToken.balanceOf(user), 0);
        assertEq(balancerPoolToken.balanceOf(user), 0);
        assertGt(auraPool.balanceOf(user), migrationParams.amountAuraSharesMinimum);

        // Migrator contract should have no funds
        assertEq(weth.balanceOf(address(migrator)), 0);
        assertEq(companionToken.balanceOf(address(migrator)), 0);
        assertEq(balancerPoolToken.balanceOf(address(migrator)), 0);
        assertEq(auraPool.balanceOf(address(migrator)), 0);
        assertEq(poolToken.balanceOf(address(migrator)), 0);
        assertEq((address(migrator).balance), 0);
    }

    // Test migrating from UniV2 LP to BPT
    function test_migrateToBpt(uint256 amount) external {
        // Set amount migrating to be less than 10% of LP supply
        uint256 lpSupply = poolToken.totalSupply();
        hevm.assume(amount <= ((lpSupply * 1000) / BPS) && amount > 1 ether);

        // Seed user with UniV2 LP tokens
        deal(address(poolToken), user, amount);

        // User should only have UniV2 LP tokens to start
        assertEq(poolToken.balanceOf(user), amount);
        assertEq(balancerPoolToken.balanceOf(user), 0);
        assertEq(auraPool.balanceOf(user), 0);

        // Get calculation parameters
        MigrationCalcs.MigrationCalcParams memory migrationCalcParams = getMigrationCalcParams(false, amount);

        // Get migration parameters
        IMigrator.MigrationParams memory migrationParams = migrationCalcs.getMigrationParams(migrationCalcParams);

        // Migrate
        hevm.startPrank(user);
        poolToken.approve(address(migrator), amount);
        migrator.migrate(migrationParams);
        hevm.stopPrank();

        // User should only have BPT (BPT amount > original LP amount)
        assertEq(poolToken.balanceOf(user), 0);
        assertGt(balancerPoolToken.balanceOf(user), migrationParams.amountBalancerLiquidityOut);
        assertEq(auraPool.balanceOf(user), 0);

        // Migrator contract should have no funds
        assertEq(weth.balanceOf(address(migrator)), 0);
        assertEq(companionToken.balanceOf(address(migrator)), 0);
        assertEq(balancerPoolToken.balanceOf(address(migrator)), 0);
        assertEq(auraPool.balanceOf(address(migrator)), 0);
        assertEq(poolToken.balanceOf(address(migrator)), 0);
        assertEq((address(migrator).balance), 0);
    }
}
