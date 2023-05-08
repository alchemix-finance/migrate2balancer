// SPDX-License-Identifier: GPL-3
pragma solidity 0.8.19;

import "./BaseTest.sol";

contract MigratorTest is BaseTest {
    // Test migrating from LP to auraBPT
    function test_migrateToAuraBpt(uint256 amount) external {
        // Set amount migrating to be less than 10% of LP supply
        uint256 lpSupply = lpToken.totalSupply();
        hevm.assume(amount <= ((lpSupply * 1000) / BPS) && amount > 1 ether);

        // Seed user with LP
        deal(address(lpToken), user, amount);

        // User should only have LP
        assertEq(lpToken.balanceOf(user), amount);
        assertEq(balancerPoolToken.balanceOf(user), 0);
        assertEq(auraPool.balanceOf(user), 0);

        // Calculation parameters
        MigrationCalcs.MigrationCalcParams memory migrationCalcParams = getMigrationCalcParams(true, amount);

        // Migration parameters
        IMigrator.MigrationParams memory migrationParams = migrationCalcs.getMigrationParams(migrationCalcParams);

        // Migrate
        hevm.startPrank(user);
        lpToken.approve(address(migrator), amount);
        migrator.migrate(migrationParams);
        hevm.stopPrank();

        // User should only have auraBPT (auraBPT amount > original LP amount)
        assertEq(lpToken.balanceOf(user), 0);
        assertEq(balancerPoolToken.balanceOf(user), 0);
        assertGt(auraPool.balanceOf(user), migrationParams.amountAuraSharesMinimum);

        // Migrator should have no funds
        assertEq(weth.balanceOf(address(migrator)), 0);
        assertEq(companionToken.balanceOf(address(migrator)), 0);
        assertEq(balancerPoolToken.balanceOf(address(migrator)), 0);
        assertEq(auraPool.balanceOf(address(migrator)), 0);
        assertEq(lpToken.balanceOf(address(migrator)), 0);
        assertEq((address(migrator).balance), 0);
    }

    // Test migrating from LP to BPT
    function test_migrateToBpt(uint256 amount) external {
        // Set amount migrating to be less than 10% of LP supply
        uint256 lpSupply = lpToken.totalSupply();
        hevm.assume(amount <= ((lpSupply * 1000) / BPS) && amount > 1 ether);

        // Seed user with LP
        deal(address(lpToken), user, amount);

        // User should only have LP
        assertEq(lpToken.balanceOf(user), amount);
        assertEq(balancerPoolToken.balanceOf(user), 0);
        assertEq(auraPool.balanceOf(user), 0);

        // Calculation parameters
        MigrationCalcs.MigrationCalcParams memory migrationCalcParams = getMigrationCalcParams(false, amount);

        // Migration parameters
        IMigrator.MigrationParams memory migrationParams = migrationCalcs.getMigrationParams(migrationCalcParams);

        // Migrate
        hevm.startPrank(user);
        lpToken.approve(address(migrator), amount);
        migrator.migrate(migrationParams);
        hevm.stopPrank();

        // User should only have BPT (BPT amount > original LP amount)
        assertEq(lpToken.balanceOf(user), 0);
        assertGt(balancerPoolToken.balanceOf(user), migrationParams.amountBalancerLiquidityOut);
        assertEq(auraPool.balanceOf(user), 0);

        // Migrator should have no funds
        assertEq(weth.balanceOf(address(migrator)), 0);
        assertEq(companionToken.balanceOf(address(migrator)), 0);
        assertEq(balancerPoolToken.balanceOf(address(migrator)), 0);
        assertEq(auraPool.balanceOf(address(migrator)), 0);
        assertEq(lpToken.balanceOf(address(migrator)), 0);
        assertEq((address(migrator).balance), 0);
    }
}
