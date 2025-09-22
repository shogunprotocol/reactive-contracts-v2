// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/Vault.sol";
import "../src/mocks/MockUSDC.sol";

contract DecimalsTest is Test {
    Vault public vault;
    MockUSDC public underlyingToken;

    address public owner;
    address public manager;
    address public agent;
    address public treasury;
    address public user;

    uint256 constant INITIAL_BALANCE = 10_000 * 1e6; // 10,000 USDC

    function setUp() public {
        owner = address(this);
        manager = makeAddr("manager");
        agent = makeAddr("agent");
        treasury = makeAddr("treasury");
        user = makeAddr("user");

        // Deploy USDC with 6 decimals
        underlyingToken = new MockUSDC();

        // Deploy vault
        vault = new Vault(
            IERC20(address(underlyingToken)),
            "USDC Vault",
            "vUSDC",
            manager,
            agent,
            0, // 0% withdrawal fee for cleaner tests
            0, // 0% yield rate for cleaner tests
            treasury
        );

        // Setup user with tokens
        underlyingToken.transfer(user, INITIAL_BALANCE);
        vm.prank(user);
        underlyingToken.approve(address(vault), type(uint256).max);
    }

    // ============ DECIMAL VERIFICATION ============

    function test_CorrectDecimalsConfiguration() public {
        console.log("Checking decimal configuration...");

        uint8 usdcDecimals = underlyingToken.decimals();
        uint8 vaultDecimals = vault.decimals();

        console.log("USDC decimals:", usdcDecimals);
        console.log("Vault decimals:", vaultDecimals);

        assertEq(usdcDecimals, 6, "USDC should have 6 decimals");
        assertEq(
            vaultDecimals,
            6,
            "Vault shares should have same decimals as underlying asset"
        );
    }

    function test_OneToOneRatioForInitialDeposits() public {
        console.log("Testing 1:1 ratio for deposits...");

        uint256 depositAmount = 1_000 * 1e6; // 1,000 USDC
        console.log("Depositing: 1000 USDC");

        vm.prank(user);
        vault.deposit(depositAmount, user);

        uint256 userShares = vault.balanceOf(user);
        uint256 totalAssets = vault.totalAssets();
        uint256 totalSupply = vault.totalSupply();

        console.log("User shares received:", userShares / 1e6);
        console.log("Total assets:", totalAssets / 1e6, "USDC");
        console.log("Total supply:", totalSupply / 1e6, "shares");

        // Should be 1:1 ratio
        assertEq(
            userShares,
            depositAmount,
            "Shares should equal deposited assets"
        );
        assertEq(
            totalAssets,
            depositAmount,
            "Total assets should equal deposited amount"
        );
        assertEq(
            totalSupply,
            depositAmount,
            "Total supply should equal deposited amount"
        );
    }

    function test_HandleDustAmountsCorrectly() public {
        console.log("Testing dust amounts...");

        uint256 dustAmount = 1; // 1 wei (0.000001 USDC)
        console.log("Depositing: 1 wei (0.000001 USDC)");

        vm.prank(user);
        vault.deposit(dustAmount, user);

        uint256 userShares = vault.balanceOf(user);
        uint256 totalAssets = vault.totalAssets();

        console.log("User shares:", userShares, "wei");
        console.log("Total assets:", totalAssets, "wei");

        assertEq(
            userShares,
            dustAmount,
            "Even dust amounts should maintain 1:1 ratio"
        );
        assertEq(
            totalAssets,
            dustAmount,
            "Total assets should match dust deposit"
        );
    }

    function test_HandleMaximumPrecisionCorrectly() public {
        console.log("Testing maximum precision...");

        // Test with 1 wei less than 1 USDC
        uint256 maxPrecisionAmount = 1e6 - 1; // 999999 wei
        console.log("Depositing: 999999 wei (0.999999 USDC)");

        vm.prank(user);
        vault.deposit(maxPrecisionAmount, user);

        uint256 userShares = vault.balanceOf(user);
        console.log("User shares:", userShares, "wei");

        assertEq(
            userShares,
            maxPrecisionAmount,
            "Maximum precision should be preserved"
        );
    }

    // ============ EXCHANGE RATE VERIFICATION ============

    function test_MaintainCorrectExchangeRateWithMultipleUsers() public {
        console.log("Testing exchange rates with multiple users...");

        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");

        // Setup users
        underlyingToken.transfer(user1, 2_000 * 1e6);
        underlyingToken.transfer(user2, 3_000 * 1e6);

        vm.prank(user1);
        underlyingToken.approve(address(vault), type(uint256).max);
        vm.prank(user2);
        underlyingToken.approve(address(vault), type(uint256).max);

        // User1 deposits 1000 USDC
        uint256 deposit1 = 1_000 * 1e6;
        vm.prank(user1);
        vault.deposit(deposit1, user1);

        uint256 shares1 = vault.balanceOf(user1);
        console.log("User1 deposited: 1000 USDC");
        console.log("User1 received:", shares1 / 1e6, "shares");

        // User2 deposits 2000 USDC
        uint256 deposit2 = 2_000 * 1e6;
        vm.prank(user2);
        vault.deposit(deposit2, user2);

        uint256 shares2 = vault.balanceOf(user2);
        console.log("User2 deposited: 2000 USDC");
        console.log("User2 received:", shares2 / 1e6, "shares");

        // Verify ratios
        assertEq(shares1, deposit1, "User1 should have 1:1 ratio");
        assertEq(shares2, deposit2, "User2 should have 1:1 ratio");

        // User2 should have exactly 2x User1's shares
        assertEq(shares2, shares1 * 2, "User2 should have 2x User1's shares");
    }

    function test_PreserveRatiosAfterWithdrawals() public {
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");

        // Setup
        underlyingToken.transfer(user1, 2_000 * 1e6);
        underlyingToken.transfer(user2, 3_000 * 1e6);

        vm.prank(user1);
        underlyingToken.approve(address(vault), type(uint256).max);
        vm.prank(user2);
        underlyingToken.approve(address(vault), type(uint256).max);

        // Both users deposit
        vm.prank(user1);
        vault.deposit(1_000 * 1e6, user1);
        vm.prank(user2);
        vault.deposit(2_000 * 1e6, user2);

        // User1 withdraws half
        vm.prank(user1);
        vault.withdraw(500 * 1e6, user1, user1);

        uint256 shares1After = vault.balanceOf(user1);
        uint256 shares2After = vault.balanceOf(user2);

        // Ratios should still be maintained
        assertEq(shares1After, 500 * 1e6, "User1 should have 500 shares left");
        assertEq(
            shares2After,
            2_000 * 1e6,
            "User2 should still have 2000 shares"
        );
        assertEq(shares2After, shares1After * 4, "Ratio should be preserved");
    }

    // ============ PRECISION EDGE CASES ============

    function test_HandleMultipleSmallDeposits() public {
        console.log("Testing multiple small deposits...");

        uint256 smallAmount = 100; // 100 wei (0.0001 USDC)
        uint256 totalExpected = 0;

        // Make 10 small deposits
        for (uint i = 0; i < 10; i++) {
            vm.prank(user);
            vault.deposit(smallAmount, user);
            totalExpected += smallAmount;
        }

        uint256 totalShares = vault.balanceOf(user);
        uint256 totalAssets = vault.totalAssets();

        console.log("Total small deposits:", totalExpected, "wei");
        console.log("Total shares received:", totalShares, "wei");
        console.log("Total assets in vault:", totalAssets, "wei");

        assertEq(
            totalShares,
            totalExpected,
            "Total shares should equal sum of deposits"
        );
        assertEq(
            totalAssets,
            totalExpected,
            "Total assets should equal sum of deposits"
        );
    }

    function test_HandleLargeAmounts() public {
        console.log("Testing large amounts...");

        uint256 largeAmount = 1_000_000 * 1e6; // 1M USDC
        underlyingToken.mint(user, largeAmount);

        vm.prank(user);
        underlyingToken.approve(address(vault), largeAmount);

        vm.prank(user);
        vault.deposit(largeAmount, user);

        uint256 userShares = vault.balanceOf(user);
        console.log("Large deposit: 1M USDC");
        console.log("Shares received:", userShares / 1e6);

        assertEq(
            userShares,
            largeAmount,
            "Large amounts should maintain 1:1 ratio"
        );
    }

    // ============ ROUNDING BEHAVIOR ============

    function test_RoundingBehaviorConsistency() public {
        // Test edge case where rounding might occur
        uint256 oddAmount = 999_999; // 0.999999 USDC

        vm.prank(user);
        vault.deposit(oddAmount, user);

        uint256 shares = vault.balanceOf(user);

        // Should not lose precision
        assertEq(
            shares,
            oddAmount,
            "No precision should be lost in odd amounts"
        );

        // Withdraw the same amount
        vm.prank(user);
        uint256 assetsWithdrawn = vault.redeem(shares, user, user);

        assertEq(
            assetsWithdrawn,
            oddAmount,
            "Withdrawal should return exact amount"
        );
    }

    // ============ FUZZ TESTS ============

    function testFuzz_DepositWithdrawRoundTrip(uint256 amount) public {
        amount = bound(amount, 1, INITIAL_BALANCE);

        vm.startPrank(user);
        vault.deposit(amount, user);
        uint256 shares = vault.balanceOf(user);
        uint256 assetsWithdrawn = vault.redeem(shares, user, user);
        vm.stopPrank();

        assertEq(
            assetsWithdrawn,
            amount,
            "Round trip should preserve exact amount"
        );
    }

    function testFuzz_ShareCalculationAccuracy(
        uint256 deposit1,
        uint256 deposit2
    ) public {
        deposit1 = bound(deposit1, 1, INITIAL_BALANCE / 3);
        deposit2 = bound(deposit2, 1, INITIAL_BALANCE / 3);

        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");

        underlyingToken.transfer(user1, deposit1);
        underlyingToken.transfer(user2, deposit2);

        vm.prank(user1);
        underlyingToken.approve(address(vault), deposit1);
        vm.prank(user2);
        underlyingToken.approve(address(vault), deposit2);

        vm.prank(user1);
        vault.deposit(deposit1, user1);
        vm.prank(user2);
        vault.deposit(deposit2, user2);

        uint256 shares1 = vault.balanceOf(user1);
        uint256 shares2 = vault.balanceOf(user2);

        // Shares should be proportional to deposits
        assertEq(shares1, deposit1, "User1 shares should equal deposit");
        assertEq(shares2, deposit2, "User2 shares should equal deposit");

        if (deposit1 > 0 && deposit2 > 0) {
            // Ratio test
            uint256 expectedRatio = (deposit2 * 1e18) / deposit1;
            uint256 actualRatio = (shares2 * 1e18) / shares1;
            assertApproxEqRel(actualRatio, expectedRatio, 1e15); // 0.1% tolerance
        }
    }
}
