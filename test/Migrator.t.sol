// SPDX-License-Identifier: GPL-3
pragma solidity ^0.8.15;

import "./BaseTest.sol";

contract MigratorTest is BaseTest {
    // Only contract owner should be able to set unwrap and swap slippage
    function test_setSlippage(uint256 _amount) external {
        if (_amount > BPS) {
            hevm.expectRevert(abi.encodePacked("swap slippage too high"));
            migrator.setSwapSlippage(_amount);
        } else {
            migrator.setSwapSlippage(_amount);
        }

        // Should never be able to be set by non owner
        hevm.expectRevert(abi.encodePacked("Ownable: caller is not the owner"));
        hevm.prank(user);
        migrator.setSwapSlippage(_amount);
    }

    // Given an TOKEN amount, calculate the WETH amount for an 80/20 TOKEN/WETH ratio
    function test_calculateWethWeight(uint256 _amount) external {
        uint256 slpSupply = sushiLpToken.totalSupply();
        hevm.assume(_amount < slpSupply && _amount > 0);

        (, int256 tokenEthPrice, , , ) = tokenPrice.latestRoundData();
        uint256 amountInEth = (((_amount * uint256(tokenEthPrice)) / 1 ether) * 2000) / 8000;
        uint256 wethAmount = migratorHarness.exposed_calculateWethWeight(_amount);

        assertEq(wethAmount, amountInEth);
    }

    // Test unwrapping SLP
    function test_unwrapSlp(uint256 _amount) external {
        // Set range for amount based on SLP supply
        uint256 slpSupply = sushiLpToken.totalSupply();
        hevm.assume(_amount < slpSupply && _amount > 1 ether);

        // Seed with SLP
        deal(address(sushiLpToken), address(migratorHarness), _amount);

        // Should only have SLP
        assertEq(sushiLpToken.balanceOf(address(migratorHarness)), _amount);
        assertEq(token.balanceOf(address(migratorHarness)), 0);
        assertEq(weth.balanceOf(address(migratorHarness)), 0);

        // Calculate min amount out
        (uint256 amountTokenMin, uint256 amountWethMin) = calculateSlpAmounts(_amount);

        // Calculate expected amount without unwrap slippage
        (uint256 wethReserves, uint256 tokenReserves, ) = sushiLpToken.getReserves();
        uint256 amountToken = (_amount * tokenReserves) / slpSupply;
        uint256 amountWeth = (_amount * wethReserves) / slpSupply;

        migratorHarness.exposed_unwrapSlp(amountTokenMin, amountWethMin);

        // After unwrap, SLP balance should be 0
        assertEq(sushiLpToken.balanceOf(address(migratorHarness)), 0);

        // Get TOKEN and WETH balance
        uint256 tokenBalance = token.balanceOf(address(migratorHarness));
        uint256 wethBalance = weth.balanceOf(address(migratorHarness));

        // Should have >= min expected TOKEN and WETH
        assertGe(tokenBalance, amountTokenMin);
        assertGe(wethBalance, amountWethMin);

        // Balances should be within a delta of actual amount and unwrap slippage
        assertApproxEq(tokenBalance, amountToken, ((amountToken * (BPS - unwrapSlippage)) / BPS));
        assertApproxEq(wethBalance, amountWeth, ((amountWeth * (BPS - unwrapSlippage)) / BPS));
    }

    // Test swapping WETH for TOKEN to go from 50/50 to 80/20 TOKEN/WETH ratio
    function test_swapWethForTokenBalancer(uint256 _amount) external {
        // Set range to be less than 10% of SLP supply
        uint256 slpSupply = sushiLpToken.totalSupply();
        hevm.assume(_amount <= ((slpSupply * 1000) / BPS) && _amount > 1 ether);

        // Seed with SLP
        deal(address(sushiLpToken), address(migratorHarness), _amount);

        // Calculate min amount out
        (uint256 amountTokenMin, uint256 amountWethMin) = calculateSlpAmounts(_amount);

        hevm.prank(address(migratorHarness));
        migratorHarness.exposed_unwrapSlp(amountTokenMin, amountWethMin);

        (, int256 tokenEthPrice, , , ) = tokenPrice.latestRoundData();

        uint256 tokenBalanceBefore = token.balanceOf(address(migratorHarness));
        uint256 wethBalanceBefore = weth.balanceOf(address(migratorHarness));

        uint256 tokenInEthBefore = (tokenBalanceBefore * uint256(tokenEthPrice)) / 1 ether;
        uint256 totalValueBefore = tokenInEthBefore + wethBalanceBefore;

        // TOKEN/WETH ratio should be approx 50/50
        assertApproxEqRel(tokenInEthBefore, (totalValueBefore * 5000) / BPS, 0.1e18);
        assertApproxEqRel(wethBalanceBefore, (totalValueBefore * 5000) / BPS, 0.1e18);

        migratorHarness.exposed_swapWethForTokenBalancer();

        uint256 tokenBalanceAfter = token.balanceOf(address(migratorHarness));
        uint256 wethBalanceAfter = weth.balanceOf(address(migratorHarness));

        uint256 tokenInEthAfter = (tokenBalanceAfter * uint256(tokenEthPrice)) / 1 ether;
        uint256 totalValueAfter = tokenInEthAfter + wethBalanceAfter;

        // TOKEN/WETH ratio should be approx 80/20
        assertApproxEqRel(tokenInEthAfter, (totalValueAfter * 8000) / BPS, 0.4e18);
        assertApproxEqRel(wethBalanceAfter, (totalValueAfter * 2000) / BPS, 0.4e18);
    }

    // Test depositing into the Balancer pool and receiving BPT
    function test_depositIntoBalancerPool(uint256 _amount) external {
        // Set range to be less than 10% of SLP supply
        uint256 slpSupply = sushiLpToken.totalSupply();
        hevm.assume(_amount <= ((slpSupply * 1000) / BPS) && _amount > 1 ether);

        // Seed with SLP, unwrap, and swap for 80/20 TOKEN/WETH
        deal(address(sushiLpToken), address(migratorHarness), _amount);

        // Calculate min amount out
        (uint256 amountTokenMin, uint256 amountWethMin) = calculateSlpAmounts(_amount);

        hevm.prank(address(migratorHarness));
        migratorHarness.exposed_unwrapSlp(amountTokenMin, amountWethMin);
        migratorHarness.exposed_swapWethForTokenBalancer();

        // BPT balance should be 0
        uint256 bptBalanceBefore = balancerPoolToken.balanceOf(address(migratorHarness));
        assertEq(bptBalanceBefore, 0);

        hevm.prank(user);
        migratorHarness.exposed_depositIntoBalancerPool();

        uint256 bptBalanceAfter = balancerPoolToken.balanceOf(address(migratorHarness));
        uint256 tokenBalanceAfter = token.balanceOf(address(migratorHarness));
        uint256 wethBalanceAfter = weth.balanceOf(address(migratorHarness));

        assertGt(bptBalanceAfter, bptBalanceBefore);
        assertEq(tokenBalanceAfter, 0);
        assertEq(wethBalanceAfter, 0);
    }

    // Test depositing BPT into the Aura pool and receiving auraBPT
    function test_depositIntoRewardsPool(uint256 _amount) external {
        uint256 bptSupply = balancerPoolToken.totalSupply();
        hevm.assume(_amount <= bptSupply / 2 && _amount > 0);

        // Seed with BPT
        deal(address(balancerPoolToken), address(migratorHarness), _amount);

        // Should only have BPT
        assertEq(balancerPoolToken.balanceOf(address(migratorHarness)), _amount);
        assertEq(auraDepositToken.balanceOf(address(migratorHarness)), 0);

        hevm.prank(address(migratorHarness));
        migratorHarness.exposed_depositIntoRewardsPool();

        // Should only have auraBPT
        assertEq(balancerPoolToken.balanceOf(address(migratorHarness)), 0);
        assertEq(auraDepositToken.balanceOf(address(migratorHarness)), _amount);
    }

    // Test entire flow of migrating from SLP to auraBPT
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

        // Calculate min amount out
        (uint256 amountTokenMin, uint256 amountWethMin) = calculateSlpAmounts(_amount);

        hevm.startPrank(user);
        sushiLpToken.approve(address(migrator), _amount);
        migrator.migrate(true, amountTokenMin, amountWethMin);
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

    // Test entire flow of migrating from SLP to BPT
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

        // Calculate min amount out
        (uint256 amountTokenMin, uint256 amountWethMin) = calculateSlpAmounts(_amount);

        hevm.startPrank(user);
        sushiLpToken.approve(address(migrator), _amount);
        migrator.migrate(false, amountTokenMin, amountWethMin);
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
