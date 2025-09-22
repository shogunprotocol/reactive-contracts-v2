// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/Vault.sol";
import "../src/mocks/MockUSDC.sol";

contract DecimalsWithYieldTest is Test {
    Vault public vault;
    MockUSDC public underlyingToken;

    address public owner;
    address public manager;
    address public agent;
    address public treasury;
    address public alice;
    address public bob;

    uint256 constant INITIAL_BALANCE = 10_000 * 1e6; // 10,000 USDC

    function setUp() public {
        owner = address(this);
        manager = makeAddr("manager");
        agent = makeAddr("agent");
        treasury = makeAddr("treasury");
        alice = makeAddr("alice");
        bob = makeAddr("bob");

        // Deploy USDC with 6 decimals
        underlyingToken = new MockUSDC();

        // Deploy vault with 5% yield rate
        vault = new Vault(
            IERC20(address(underlyingToken)),
            "USDC Vault",
            "vUSDC",
            manager,
            agent,
            0, // 0% withdrawal fee for cleaner tests
            500, // 5% annual yield rate
            treasury
        );

        // Setup users with tokens
        underlyingToken.transfer(alice, INITIAL_BALANCE);
        underlyingToken.transfer(bob, INITIAL_BALANCE);

        vm.prank(alice);
        underlyingToken.approve(address(vault), type(uint256).max);
        vm.prank(bob);
        underlyingToken.approve(address(vault), type(uint256).max);
    }

    // ============ YIELD IMPACT ON EXCHANGE RATES ============

    function test_MaintainProperExchangeRatesWhenYieldAccrues() public {
        console.log("Testing exchange rates with yield...");

        // Alice deposits first
        uint256 aliceDeposit = 1_000 * 1e6; // 1,000 USDC
        vm.prank(alice);
        vault.deposit(aliceDeposit, alice);

        uint256 aliceShares = vault.balanceOf(alice);
        console.log("Alice deposited: 1000 USDC");
        console.log("Alice received:", aliceShares / 1e6, "shares");

        // Fast forward 30 days to accrue yield
        skip(30 days);

        uint256 totalAssetsBeforeBob = vault.totalAssets();
        uint256 totalSupplyBeforeBob = vault.totalSupply();
        uint256 exchangeRateBeforeBob = (totalAssetsBeforeBob * 1e6) /
            totalSupplyBeforeBob;

        console.log("After 30 days:");
        console.log("  Total assets:", totalAssetsBeforeBob / 1e6, "USDC");
        console.log("  Total supply:", totalSupplyBeforeBob / 1e6, "shares");
        console.log(
            "  Exchange rate: 1 share =",
            exchangeRateBeforeBob / 1e6,
            "USDC"
        );

        // Bob deposits same amount after yield has accrued
        uint256 bobDeposit = 1_000 * 1e6; // 1,000 USDC
        vm.prank(bob);
        vault.deposit(bobDeposit, bob);

        uint256 bobShares = vault.balanceOf(bob);
        console.log("Bob deposited: 1000 USDC");
        console.log("Bob received:", bobShares / 1e6, "shares");

        // Bob should get fewer shares because share price increased due to yield
        assertLt(
            bobShares,
            aliceShares,
            "Bob should get fewer shares due to yield appreciation"
        );

        // Verify Alice can redeem more than she deposited (due to yield)
        uint256 aliceRedeemable = vault.previewRedeem(aliceShares);
        console.log("Alice can redeem:", aliceRedeemable / 1e6, "USDC");

        assertGt(
            aliceRedeemable,
            aliceDeposit,
            "Alice should be able to redeem more than she deposited"
        );

        // Verify Bob can redeem approximately what he deposited
        uint256 bobRedeemable = vault.previewRedeem(bobShares);
        console.log("Bob can redeem:", bobRedeemable / 1e6, "USDC");

        assertApproxEqAbs(
            bobRedeemable,
            bobDeposit,
            1 * 1e6,
            "Bob should redeem close to what he deposited"
        );
    }

    function test_HandlePrecisionCorrectlyWithSmallYieldAmounts() public {
        console.log("Testing precision with small yield amounts...");

        // Deposit small amount
        uint256 smallDeposit = 1 * 1e6; // 1 USDC
        vm.prank(alice);
        vault.deposit(smallDeposit, alice);

        console.log("Deposited: 1 USDC");

        // Fast forward 1 day (should generate very small yield)
        skip(1 days);

        uint256 totalAssets = vault.totalAssets();
        uint256 pendingYield = vault.calculatePendingYield();

        console.log("Total assets after 1 day:", totalAssets, "wei");
        console.log("Pending yield:", pendingYield, "wei");

        // Even tiny yield should be handled correctly
        if (pendingYield > 0) {
            assertLt(
                pendingYield,
                1000,
                "Yield should be very small for 1 day"
            );
        }

        // Total assets should be at least the deposit
        assertGe(
            totalAssets,
            smallDeposit,
            "Total assets should not be less than deposit"
        );
    }

    function test_LargeAmountsWithYieldMaintainPrecision() public {
        console.log("Testing large amounts with yield...");

        // Deposit large amount
        uint256 largeDeposit = 1_000_000 * 1e6; // 1M USDC
        underlyingToken.mint(alice, largeDeposit);
        vm.prank(alice);
        underlyingToken.approve(address(vault), largeDeposit);

        vm.prank(alice);
        vault.deposit(largeDeposit, alice);

        console.log("Deposited: 1M USDC");

        // Fast forward 1 year
        skip(365 days);

        uint256 totalAssets = vault.totalAssets();
        uint256 pendingYield = vault.calculatePendingYield();

        console.log("Total assets after 1 year:", totalAssets / 1e6, "USDC");
        console.log("Pending yield:", pendingYield / 1e6, "USDC");

        // Should have significant yield
        assertGt(
            pendingYield,
            10_000 * 1e6,
            "Should have substantial yield after 1 year"
        );
        assertLt(
            pendingYield,
            100_000 * 1e6,
            "Yield should be reasonable (< 10%)"
        );
    }

    // ============ COMPOUND YIELD EFFECTS ============

    function test_CompoundYieldAffectsExchangeRates() public {
        console.log("Testing compound yield effects...");

        // Alice deposits 1000 USDC
        uint256 deposit1 = 1_000 * 1e6;
        vm.prank(alice);
        vault.deposit(deposit1, alice);

        // Fast forward 6 months and update yield
        skip(180 days);
        vault.updateYield();

        uint256 assetsAfter6Months = vault.totalAssets();
        console.log("Assets after 6 months:", assetsAfter6Months / 1e6, "USDC");

        // Bob deposits same amount after 6 months
        vm.prank(bob);
        vault.deposit(deposit1, bob);

        uint256 aliceShares = vault.balanceOf(alice);
        uint256 bobShares = vault.balanceOf(bob);

        console.log("Alice shares:", aliceShares / 1e6);
        console.log("Bob shares:", bobShares / 1e6);

        // Alice should have more shares since she deposited before yield accrued
        assertGt(aliceShares, bobShares, "Alice should have more shares");

        // Fast forward another 6 months
        skip(180 days);

        uint256 aliceRedeemable = vault.previewRedeem(aliceShares);
        uint256 bobRedeemable = vault.previewRedeem(bobShares);

        console.log("Alice redeemable:", aliceRedeemable / 1e6, "USDC");
        console.log("Bob redeemable:", bobRedeemable / 1e6, "USDC");

        // Both should have more than they deposited, but Alice should have more
        assertGt(aliceRedeemable, deposit1, "Alice should profit from yield");
        assertGt(bobRedeemable, deposit1, "Bob should profit from yield");
        assertGt(
            aliceRedeemable,
            bobRedeemable,
            "Alice should have more due to longer exposure"
        );
    }

    function test_MultipleUsersWithDifferentTimingAndAmounts() public {
        console.log("Testing multiple users with different timing...");

        // Alice deposits 500 USDC at start
        vm.prank(alice);
        vault.deposit(500 * 1e6, alice);

        // Wait 3 months
        skip(90 days);

        // Bob deposits 1000 USDC
        vm.prank(bob);
        vault.deposit(1_000 * 1e6, bob);

        // Wait another 3 months
        skip(90 days);

        // Alice deposits another 500 USDC
        vm.prank(alice);
        vault.deposit(500 * 1e6, alice);

        // Wait final 6 months
        skip(180 days);

        uint256 aliceShares = vault.balanceOf(alice);
        uint256 bobShares = vault.balanceOf(bob);
        uint256 aliceRedeemable = vault.previewRedeem(aliceShares);
        uint256 bobRedeemable = vault.previewRedeem(bobShares);

        console.log("Final Alice shares:", aliceShares / 1e6);
        console.log("Final Bob shares:", bobShares / 1e6);
        console.log("Alice redeemable:", aliceRedeemable / 1e6, "USDC");
        console.log("Bob redeemable:", bobRedeemable / 1e6, "USDC");

        // Both should have made money
        assertGt(aliceRedeemable, 1_000 * 1e6, "Alice should profit");
        assertGt(bobRedeemable, 1_000 * 1e6, "Bob should profit");

        // Total redeemable should be more than total deposited
        uint256 totalDeposited = 2_000 * 1e6; // Alice: 1000, Bob: 1000
        uint256 totalRedeemable = aliceRedeemable + bobRedeemable;
        assertGt(totalRedeemable, totalDeposited, "Total should have grown");
    }

    // ============ WITHDRAWAL WITH YIELD ============

    function test_WithdrawalsMaintainCorrectRatios() public {
        // Setup: Alice and Bob deposit, yield accrues
        vm.prank(alice);
        vault.deposit(1_000 * 1e6, alice);

        skip(30 days);

        vm.prank(bob);
        vault.deposit(1_000 * 1e6, bob);

        skip(60 days);

        uint256 aliceSharesBefore = vault.balanceOf(alice);
        uint256 bobSharesBefore = vault.balanceOf(bob);

        // Alice withdraws half her shares
        vm.prank(alice);
        vault.redeem(aliceSharesBefore / 2, alice, alice);

        uint256 aliceSharesAfter = vault.balanceOf(alice);
        uint256 bobSharesAfter = vault.balanceOf(bob);

        // Alice should have exactly half her shares left
        assertEq(
            aliceSharesAfter,
            aliceSharesBefore / 2,
            "Alice should have half shares left"
        );

        // Bob's shares should be unchanged
        assertEq(
            bobSharesAfter,
            bobSharesBefore,
            "Bob's shares should be unchanged"
        );

        // Exchange rate should still be fair for both
        uint256 aliceRedeemable = vault.previewRedeem(aliceSharesAfter);
        uint256 bobRedeemable = vault.previewRedeem(bobSharesAfter);

        // Both should still be profitable proportionally
        assertGt(
            aliceRedeemable,
            500 * 1e6,
            "Alice's remaining should be profitable"
        );
        assertGt(bobRedeemable, 1_000 * 1e6, "Bob should be profitable");
    }

    function test_SmallWithdrawalsPreservePrecision() public {
        // Large deposit
        vm.prank(alice);
        vault.deposit(10_000 * 1e6, alice);

        skip(30 days);

        // Small withdrawal
        uint256 smallWithdraw = 1 * 1e6; // 1 USDC
        uint256 sharesBefore = vault.balanceOf(alice);

        vm.prank(alice);
        uint256 assetsReceived = vault.withdraw(smallWithdraw, alice, alice);

        uint256 sharesAfter = vault.balanceOf(alice);
        uint256 sharesBurned = sharesBefore - sharesAfter;

        // Should receive approximately what was requested (allowing for withdrawal fees)
        assertApproxEqAbs(
            assetsReceived,
            smallWithdraw,
            5000,
            "Should receive close to requested amount allowing for fees"
        );

        // Shares burned should be proportional
        assertGt(sharesBurned, 0, "Some shares should be burned");
        assertLt(
            sharesBurned,
            sharesBefore / 1000,
            "Shares burned should be small fraction"
        );
    }

    // ============ EDGE CASES WITH YIELD ============

    function test_ZeroYieldEdgeCases() public {
        // Deploy vault with 0% yield
        Vault zeroYieldVault = new Vault(
            IERC20(address(underlyingToken)),
            "Zero Yield Vault",
            "zVault",
            manager,
            agent,
            0,
            0, // 0% yield rate
            treasury
        );

        vm.prank(alice);
        underlyingToken.approve(address(zeroYieldVault), INITIAL_BALANCE);

        vm.prank(alice);
        zeroYieldVault.deposit(1_000 * 1e6, alice);

        skip(365 days);

        uint256 totalAssets = zeroYieldVault.totalAssets();
        uint256 pendingYield = zeroYieldVault.calculatePendingYield();

        assertEq(
            totalAssets,
            1_000 * 1e6,
            "Total assets should not change with 0% yield"
        );
        assertEq(pendingYield, 0, "Pending yield should be 0");
    }

    function test_VeryHighYieldRates() public {
        // Note: In practice, the vault has maximum yield rate limits
        // This tests behavior near those limits
        vm.prank(alice);
        vault.deposit(1_000 * 1e6, alice);

        // Test with maximum allowed time
        skip(730 days); // 2 years

        uint256 pendingYield = vault.calculatePendingYield();
        uint256 totalAssets = vault.totalAssets();

        // Should not overflow or underflow
        assertGt(totalAssets, 1_000 * 1e6, "Should have grown");
        assertLt(
            totalAssets,
            2_000 * 1e6,
            "Should not have doubled (conservative implementation)"
        );
    }

    // ============ FUZZ TESTS ============

    function testFuzz_YieldConsistencyAcrossTimeAndAmounts(
        uint256 depositAmount,
        uint256 timeElapsed
    ) public {
        depositAmount = bound(depositAmount, 1_000 * 1e6, INITIAL_BALANCE);
        timeElapsed = bound(timeElapsed, 1 days, 365 days);

        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        skip(timeElapsed);

        uint256 totalAssets = vault.totalAssets();
        uint256 pendingYield = vault.calculatePendingYield();

        // Yield should be positive but reasonable
        assertGe(
            totalAssets,
            depositAmount,
            "Total assets should not decrease"
        );

        if (timeElapsed > 7 days) {
            assertGt(
                pendingYield,
                0,
                "Should have some yield after significant time"
            );
        }

        // Sanity check: yield shouldn't be more than 20% annually
        uint256 maxExpectedYield = (depositAmount * 20 * timeElapsed) /
            (100 * 365 days);
        assertLe(
            pendingYield,
            maxExpectedYield * 2,
            "Yield should be reasonable"
        ); // 2x buffer for compound effects
    }

    function testFuzz_ExchangeRateFairness(
        uint256 deposit1,
        uint256 deposit2,
        uint256 timeGap
    ) public {
        deposit1 = bound(deposit1, 100 * 1e6, INITIAL_BALANCE / 3);
        deposit2 = bound(deposit2, 100 * 1e6, INITIAL_BALANCE / 3);
        timeGap = bound(timeGap, 1 days, 180 days);

        // First deposit
        vm.prank(alice);
        vault.deposit(deposit1, alice);

        skip(timeGap);

        // Second deposit
        vm.prank(bob);
        vault.deposit(deposit2, bob);

        uint256 aliceShares = vault.balanceOf(alice);
        uint256 bobShares = vault.balanceOf(bob);

        // If same deposit amount and significant time passed, Alice should have more shares
        if (deposit1 == deposit2 && timeGap > 7 days) {
            assertGt(
                aliceShares,
                bobShares,
                "Earlier depositor should benefit from yield"
            );
        }

        // Both should be able to redeem their proportional share
        uint256 aliceRedeemable = vault.previewRedeem(aliceShares);
        uint256 bobRedeemable = vault.previewRedeem(bobShares);

        assertGe(
            aliceRedeemable,
            deposit1,
            "Alice should get at least what she deposited"
        );
        assertApproxEqAbs(
            bobRedeemable,
            deposit2,
            deposit2 / 100,
            "Bob should get close to what he deposited"
        );
    }
}
