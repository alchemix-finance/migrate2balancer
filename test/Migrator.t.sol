// SPDX-License-Identifier: GPL-3
pragma solidity ^0.8.15;

import "./BaseTest.sol";

contract MigratorTest is BaseTest {
    // Only contract owner should be able to set unwrap and swap slippage
    function test_setUnrwapSlippage(uint256 _amount) external {
        if (_amount > migrator.BPS()) {
            hevm.expectRevert(abi.encodePacked("unwrap slippage too high"));
            migrator.setUnrwapSlippage(_amount);

            hevm.expectRevert(abi.encodePacked("swap slippage too high"));
            migrator.setSwapSlippage(_amount);
        } else {
            migrator.setUnrwapSlippage(_amount);
            migrator.setSwapSlippage(_amount);
        }

        // Should never be able to be set by non owner
        hevm.expectRevert(abi.encodePacked("Ownable: caller is not the owner"));
        hevm.prank(user);
        migrator.setUnrwapSlippage(_amount);

        // Should never be able to be set by non owner
        hevm.expectRevert(abi.encodePacked("Ownable: caller is not the owner"));
        hevm.prank(user);
        migrator.setSwapSlippage(_amount);
    }

    // Test unwrapping SLP within the Migrator contract
    function test_unwrapSlp(uint256 _amount) external {
        // Set range for amount based on SLP supply
        uint256 slpSupply = slp.totalSupply();
        hevm.assume(_amount < slpSupply && _amount > 1 ether);

        // Seed Migrator with SLP
        deal(address(slp), address(migrator), _amount);

        // Migrator should only have SLP
        assertEq(slp.balanceOf(address(migrator)), _amount);
        assertEq(alcx.balanceOf(address(migrator)), 0);
        assertEq(weth.balanceOf(address(migrator)), 0);

        // Calculate min amount out
        (uint256 amountTokenMin, uint256 amountWethMin) = migrator.calculateSlpAmounts(_amount);

        // Calculate expected amount without unwrap slippage
        (uint256 wethReserves, uint256 alcxReserves, ) = slp.getReserves();
        uint256 amountToken = (_amount * alcxReserves) / slpSupply;
        uint256 amountWeth = (_amount * wethReserves) / slpSupply;

        hevm.prank(address(migrator));
        migrator.unwrapSlp();

        // After unwrap, Migrator SLP balance should be 0
        assertEq(slp.balanceOf(address(migrator)), 0);

        // Get ALCX and WETH balance of Migrator
        uint256 tokenBalance = alcx.balanceOf(address(migrator));
        uint256 wethBalance = weth.balanceOf(address(migrator));

        // Migrator should have >= min expected ALCX and WETH
        assertGe(tokenBalance, amountTokenMin);
        assertGe(wethBalance, amountWethMin);

        // Migrator balances should be within a delta of actual amount and unwrap slippage
        assertApproxEq(tokenBalance, amountToken, ((amountToken * (BPS - migrator.unrwapSlippage())) / BPS));
        assertApproxEq(wethBalance, amountWeth, ((amountWeth * (BPS - migrator.unrwapSlippage())) / BPS));
    }

    // Test swapping WETH for ALCX to go from 50/50 to 80/20 ALCX/WETH ratio
    function test_swapWethForAlcxBalancer(uint256 _amount) public {
        // Set range to be less than 10% of SLP supply
        uint256 slpSupply = slp.totalSupply();
        hevm.assume(_amount <= ((slpSupply * 1000) / migrator.BPS()) && _amount > 1 ether);

        // Seed Migrator with SLP
        deal(address(slp), address(migrator), _amount);
        hevm.prank(address(migrator));
        migrator.unwrapSlp();

        (, int256 alcxEthPrice, , , ) = priceFeed.latestRoundData();

        uint256 alcxBalanceBefore = alcx.balanceOf(address(migrator));
        uint256 wethBalanceBefore = weth.balanceOf(address(migrator));

        uint256 alcxInEthBefore = (alcxBalanceBefore * uint256(alcxEthPrice)) / 1 ether;
        uint256 totalValueBefore = alcxInEthBefore + wethBalanceBefore;

        // ALCX/WETH ratio should be approx 50/50
        assertApproxEqRel(alcxInEthBefore, (totalValueBefore * 5000) / BPS, 0.1e18);
        assertApproxEqRel(wethBalanceBefore, (totalValueBefore * 5000) / BPS, 0.1e18);

        migrator.swapWethForAlcxBalancer();

        uint256 alcxBalanceAfter = alcx.balanceOf(address(migrator));
        uint256 wethBalanceAfter = weth.balanceOf(address(migrator));

        uint256 alcxInEthAfter = (alcxBalanceAfter * uint256(alcxEthPrice)) / 1 ether;
        uint256 totalValueAfter = alcxInEthAfter + wethBalanceAfter;

        // ALCX/WETH ratio should be approx 80/20
        assertApproxEqRel(alcxInEthAfter, (totalValueAfter * 8000) / BPS, 0.4e18);
        assertApproxEqRel(wethBalanceAfter, (totalValueAfter * 2000) / BPS, 0.4e18);
    }

    // Given an ALCX amount, calculate the WETH amount for an 80/20 ALCX/WETH ratio
    function test_calculateWethWeight(uint256 _amount) public {
        uint256 slpSupply = slp.totalSupply();
        hevm.assume(_amount < slpSupply && _amount > 0);

        (, int256 alcxEthPrice, , , ) = priceFeed.latestRoundData();
        uint256 amountInEth = (((_amount * uint256(alcxEthPrice)) / 1 ether) * 2000) / 8000;
        uint256 wethAmount = migrator.calculateWethWeight(_amount);

        assertEq(wethAmount, amountInEth);
    }

    // Test depositing into the Balancer pool and receiving BPT
    function test_depositIntoBalancerPool(uint256 _amount) public {
        // Set range to be less than 10% of SLP supply
        uint256 slpSupply = slp.totalSupply();
        hevm.assume(_amount <= ((slpSupply * 1000) / migrator.BPS()) && _amount > 1 ether);

        // Seed Migrator with SLP, unwrap, and swap for 80/20 ALCX/WETH
        deal(address(slp), address(migrator), _amount);
        hevm.prank(address(migrator));
        migrator.unwrapSlp();
        migrator.swapWethForAlcxBalancer();

        // BPT balance should be 0
        uint256 bptBalanceBefore = bpt.balanceOf(address(migrator));
        assertEq(bptBalanceBefore, 0);

        hevm.prank(user);
        migrator.depositIntoBalancerPool();

        uint256 bptBalanceAfter = bpt.balanceOf(address(migrator));
        uint256 alcxBalanceAfter = alcx.balanceOf(address(migrator));
        uint256 wethBalanceAfter = weth.balanceOf(address(migrator));

        assertGt(bptBalanceAfter, bptBalanceBefore);
        assertEq(alcxBalanceAfter, 0);
        assertEq(wethBalanceAfter, 0);
    }
}
