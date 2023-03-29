// SPDX-License-Identifier: GPL-3
pragma solidity ^0.8.15;

import "./BaseTest.sol";

contract MigratorTest is BaseTest {
    // Migrator cannot be initialized twice
    function test_initialize() external {
        hevm.expectRevert(abi.encodePacked("Initializable: contract is already initialized"));
        migrator.initialize(params);
    }

    // Only contract owner should be able to set unwrap and swap slippage
    function test_setSlippage(uint256 _amount) external {
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

    // Given an TOKEN amount, calculate the WETH amount for an 80/20 TOKEN/WETH ratio
    function test_calculateWethWeight(uint256 _amount) external {
        uint256 slpSupply = slp.totalSupply();
        hevm.assume(_amount < slpSupply && _amount > 0);

        (, int256 tokenEthPrice, , , ) = tokenPrice.latestRoundData();
        uint256 amountInEth = (((_amount * uint256(tokenEthPrice)) / 1 ether) * 2000) / 8000;
        uint256 wethAmount = migrator.calculateWethWeight(_amount);

        assertEq(wethAmount, amountInEth);
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
        assertEq(token.balanceOf(address(migrator)), 0);
        assertEq(weth.balanceOf(address(migrator)), 0);

        // Calculate min amount out
        (uint256 amountTokenMin, uint256 amountWethMin) = migrator.calculateSlpAmounts(_amount);

        // Calculate expected amount without unwrap slippage
        (uint256 wethReserves, uint256 tokenReserves, ) = slp.getReserves();
        uint256 amountToken = (_amount * tokenReserves) / slpSupply;
        uint256 amountWeth = (_amount * wethReserves) / slpSupply;

        // hevm.prank(address(migrator));
        migrator.unwrapSlp();

        // After unwrap, Migrator SLP balance should be 0
        assertEq(slp.balanceOf(address(migrator)), 0);

        // Get TOKEN and WETH balance of Migrator
        uint256 tokenBalance = token.balanceOf(address(migrator));
        uint256 wethBalance = weth.balanceOf(address(migrator));

        // Migrator should have >= min expected TOKEN and WETH
        assertGe(tokenBalance, amountTokenMin);
        assertGe(wethBalance, amountWethMin);

        // Migrator balances should be within a delta of actual amount and unwrap slippage
        assertApproxEq(tokenBalance, amountToken, ((amountToken * (BPS - migrator.unrwapSlippage())) / BPS));
        assertApproxEq(wethBalance, amountWeth, ((amountWeth * (BPS - migrator.unrwapSlippage())) / BPS));
    }

    // Test swapping WETH for TOKEN to go from 50/50 to 80/20 TOKEN/WETH ratio
    function test_swapWethForTokenBalancer(uint256 _amount) external {
        // Set range to be less than 10% of SLP supply
        uint256 slpSupply = slp.totalSupply();
        hevm.assume(_amount <= ((slpSupply * 1000) / migrator.BPS()) && _amount > 1 ether);

        // Seed Migrator with SLP
        deal(address(slp), address(migrator), _amount);
        hevm.prank(address(migrator));
        migrator.unwrapSlp();

        (, int256 tokenEthPrice, , , ) = tokenPrice.latestRoundData();

        uint256 tokenBalanceBefore = token.balanceOf(address(migrator));
        uint256 wethBalanceBefore = weth.balanceOf(address(migrator));

        uint256 tokenInEthBefore = (tokenBalanceBefore * uint256(tokenEthPrice)) / 1 ether;
        uint256 totalValueBefore = tokenInEthBefore + wethBalanceBefore;

        // TOKEN/WETH ratio should be approx 50/50
        assertApproxEqRel(tokenInEthBefore, (totalValueBefore * 5000) / BPS, 0.1e18);
        assertApproxEqRel(wethBalanceBefore, (totalValueBefore * 5000) / BPS, 0.1e18);

        migrator.swapWethForTokenBalancer();

        uint256 tokenBalanceAfter = token.balanceOf(address(migrator));
        uint256 wethBalanceAfter = weth.balanceOf(address(migrator));

        uint256 tokenInEthAfter = (tokenBalanceAfter * uint256(tokenEthPrice)) / 1 ether;
        uint256 totalValueAfter = tokenInEthAfter + wethBalanceAfter;

        // TOKEN/WETH ratio should be approx 80/20
        assertApproxEqRel(tokenInEthAfter, (totalValueAfter * 8000) / BPS, 0.4e18);
        assertApproxEqRel(wethBalanceAfter, (totalValueAfter * 2000) / BPS, 0.4e18);
    }

    // Test depositing into the Balancer pool and receiving BPT
    function test_depositIntoBalancerPool(uint256 _amount) external {
        // Set range to be less than 10% of SLP supply
        uint256 slpSupply = slp.totalSupply();
        hevm.assume(_amount <= ((slpSupply * 1000) / migrator.BPS()) && _amount > 1 ether);

        // Seed Migrator with SLP, unwrap, and swap for 80/20 TOKEN/WETH
        deal(address(slp), address(migrator), _amount);
        hevm.prank(address(migrator));
        migrator.unwrapSlp();
        migrator.swapWethForTokenBalancer();

        // BPT balance should be 0
        uint256 bptBalanceBefore = bpt.balanceOf(address(migrator));
        assertEq(bptBalanceBefore, 0);

        hevm.prank(user);
        migrator.depositIntoBalancerPool();

        uint256 bptBalanceAfter = bpt.balanceOf(address(migrator));
        uint256 tokenBalanceAfter = token.balanceOf(address(migrator));
        uint256 wethBalanceAfter = weth.balanceOf(address(migrator));

        assertGt(bptBalanceAfter, bptBalanceBefore);
        assertEq(tokenBalanceAfter, 0);
        assertEq(wethBalanceAfter, 0);
    }

    // Test depositing BPT into the Aura pool and receiving auraBPT
    function test_depositIntoRewardsPool(uint256 _amount) external {
        uint256 bptSupply = bpt.totalSupply();
        hevm.assume(_amount <= bptSupply / 2 && _amount > 0);

        // Seed migrator with BPT
        deal(address(bpt), address(migrator), _amount);

        // Migrator should only have BPT
        assertEq(bpt.balanceOf(address(migrator)), _amount);
        assertEq(auraBpt.balanceOf(address(migrator)), 0);

        hevm.prank(address(migrator));
        migrator.depositIntoRewardsPool();

        // Migrator should only have auraBPT
        assertEq(bpt.balanceOf(address(migrator)), 0);
        assertEq(auraBpt.balanceOf(address(migrator)), _amount);
    }

    // Test external users depositing BPT into the Aura pool and receiving auraBPT
    function test_userDepositIntoRewardsPool(uint256 _amount) external {
        uint256 bptSupply = bpt.totalSupply();
        hevm.assume(_amount <= bptSupply / 2 && _amount > 0);

        // Seed user with BPT
        deal(address(bpt), user, _amount);

        // User should only have BPT
        assertEq(bpt.balanceOf(user), _amount);
        assertEq(auraBpt.balanceOf(user), 0);

        hevm.startPrank(user);

        bpt.approve(address(migrator), _amount);
        migrator.userDepositIntoRewardsPool();

        hevm.stopPrank();

        // User should only have auraBPT
        assertEq(bpt.balanceOf(user), 0);
        assertEq(auraBpt.balanceOf(user), _amount);
    }

    // Test entire flow of migrating from SLP to auraBPT
    function test_migrateToAuraBpt(uint256 _amount) external {
        // Set range to be less than 10% of SLP supply
        uint256 slpSupply = slp.totalSupply();
        hevm.assume(_amount <= ((slpSupply * 1000) / migrator.BPS()) && _amount > 1 ether);

        // Seed user with SLP
        deal(address(slp), user, _amount);

        // User should only have SLP
        assertEq(slp.balanceOf(user), _amount);
        assertEq(bpt.balanceOf(user), 0);
        assertEq(auraBpt.balanceOf(user), 0);

        hevm.startPrank(user);
        slp.approve(address(migrator), _amount);
        migrator.migrate(true);
        hevm.stopPrank();

        // User should only have auraBPT (auraBPT amount > original SLP amount)
        assertEq(slp.balanceOf(user), 0);
        assertEq(bpt.balanceOf(user), 0);
        assertGt(auraBpt.balanceOf(user), _amount);

        // Migrator should have no funds
        assertEq(weth.balanceOf(address(migrator)), 0);
        assertEq(token.balanceOf(address(migrator)), 0);
        assertEq(bpt.balanceOf(address(migrator)), 0);
        assertEq(auraBpt.balanceOf(address(migrator)), 0);
        assertEq(slp.balanceOf(address(migrator)), 0);
        assertEq((address(migrator).balance), 0);
    }

    // Test entire flow of migrating from SLP to BPT
    function test_migrateToBpt(uint256 _amount) external {
        // Set range to be less than 10% of SLP supply
        uint256 slpSupply = slp.totalSupply();
        hevm.assume(_amount <= ((slpSupply * 1000) / migrator.BPS()) && _amount > 1 ether);

        // Seed user with SLP
        deal(address(slp), user, _amount);

        // User should only have SLP
        assertEq(slp.balanceOf(user), _amount);
        assertEq(bpt.balanceOf(user), 0);
        assertEq(auraBpt.balanceOf(user), 0);

        hevm.startPrank(user);
        slp.approve(address(migrator), _amount);
        migrator.migrate(false);
        hevm.stopPrank();

        // User should only have BPT (BPT amount > original SLP amount)
        assertEq(slp.balanceOf(user), 0);
        assertGt(bpt.balanceOf(user), _amount);
        assertEq(auraBpt.balanceOf(user), 0);

        // Migrator should have no funds
        assertEq(weth.balanceOf(address(migrator)), 0);
        assertEq(token.balanceOf(address(migrator)), 0);
        assertEq(bpt.balanceOf(address(migrator)), 0);
        assertEq(auraBpt.balanceOf(address(migrator)), 0);
        assertEq(slp.balanceOf(address(migrator)), 0);
        assertEq((address(migrator).balance), 0);
    }
}
