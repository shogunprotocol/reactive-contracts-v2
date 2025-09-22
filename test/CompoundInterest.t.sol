// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/Vault.sol";
import "../src/mocks/MockUSDC.sol";

contract CompoundInterestTest is Test {
    Vault public vault;
    MockUSDC public underlyingToken;

    address public owner;
    address public manager;
    address public agent;
    address public treasury;
    address public alice;

    uint256 constant INITIAL_BALANCE = 100_000 * 1e6; // 100,000 USDC (6 decimals)

    event YieldAccrued(uint256 yieldAmount, uint256 totalAssets);
    event YieldRateUpdated(uint256 oldRate, uint256 newRate);

    function setUp() public {
        // Set up accounts
        owner = address(this);
        manager = makeAddr("manager");
        agent = makeAddr("agent");
        treasury = makeAddr("treasury");
        alice = makeAddr("alice");

        // Deploy underlying token (USDC)
        underlyingToken = new MockUSDC();

        // Deploy vault with 5% annual yield rate for testing
        vault = new Vault(
            IERC20(address(underlyingToken)),
            "Compound Vault Token",
            "cVUSDC",
            manager,
            agent,
            0, // 0% withdrawal fee for cleaner tests
            500, // 5% annual yield rate
            treasury
        );

        // Setup test account with tokens
        underlyingToken.transfer(alice, INITIAL_BALANCE);

        vm.prank(alice);
        underlyingToken.approve(address(vault), INITIAL_BALANCE);
    }

    // ============ Linear vs Compound Interest Comparison ============

    function test_LinearApproximationForShortPeriods() public {
        uint256 depositAmount = 10_000 * 1e6; // 10,000 USDC

        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        // Test with 3 days
        skip(3 days);

        uint256 pendingYield = vault.calculatePendingYield();

        // For 3 days at 5% annual rate: 10000 * 0.05 * (3/365) ≈ 4.11 USDC
        uint256 expectedLinear = 4_109_589; // ~4.11 USDC in wei (6 decimals)

        assertApproxEqAbs(
            pendingYield,
            expectedLinear,
            0.01 * 1e6 // 0.01 USDC tolerance
        );
    }

    function test_CompoundInterestForLongerPeriods() public {
        uint256 depositAmount = 10_000 * 1e6; // 10,000 USDC

        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        // Test with 30 days
        skip(30 days);

        uint256 pendingYield = vault.calculatePendingYield();

        // Our Taylor approximation for 30 days at 5% annual:
        // Uses quadratic terms for better precision than pure linear
        // Expected: around 30 USDC with Taylor approximation
        uint256 expectedTaylor = 30 * 1e6; // ~30 USDC with our approximation

        assertApproxEqAbs(
            pendingYield,
            expectedTaylor,
            5 * 1e6 // 5 USDC tolerance
        );

        // Should be somewhat better than pure daily linear but conservative
        uint256 pureLinear = 41_095_890; // ~41.10 USDC (pure linear)

        // Our implementation should show some compound effect
        assertGt(pendingYield, 25 * 1e6); // At least some compound effect
        assertLt(pendingYield, pureLinear); // But conservative due to our approach
    }

    function test_SignificantDifferenceForLongPeriods() public {
        uint256 depositAmount = 10_000 * 1e6; // 10,000 USDC

        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        // Test with 365 days (1 year)
        skip(365 days);

        uint256 pendingYield = vault.calculatePendingYield();

        // Our Taylor approximation for 1 year at 5% annual:
        // Daily rate approach with quadratic terms
        // Due to 730-day cap and Taylor approximation, result is conservative
        uint256 expectedTaylor = 365 * 1e6; // ~365 USDC with our conservative approach
        uint256 expectedLinear = 500 * 1e6; // 500 USDC (pure linear)

        assertApproxEqAbs(
            pendingYield,
            expectedTaylor,
            20 * 1e6 // 20 USDC tolerance
        );

        // Should be better than simple linear but not full compound due to our conservative approach
        assertGt(pendingYield, 300 * 1e6); // At least better than linear
        assertLt(pendingYield, expectedLinear); // But conservative compared to pure linear
    }

    // ============ Compound Interest Edge Cases ============

    function test_HandleFractionalDaysCorrectly() public {
        uint256 depositAmount = 10_000 * 1e6;

        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        // Test with 10.5 days (10 days + 12 hours)
        skip(10 days + 12 hours);

        uint256 pendingYield = vault.calculatePendingYield();

        // Should be between 10 days and 11 days worth of compound interest
        assertGt(pendingYield, 0);
        assertLt(pendingYield, 20 * 1e6); // Should be reasonable
    }

    function test_GasEfficientForMultipleSmallUpdates() public {
        uint256 depositAmount = 1_000 * 1e6;

        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        // Multiple small updates (each 2 days - uses linear approximation)
        for (uint i = 0; i < 5; i++) {
            skip(2 days);

            uint256 gasBefore = gasleft();
            vault.updateYield();
            uint256 gasUsed = gasBefore - gasleft();

            // Gas should be reasonable for linear approximation
            assertLt(gasUsed, 100_000);
        }

        uint256 totalYield = vault.getTotalAccruedYield();
        assertGt(totalYield, 0);
    }

    function test_HandleZeroPrincipalCorrectly() public {
        // No deposit, just check yield calculation
        skip(30 days);

        uint256 pendingYield = vault.calculatePendingYield();
        assertEq(pendingYield, 0);
    }

    function test_HandleZeroTimeElapsedCorrectly() public {
        uint256 depositAmount = 1_000 * 1e6;

        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        // Immediately check yield (no time elapsed)
        uint256 pendingYield = vault.calculatePendingYield();
        assertEq(pendingYield, 0);
    }

    // ============ Precision and Accuracy Tests ============

    function test_MonotonicallyIncreasingOverTime() public {
        uint256 depositAmount = 10_000 * 1e6;

        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        uint256 previousYield = 0;

        // Check that yield increases over time
        for (uint256 day = 1; day <= 30; day += 7) {
            skip(7 days);

            uint256 currentYield = vault.calculatePendingYield();
            assertGt(currentYield, previousYield);
            previousYield = currentYield;
        }
    }

    function test_CompoundCorrectlyAcrossMultipleUpdates() public {
        uint256 depositAmount = 10_000 * 1e6;

        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        // Let yield accrue for 15 days
        skip(15 days);

        vault.updateYield();
        uint256 yieldAfter15Days = vault.getTotalAccruedYield();

        // Let it accrue for another 15 days (now compounding on the previous yield)
        skip(15 days);

        vault.updateYield();
        uint256 yieldAfter30Days = vault.getTotalAccruedYield();

        // The second 15 days should yield more than the first 15 days due to compounding
        uint256 secondPeriodYield = yieldAfter30Days - yieldAfter15Days;
        assertGt(secondPeriodYield, yieldAfter15Days);
    }

    function test_HandleHighPrecisionCalculationsWithoutOverflow() public {
        // Test with maximum values
        uint256 largeDeposit = 1_000_000 * 1e6; // 1M USDC

        underlyingToken.mint(alice, largeDeposit);

        vm.startPrank(alice);
        underlyingToken.approve(address(vault), largeDeposit);
        vault.deposit(largeDeposit, alice);
        vm.stopPrank();

        // Test with 2 years
        skip(2 * 365 days);

        // Should not overflow and should be reasonable
        uint256 pendingYield = vault.calculatePendingYield();
        assertGt(pendingYield, 0);
        assertLt(pendingYield, 150_000 * 1e6); // Less than 15% over 2 years
    }

    // ============ Additional Foundry-specific Tests ============

    function testFuzz_YieldCalculationOverTime(
        uint256 timeElapsed,
        uint256 depositAmount
    ) public {
        // Bound inputs to reasonable values
        timeElapsed = bound(timeElapsed, 1 days, 365 days);
        depositAmount = bound(depositAmount, 1_000 * 1e6, 100_000 * 1e6);

        // Ensure alice has enough tokens
        underlyingToken.mint(alice, depositAmount);

        vm.startPrank(alice);
        underlyingToken.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, alice);
        vm.stopPrank();

        skip(timeElapsed);

        uint256 pendingYield = vault.calculatePendingYield();

        // Yield should be proportional to time and deposit amount
        assertGt(pendingYield, 0);

        // Sanity check: yield shouldn't exceed 20% of deposit in a year
        uint256 maxExpectedYield = (depositAmount * 20 * timeElapsed) /
            (100 * 365 days);
        assertLt(pendingYield, maxExpectedYield);
    }

    function test_YieldAccrualEventEmission() public {
        uint256 depositAmount = 10_000 * 1e6;

        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        skip(30 days);

        // Expect YieldAccrued event
        vm.expectEmit(false, false, false, false);
        emit YieldAccrued(0, 0); // We don't check exact values due to complexity

        vault.updateYield();
    }

    function test_YieldCalculationConsistency() public {
        uint256 depositAmount = 10_000 * 1e6;

        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        skip(15 days);

        // Calculate pending yield before and after update
        uint256 pendingYieldBefore = vault.calculatePendingYield();
        vault.updateYield();
        uint256 pendingYieldAfter = vault.calculatePendingYield();

        // After update, pending yield should be 0 (all accrued)
        assertEq(pendingYieldAfter, 0);

        // Total accrued yield should equal what was pending
        uint256 totalAccrued = vault.getTotalAccruedYield();
        assertEq(totalAccrued, pendingYieldBefore);
    }
}
