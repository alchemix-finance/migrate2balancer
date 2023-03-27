// SPDX-License-Identifier: GPL-3
pragma solidity ^0.8.15;

import "./BaseTest.sol";

contract MigratorTest is BaseTest {
    // Only contract owner should be able to set slippage
    function test_setUnrwapSlippage(uint256 _amount) external {
        if (_amount > migrator.BPS()) {
            hevm.expectRevert(abi.encodePacked("slippage too high"));
            migrator.setUnrwapSlippage(_amount);
        } else {
            migrator.setUnrwapSlippage(_amount);
        }

        // Should never be able to be set by non owner
        hevm.expectRevert(abi.encodePacked("Ownable: caller is not the owner"));
        hevm.prank(user);
        migrator.setUnrwapSlippage(_amount);
    }

    // Test unwrapping SLP within the Migrator contract
    function test_unwrapSlp(uint256 _amount) external {
        // Set range for fuzzed amount based on SLP supply
        uint256 slpSupply = slp.totalSupply();
        hevm.assume(_amount < slpSupply && _amount > 1 ether);

        // Seed Migrator with SLP
        deal(address(slp), address(migrator), _amount);

        // Migrator should only have SLP
        assertEq(slp.balanceOf(address(migrator)), _amount);
        assertEq(alcx.balanceOf(address(migrator)), 0);
        assertEq((address(migrator).balance), 0);

        // Calculate min amount out
        (uint256 amountTokenMin, uint256 amountEthMin) = migrator.calculateSlpAmounts(_amount);

        // Calculate expected amount without slippage
        (uint256 wethReserves, uint256 alcxReserves, ) = slp.getReserves();
        uint256 amountToken = (_amount * alcxReserves) / slpSupply;
        uint256 amountEth = (_amount * wethReserves) / slpSupply;

        hevm.prank(address(migrator));
        migrator.unwrapSlp();

        // After unwrap, Migrator SLP balance should be 0
        assertEq(slp.balanceOf(address(migrator)), 0);

        // Get ALCX and ETH balance of Migrator
        uint256 tokenBalance = alcx.balanceOf(address(migrator));
        uint256 ethBalance = (address(migrator).balance);

        // Migrator should have >= min expected ALCX and ETH
        assertGe(tokenBalance, amountTokenMin);
        assertGe(ethBalance, amountEthMin);

        // Migrator balances should be within a delta of actual amount and slippage
        assertApproxEq(tokenBalance, amountToken, ((amountToken * (BPS - migrator.slippage())) / BPS));
        assertApproxEq(ethBalance, amountEth, ((amountEth * (BPS - migrator.slippage())) / BPS));
    }

    function test_swapEthForAlcx() public {
        uint256 _amount = 5 ether;
        // Seed Migrator with SLP
        deal(address(slp), address(migrator), _amount);
        hevm.prank(address(migrator));
        migrator.unwrapSlp();

        migrator.swapEthForAlcx();
    }
}
