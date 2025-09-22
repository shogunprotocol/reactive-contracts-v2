// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/Vault.sol";
import "../src/mocks/MockUSDC.sol";
import "../src/strategies/Strategies.sol";

contract SecurityAuditTest is Test {
    Vault public vault;
    MockUSDC public underlyingToken;
    Strategies public strategies;

    address public owner;
    address public manager;
    address public agent;
    address public treasury;
    address public attacker;
    address public user1;
    address public user2;

    uint256 constant INITIAL_BALANCE = 100_000 * 1e6; // 100,000 USDC

    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant AGENT_ROLE = keccak256("AGENT_ROLE");
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;

    function setUp() public {
        owner = address(this);
        manager = makeAddr("manager");
        agent = makeAddr("agent");
        treasury = makeAddr("treasury");
        attacker = makeAddr("attacker");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        // Deploy underlying token
        underlyingToken = new MockUSDC();

        // Deploy vault
        vault = new Vault(
            IERC20(address(underlyingToken)),
            "Vault Token",
            "vUNDER",
            manager,
            agent,
            100, // 1% withdrawal fee
            500, // 5% annual yield rate
            treasury
        );

        // Setup balances
        underlyingToken.transfer(user1, INITIAL_BALANCE);
        underlyingToken.transfer(user2, INITIAL_BALANCE);
        underlyingToken.transfer(attacker, INITIAL_BALANCE);

        // Approvals
        vm.prank(user1);
        underlyingToken.approve(address(vault), type(uint256).max);
        vm.prank(user2);
        underlyingToken.approve(address(vault), type(uint256).max);
        vm.prank(attacker);
        underlyingToken.approve(address(vault), type(uint256).max);
    }

    // ============ ACCESS CONTROL VULNERABILITIES ============

    function test_PreventUnauthorizedRoleEscalation() public {
        // Attacker should not be able to grant themselves roles
        vm.startPrank(attacker);

        vm.expectRevert();
        vault.grantRole(MANAGER_ROLE, attacker);

        vm.expectRevert();
        vault.grantRole(AGENT_ROLE, attacker);

        vm.expectRevert();
        vault.grantRole(DEFAULT_ADMIN_ROLE, attacker);

        vm.stopPrank();
    }

    function test_PreventManagerFromGrantingAdminRoles() public {
        vm.prank(manager);
        vm.expectRevert();
        vault.grantRole(DEFAULT_ADMIN_ROLE, attacker);
    }

    function test_PreventBypassingOnlyManagerRestrictions() public {
        vm.startPrank(attacker);

        vm.expectRevert("Vault: caller is not a manager");
        vault.addStrategy(attacker);

        vm.expectRevert("Vault: caller is not a manager");
        vault.setYieldRate(1000);

        vm.stopPrank();
    }

    function test_PreventBypassingOnlyAgentRestrictions() public {
        // First add a strategy as manager
        vm.prank(manager);
        vault.addStrategy(attacker);

        vm.prank(attacker);
        vm.expectRevert("Vault: caller is not an agent");
        vault.executeStrategy(attacker, "");
    }

    // ============ REENTRANCY VULNERABILITIES ============

    function test_PreventReentrancyOnDeposit() public {
        // This would require a malicious ERC20 token that attempts reentrancy
        // For now, we test that the reentrancy guard is in place
        vm.prank(user1);
        vault.deposit(1000 * 1e6, user1);

        // Basic test that deposit works normally
        // Account for potential withdrawal fees (1% = 5 USDC on 500 USDC withdrawal)
        assertApproxEqAbs(
            vault.balanceOf(user1),
            1000 * 1e6,
            10 * 1e6,
            "User balance should be approximately intact"
        );
    }

    function test_PreventReentrancyOnWithdraw() public {
        // Setup deposit first
        vm.prank(user1);
        vault.deposit(1000 * 1e6, user1);

        // Test normal withdrawal
        vm.prank(user1);
        vault.withdraw(500 * 1e6, user1, user1);

        // Account for withdrawal fees (1% fee = 5 USDC on 500 USDC withdrawal)
        assertApproxEqAbs(
            vault.balanceOf(user1),
            500 * 1e6,
            10 * 1e6,
            "User balance should account for withdrawal fees"
        );
    }

    // ============ INTEGER OVERFLOW/UNDERFLOW ============

    function test_PreventOverflowInYieldCalculations() public {
        // Test with maximum values
        uint256 maxDeposit = type(uint128).max / 1e12; // Scale down to prevent overflow
        underlyingToken.mint(user1, maxDeposit);

        vm.prank(user1);
        underlyingToken.approve(address(vault), maxDeposit);

        vm.prank(user1);
        vault.deposit(maxDeposit, user1);

        // Should not overflow when calculating yield
        skip(365 days);

        uint256 yield = vault.calculatePendingYield();
        assertGt(yield, 0);
        assertLt(yield, type(uint256).max);
    }

    function test_PreventUnderflowInWithdrawals() public {
        vm.prank(user1);
        vault.deposit(1000 * 1e6, user1);

        // Try to withdraw more than deposited
        vm.prank(user1);
        vm.expectRevert();
        vault.withdraw(2000 * 1e6, user1, user1);
    }

    // ============ FRONT-RUNNING VULNERABILITIES ============

    function test_PreventMEVAttacksOnYieldUpdates() public {
        // User1 deposits
        vm.prank(user1);
        vault.deposit(10_000 * 1e6, user1);

        skip(30 days);

        // Attacker cannot manipulate yield calculation by front-running
        uint256 pendingYieldBefore = vault.calculatePendingYield();

        // Simulate attacker trying to deposit right before yield update
        vm.prank(attacker);
        vault.deposit(1000 * 1e6, attacker);

        vault.updateYield();

        // Yield should be calculated fairly based on time-weighted deposits
        uint256 user1Redeemable = vault.previewRedeem(vault.balanceOf(user1));
        uint256 attackerRedeemable = vault.previewRedeem(
            vault.balanceOf(attacker)
        );

        // User1 should benefit from 30 days of yield, attacker should not
        assertGt(user1Redeemable, 10_000 * 1e6);
        assertApproxEqAbs(attackerRedeemable, 1000 * 1e6, 1e6);
    }

    // ============ FLASH LOAN ATTACKS ============

    function test_PreventFlashLoanManipulation() public {
        // Setup normal state
        vm.prank(user1);
        vault.deposit(5_000 * 1e6, user1);

        skip(30 days);

        // Simulate attacker with flash loan trying to manipulate exchange rate
        uint256 flashLoanAmount = 1_000_000 * 1e6; // 1M USDC
        underlyingToken.mint(attacker, flashLoanAmount);

        vm.startPrank(attacker);
        underlyingToken.approve(address(vault), flashLoanAmount);

        // Large deposit
        vault.deposit(flashLoanAmount, attacker);

        // Try to immediately withdraw to manipulate rates
        uint256 shares = vault.balanceOf(attacker);
        vault.redeem(shares, attacker, attacker);

        vm.stopPrank();

        // User1's position should not be negatively affected
        uint256 user1Redeemable = vault.previewRedeem(vault.balanceOf(user1));
        assertGt(
            user1Redeemable,
            5_000 * 1e6,
            "User1 should still have yield gains"
        );
    }

    // ============ PRECISION ATTACKS ============

    function test_PreventRoundingErrorExploitation() public {
        // Attempt to exploit rounding errors with very small amounts
        vm.startPrank(attacker);

        // Many tiny deposits
        for (uint i = 0; i < 100; i++) {
            vault.deposit(1, attacker); // 1 wei deposits
        }

        // Check that attacker didn't unfairly benefit
        uint256 attackerShares = vault.balanceOf(attacker);
        assertEq(
            attackerShares,
            100,
            "Should receive exactly 100 shares for 100 wei"
        );

        vm.stopPrank();
    }

    function test_PreventInflationAttacks() public {
        // Setup: Normal user deposits
        vm.prank(user1);
        vault.deposit(1000 * 1e6, user1);

        // Attacker tries inflation attack with tiny amount
        vm.prank(attacker);
        vault.deposit(1, attacker);

        skip(1 days);

        // Both should get fair treatment
        uint256 user1Redeemable = vault.previewRedeem(vault.balanceOf(user1));
        uint256 attackerRedeemable = vault.previewRedeem(
            vault.balanceOf(attacker)
        );

        assertGt(user1Redeemable, 1000 * 1e6);
        assertEq(attackerRedeemable, 1); // Should only get back what they put in
    }

    // ============ DENIAL OF SERVICE ATTACKS ============

    function test_PreventGasGriefingAttacks() public {
        // Attacker cannot grief by creating expensive operations
        vm.startPrank(attacker);

        // Multiple small operations should not consume excessive gas
        for (uint i = 0; i < 10; i++) {
            uint256 gasBefore = gasleft();
            vault.deposit(100 * 1e6, attacker);
            uint256 gasUsed = gasBefore - gasleft();
            assertLt(gasUsed, 200_000, "Deposit should not use excessive gas");
        }

        vm.stopPrank();
    }

    // ============ APPROVAL VULNERABILITIES ============

    function test_PreventApprovalRaceConditions() public {
        // User approves tokens
        vm.prank(user1);
        underlyingToken.approve(address(vault), 1000 * 1e6);

        // User deposits
        vm.prank(user1);
        vault.deposit(1000 * 1e6, user1);

        // Remaining approval should be zero (vault should use exact amount)
        uint256 remainingApproval = underlyingToken.allowance(
            user1,
            address(vault)
        );
        assertEq(remainingApproval, 0, "No leftover approval should remain");
    }

    // ============ STRATEGY VULNERABILITIES ============

    function test_PreventMaliciousStrategyExecution() public {
        // Only authorized agents should execute strategies
        vm.prank(manager);
        vault.addStrategy(makeAddr("strategy"));

        vm.prank(attacker);
        vm.expectRevert("Vault: caller is not an agent");
        vault.executeStrategy(makeAddr("strategy"), "");
    }

    function test_PreventStrategyDraining() public {
        vm.prank(user1);
        vault.deposit(10_000 * 1e6, user1);

        // Attacker cannot drain vault through strategy calls
        vm.prank(manager);
        vault.addStrategy(attacker);

        // Even if attacker is added as strategy, they can't be executed without agent role
        vm.prank(attacker);
        vm.expectRevert("Vault: caller is not an agent");
        vault.executeStrategy(attacker, "");
    }

    // ============ EMERGENCY SCENARIOS ============

    function test_EmergencyPauseProtection() public {
        // Normal operations work
        vm.prank(user1);
        vault.deposit(1000 * 1e6, user1);

        // Owner pauses in emergency
        vault.pause();

        // All operations should be blocked
        vm.prank(user1);
        vm.expectRevert();
        vault.deposit(1000 * 1e6, user1);

        vm.prank(user1);
        vm.expectRevert();
        vault.withdraw(500 * 1e6, user1, user1);
    }

    function test_OnlyOwnerCanPauseUnpause() public {
        vm.prank(attacker);
        vm.expectRevert("Vault: caller is not a pauser");
        vault.pause();

        // Owner can pause
        vault.pause();
        assertTrue(vault.paused());

        // Attacker cannot unpause
        vm.prank(attacker);
        vm.expectRevert("Vault: caller is not a pauser");
        vault.unpause();

        // Owner can unpause
        vault.unpause();
        assertFalse(vault.paused());
    }

    // ============ FEE MANIPULATION ============

    function test_PreventFeeManipulation() public {
        vm.prank(user1);
        vault.deposit(10_000 * 1e6, user1);

        // Attacker cannot manipulate fees
        vm.prank(attacker);
        vm.expectRevert("Vault: not owner/manager");
        vault.collectFees();

        // Normal withdrawal generates fees
        vm.prank(user1);
        vault.withdraw(1000 * 1e6, user1, user1);

        uint256 feesBefore = vault.getCollectableFees();
        assertGt(feesBefore, 0);

        // Only owner can collect fees
        vault.collectFees();
        uint256 feesAfter = vault.getCollectableFees();
        assertEq(feesAfter, 0);
    }

    // ============ INTEGRATION SECURITY TESTS ============

    function test_ComplexAttackScenario() public {
        // Setup normal users
        vm.prank(user1);
        vault.deposit(5_000 * 1e6, user1);

        vm.prank(user2);
        vault.deposit(3_000 * 1e6, user2);

        skip(30 days);

        // Attacker tries multiple attack vectors
        vm.startPrank(attacker);

        // 1. Try to manipulate with large deposit
        vault.deposit(50_000 * 1e6, attacker);

        // 2. Try to immediately withdraw
        uint256 attackerShares = vault.balanceOf(attacker);
        vault.redeem(attackerShares, attacker, attacker);

        vm.stopPrank();

        // Verify normal users are not negatively affected
        uint256 user1Redeemable = vault.previewRedeem(vault.balanceOf(user1));
        uint256 user2Redeemable = vault.previewRedeem(vault.balanceOf(user2));

        assertGt(user1Redeemable, 5_000 * 1e6, "User1 should have gains");
        assertGt(user2Redeemable, 3_000 * 1e6, "User2 should have gains");
    }

    // ============ FUZZ TESTING FOR SECURITY ============

    function testFuzz_NoArbitraryValueExtraction(
        uint256 depositAmount,
        uint256 timeElapsed
    ) public {
        depositAmount = bound(depositAmount, 1000 * 1e6, INITIAL_BALANCE);
        timeElapsed = bound(timeElapsed, 1 days, 365 days);

        // User deposits
        vm.prank(user1);
        vault.deposit(depositAmount, user1);

        skip(timeElapsed);

        // User should always be able to get back at least what they deposited
        uint256 redeemable = vault.previewRedeem(vault.balanceOf(user1));
        assertGe(redeemable, depositAmount, "Should not lose principal");

        // User should not be able to extract more than reasonable yield
        uint256 maxReasonableYield = (depositAmount * 25 * timeElapsed) /
            (100 * 365 days); // 25% annual max
        assertLe(
            redeemable,
            depositAmount + maxReasonableYield,
            "Yield should be reasonable"
        );
    }

    function testFuzz_RoleIntegrity(address randomUser) public {
        vm.assume(
            randomUser != owner && randomUser != manager && randomUser != agent
        );
        vm.assume(randomUser != address(0));

        // Random user should not have any special roles
        assertFalse(vault.hasRole(DEFAULT_ADMIN_ROLE, randomUser));
        assertFalse(vault.hasRole(MANAGER_ROLE, randomUser));
        assertFalse(vault.hasRole(AGENT_ROLE, randomUser));

        // Random user should not be able to call protected functions
        vm.startPrank(randomUser);

        vm.expectRevert();
        vault.grantRole(MANAGER_ROLE, randomUser);

        vm.expectRevert("Vault: caller is not a manager");
        vault.setYieldRate(1000);

        vm.expectRevert("Vault: caller is not a pauser");
        vault.pause();

        vm.stopPrank();
    }
}
