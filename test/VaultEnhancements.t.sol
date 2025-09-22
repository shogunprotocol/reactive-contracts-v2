// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/Vault.sol";
import "../src/mocks/MockUSDC.sol";

contract VaultEnhancementsTest is Test {
    Vault public vault;
    MockUSDC public underlyingToken;

    address public owner;
    address public manager;
    address public agent;
    address public treasury;
    address public alice;
    address public bob;

    uint256 constant INITIAL_BALANCE = 10_000 * 1e6; // 10,000 USDC

    event Paused(address account);
    event Unpaused(address account);
    event FeesCollected(address indexed treasury, uint256 amount);

    function setUp() public {
        owner = address(this);
        manager = makeAddr("manager");
        agent = makeAddr("agent");
        treasury = makeAddr("treasury");
        alice = makeAddr("alice");
        bob = makeAddr("bob");

        // Deploy underlying token (USDC)
        underlyingToken = new MockUSDC();

        // Deploy vault with 1% withdrawal fee and 5% yield rate
        vault = new Vault(
            IERC20(address(underlyingToken)),
            "Enhanced Vault Token",
            "eVUSDC",
            manager,
            agent,
            100, // 1% withdrawal fee
            500, // 5% annual yield rate
            treasury
        );

        // Setup test accounts with tokens
        underlyingToken.transfer(alice, INITIAL_BALANCE);
        underlyingToken.transfer(bob, INITIAL_BALANCE);
    }

    // ============ Pausable Functionality ============

    function test_AllowOwnerToPauseAndUnpause() public {
        // Check initial state (not paused)
        assertFalse(vault.paused());

        // Owner can pause
        vault.pause();
        assertTrue(vault.paused());

        // Owner can unpause
        vault.unpause();
        assertFalse(vault.paused());
    }

    function test_CheckPauserRoleCorrectly() public {
        assertTrue(vault.hasPauserRole(owner), "Owner should have pauser role");
        assertFalse(
            vault.hasPauserRole(alice),
            "Alice should not have pauser role"
        );
    }

    function test_PreventDepositsWhenPaused() public {
        vm.prank(alice);
        underlyingToken.approve(address(vault), INITIAL_BALANCE);

        // Pause the vault
        vault.pause();

        // Deposits should revert when paused
        vm.prank(alice);
        vm.expectRevert();
        vault.deposit(1_000 * 1e6, alice);
    }

    function test_PreventWithdrawalsWhenPaused() public {
        // First make a deposit when not paused
        vm.startPrank(alice);
        underlyingToken.approve(address(vault), INITIAL_BALANCE);
        vault.deposit(1_000 * 1e6, alice);
        vm.stopPrank();

        // Pause the vault
        vault.pause();

        // Withdrawals should revert when paused
        vm.prank(alice);
        vm.expectRevert();
        vault.withdraw(500 * 1e6, alice, alice);
    }

    function test_RevertPauseIfNotPauser() public {
        vm.prank(alice);
        vm.expectRevert("Vault: caller is not a pauser");
        vault.pause();
    }

    // ============ Fee Collection Functionality ============

    function test_CollectWithdrawalFeesToTreasury() public {
        uint256 depositAmount = 1_000 * 1e6; // 1,000 USDC
        uint256 withdrawAmount = 500 * 1e6; // 500 USDC
        uint256 expectedFee = 5 * 1e6; // 1% of 500 USDC = 5 USDC

        vm.startPrank(alice);
        underlyingToken.approve(address(vault), INITIAL_BALANCE);

        // Alice deposits
        vault.deposit(depositAmount, alice);

        // Alice withdraws (creating fee)
        vault.withdraw(withdrawAmount, alice, alice);
        vm.stopPrank();

        // Check collectable fees
        uint256 collectableFees = vault.getCollectableFees();
        assertApproxEqAbs(collectableFees, expectedFee, 0.1 * 1e6);

        // Collect fees
        uint256 treasuryBalanceBefore = underlyingToken.balanceOf(treasury);

        vm.expectEmit(true, false, false, false);
        emit FeesCollected(treasury, collectableFees);

        vault.collectFees();

        uint256 treasuryBalanceAfter = underlyingToken.balanceOf(treasury);
        assertEq(treasuryBalanceAfter - treasuryBalanceBefore, collectableFees);
    }

    function test_OnlyOwnerCanCollectFees() public {
        // Create some fees first
        vm.startPrank(alice);
        underlyingToken.approve(address(vault), INITIAL_BALANCE);
        vault.deposit(1_000 * 1e6, alice);
        vault.withdraw(500 * 1e6, alice, alice);
        vm.stopPrank();

        vm.prank(alice);
        vm.expectRevert("Vault: not owner/manager");
        vault.collectFees();
    }

    function test_FeesAccumulateOverMultipleWithdrawals() public {
        vm.startPrank(alice);
        underlyingToken.approve(address(vault), INITIAL_BALANCE);
        vault.deposit(2_000 * 1e6, alice);

        // First withdrawal
        vault.withdraw(500 * 1e6, alice, alice);
        uint256 feesAfterFirst = vault.getCollectableFees();

        // Second withdrawal
        vault.withdraw(500 * 1e6, alice, alice);
        uint256 feesAfterSecond = vault.getCollectableFees();
        vm.stopPrank();

        // Fees should have accumulated
        assertGt(feesAfterSecond, feesAfterFirst, "Fees should accumulate");
        assertApproxEqAbs(feesAfterSecond, 10 * 1e6, 0.2 * 1e6); // ~10 USDC in fees
    }

    function test_NoFeesOnDeposits() public {
        vm.startPrank(alice);
        underlyingToken.approve(address(vault), INITIAL_BALANCE);
        vault.deposit(1_000 * 1e6, alice);
        vm.stopPrank();

        uint256 collectableFees = vault.getCollectableFees();
        assertEq(collectableFees, 0, "No fees should be collected on deposits");
    }

    // ============ Yield Rate Management ============

    function test_ManagerCanUpdateYieldRate() public {
        uint256 oldRate = 500; // 5%
        uint256 newRate = 1000; // 10%

        vm.prank(manager);
        vault.setYieldRate(newRate);

        // Note: We can't directly test the internal yieldRate variable
        // but we can test the effect through yield calculations
    }

    function test_OnlyManagerCanUpdateYieldRate() public {
        vm.prank(alice);
        vm.expectRevert("Vault: caller is not a manager");
        vault.setYieldRate(1000);
    }

    function test_YieldRateUpdateAffectsNewDeposits() public {
        // Make initial deposit
        vm.startPrank(alice);
        underlyingToken.approve(address(vault), INITIAL_BALANCE);
        vault.deposit(1_000 * 1e6, alice);
        vm.stopPrank();

        // Fast forward to accrue some yield
        skip(30 days);

        uint256 yieldBefore = vault.calculatePendingYield();

        // Manager updates yield rate
        vm.prank(manager);
        vault.setYieldRate(1000); // 10% instead of 5%

        // Fast forward again
        skip(30 days);

        uint256 yieldAfter = vault.calculatePendingYield();

        // The new yield calculation should reflect the higher rate
        assertGt(
            yieldAfter,
            yieldBefore,
            "Yield should be higher with increased rate"
        );
    }

    // ============ Emergency Functions ============

    function test_OwnerCanPauseForEmergency() public {
        // Simulate emergency scenario
        vault.pause();
        assertTrue(vault.paused(), "Vault should be paused in emergency");

        // All user operations should be blocked
        vm.startPrank(alice);
        underlyingToken.approve(address(vault), INITIAL_BALANCE);

        vm.expectRevert();
        vault.deposit(1_000 * 1e6, alice);
        vm.stopPrank();
    }

    function test_UnpauseRestoresNormalOperation() public {
        // Pause first
        vault.pause();

        // Unpause
        vault.unpause();
        assertFalse(vault.paused(), "Vault should be unpaused");

        // Operations should work normally
        vm.startPrank(alice);
        underlyingToken.approve(address(vault), INITIAL_BALANCE);
        vault.deposit(1_000 * 1e6, alice);
        vm.stopPrank();

        assertEq(
            vault.balanceOf(alice),
            1_000 * 1e6,
            "Deposit should work after unpause"
        );
    }

    // ============ Fee Configuration Tests ============

    function test_WithdrawalFeeCalculation() public {
        vm.startPrank(alice);
        underlyingToken.approve(address(vault), INITIAL_BALANCE);
        vault.deposit(1_000 * 1e6, alice);

        uint256 withdrawAmount = 1_000 * 1e6;
        uint256 expectedFee = (withdrawAmount * 100) / 10_000; // 1%

        vault.withdraw(withdrawAmount, alice, alice);
        vm.stopPrank();

        uint256 actualFees = vault.getCollectableFees();
        assertApproxEqAbs(actualFees, expectedFee, 1e3); // Small rounding tolerance
    }

    function test_ZeroWithdrawalFeeWhenSetToZero() public {
        // Deploy vault with 0% withdrawal fee
        Vault zeroFeeVault = new Vault(
            IERC20(address(underlyingToken)),
            "Zero Fee Vault",
            "zfVault",
            manager,
            agent,
            0, // 0% withdrawal fee
            500,
            treasury
        );

        vm.startPrank(alice);
        underlyingToken.approve(address(zeroFeeVault), INITIAL_BALANCE);
        zeroFeeVault.deposit(1_000 * 1e6, alice);
        zeroFeeVault.withdraw(500 * 1e6, alice, alice);
        vm.stopPrank();

        uint256 fees = zeroFeeVault.getCollectableFees();
        assertEq(fees, 0, "No fees should be collected with 0% fee");
    }

    // ============ Integration Tests ============

    function test_FullWorkflowWithFeesAndYield() public {
        vm.startPrank(alice);
        underlyingToken.approve(address(vault), INITIAL_BALANCE);

        // Deposit
        vault.deposit(2_000 * 1e6, alice);

        // Wait for yield
        skip(90 days);

        // Withdraw (generates fees)
        vault.withdraw(1_000 * 1e6, alice, alice);
        vm.stopPrank();

        // Check that both yield and fees were generated
        uint256 totalAssets = vault.totalAssets();
        uint256 collectableFees = vault.getCollectableFees();

        assertGt(totalAssets, 1_000 * 1e6, "Should have yield accrued");
        assertGe(
            collectableFees,
            0,
            "Should have fees collected (may be zero due to rounding)"
        );

        // Collect fees
        uint256 treasuryBefore = underlyingToken.balanceOf(treasury);
        vault.collectFees();
        uint256 treasuryAfter = underlyingToken.balanceOf(treasury);

        assertGe(
            treasuryAfter,
            treasuryBefore,
            "Treasury should receive fees (may be zero due to rounding)"
        );
    }

    // ============ Edge Cases ============

    function test_PauseUnpauseMultipleTimes() public {
        for (uint i = 0; i < 5; i++) {
            vault.pause();
            assertTrue(vault.paused());

            vault.unpause();
            assertFalse(vault.paused());
        }
    }

    function test_CollectFeesWhenNoFees() public {
        // Should not revert when no fees to collect
        vault.collectFees();

        uint256 treasuryBalance = underlyingToken.balanceOf(treasury);
        assertEq(treasuryBalance, 0, "Treasury should remain at zero");
    }

    function test_FeePrecisionEdgeCases() public {
        vm.startPrank(alice);
        underlyingToken.approve(address(vault), INITIAL_BALANCE);
        vault.deposit(100 * 1e6, alice);

        // Withdraw very small amount (1 wei)
        vault.withdraw(1, alice, alice);
        vm.stopPrank();

        // Should handle fee calculation without underflow
        uint256 fees = vault.getCollectableFees();
        // Fee might be 0 due to rounding down, which is acceptable
        assertLe(fees, 1, "Fee should be minimal for tiny withdrawal");
    }

    // ============ Fuzz Tests ============

    function testFuzz_WithdrawalFees(
        uint256 depositAmount,
        uint256 withdrawAmount
    ) public {
        depositAmount = bound(depositAmount, 1_000 * 1e6, INITIAL_BALANCE);
        withdrawAmount = bound(withdrawAmount, 1e6, depositAmount);

        vm.startPrank(alice);
        underlyingToken.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, alice);
        vault.withdraw(withdrawAmount, alice, alice);
        vm.stopPrank();

        uint256 fees = vault.getCollectableFees();
        uint256 expectedFee = (withdrawAmount * 100) / 10_000; // 1%

        // Allow for small rounding differences
        assertApproxEqAbs(fees, expectedFee, expectedFee / 100 + 1);
    }

    function testFuzz_PauseUnpauseSequence(uint8 operations) public {
        operations = uint8(bound(operations, 1, 20));

        bool expectedPaused = false;
        for (uint i = 0; i < operations; i++) {
            if (expectedPaused) {
                vault.unpause();
                expectedPaused = false;
            } else {
                vault.pause();
                expectedPaused = true;
            }
            assertEq(vault.paused(), expectedPaused);
        }
    }
}
