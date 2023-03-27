// SPDX-License-Identifier: GPL-3
pragma solidity ^0.8.15;

import "./BaseTest.sol";

contract MigratorTest is BaseTest {
    // Test unwrapping SLP within the Migrator contract
    function test_unwrapSlp(uint256 _amount) external {
        // Set range for fuzzed amount based on SLP supply
        uint256 slpSupply = slp.totalSupply();
        hevm.assume(_amount < slpSupply && _amount > 1 ether);

        deal(address(slp), address(migrator), _amount);

        (uint256 amountTokenMin, uint256 amountEthMin) = migrator.calculateSlpAmounts(_amount);

        // Migrator should only have SLP
        assertEq(slp.balanceOf(address(migrator)), _amount);
        assertEq(alcx.balanceOf(address(migrator)), 0);
        assertEq((address(migrator).balance), 0);

        hevm.prank(address(migrator));
        migrator.unwrapSlp();

        // After unwrap, SLP should be 0
        assertEq(slp.balanceOf(address(migrator)), 0);

        // Migrator should have >= expected ALCX and ETH from SLP
        assertGe(alcx.balanceOf(address(migrator)), amountTokenMin);
        assertGe((address(migrator).balance), amountEthMin);
    }
}
