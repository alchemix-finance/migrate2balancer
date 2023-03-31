// SPDX-License-Identifier: GPL-3
pragma solidity ^0.8.15;

import "./BaseTest.sol";

contract MigratorTest is BaseTest {
    // Test migrating from SLP to auraBPT
    function test_migrateToAuraBpt(uint256 _amount) external {
        // Set range to be less than 10% of SLP supply
        uint256 slpSupply = sushiLpToken.totalSupply();
        hevm.assume(_amount <= ((slpSupply * 1000) / BPS) && _amount > 1 ether);

        // Seed user with SLP
        deal(address(sushiLpToken), user, _amount);

        // User should only have SLP
        assertEq(sushiLpToken.balanceOf(user), _amount);
        assertEq(balancerPoolToken.balanceOf(user), 0);
        assertEq(auraDepositToken.balanceOf(user), 0);

        // Parameters to be calculated off-chain
        (
            uint256 amountTokenMin,
            uint256 amountWethMin,
            uint256 wethRequired,
            uint256 minAmountTokenOut,
            uint256 amountBptOut
        ) = offChainParams(_amount);

        hevm.startPrank(user);
        sushiLpToken.approve(address(migrator), _amount);
        migrator.migrate(true, amountTokenMin, amountWethMin, wethRequired, minAmountTokenOut, amountBptOut);
        hevm.stopPrank();

        // User should only have auraBPT (auraBPT amount > original SLP amount)
        assertEq(sushiLpToken.balanceOf(user), 0);
        assertEq(balancerPoolToken.balanceOf(user), 0);
        assertGt(auraDepositToken.balanceOf(user), _amount);

        // Migrator should have no funds
        assertEq(weth.balanceOf(address(migrator)), 0);
        assertEq(token.balanceOf(address(migrator)), 0);
        assertEq(balancerPoolToken.balanceOf(address(migrator)), 0);
        assertEq(auraDepositToken.balanceOf(address(migrator)), 0);
        assertEq(sushiLpToken.balanceOf(address(migrator)), 0);
        assertEq((address(migrator).balance), 0);
    }

    // Test migrating from SLP to BPT
    function test_migrateToBpt(uint256 _amount) external {
        // Set range to be less than 10% of SLP supply
        uint256 slpSupply = sushiLpToken.totalSupply();
        hevm.assume(_amount <= ((slpSupply * 1000) / BPS) && _amount > 1 ether);

        // Seed user with SLP
        deal(address(sushiLpToken), user, _amount);

        // User should only have SLP
        assertEq(sushiLpToken.balanceOf(user), _amount);
        assertEq(balancerPoolToken.balanceOf(user), 0);
        assertEq(auraDepositToken.balanceOf(user), 0);

        // Parameters to be calculated off-chain
        (
            uint256 amountTokenMin,
            uint256 amountWethMin,
            uint256 wethRequired,
            uint256 minAmountTokenOut,
            uint256 amountBptOut
        ) = offChainParams(_amount);

        hevm.startPrank(user);
        sushiLpToken.approve(address(migrator), _amount);
        migrator.migrate(false, amountTokenMin, amountWethMin, wethRequired, minAmountTokenOut, amountBptOut);
        hevm.stopPrank();

        // User should only have BPT (BPT amount > original SLP amount)
        assertEq(sushiLpToken.balanceOf(user), 0);
        assertGt(balancerPoolToken.balanceOf(user), _amount);
        assertEq(auraDepositToken.balanceOf(user), 0);

        // Migrator should have no funds
        assertEq(weth.balanceOf(address(migrator)), 0);
        assertEq(token.balanceOf(address(migrator)), 0);
        assertEq(balancerPoolToken.balanceOf(address(migrator)), 0);
        assertEq(auraDepositToken.balanceOf(address(migrator)), 0);
        assertEq(sushiLpToken.balanceOf(address(migrator)), 0);
        assertEq((address(migrator).balance), 0);
    }
}
