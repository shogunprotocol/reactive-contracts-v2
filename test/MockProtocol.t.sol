// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/mocks/MockProtocol.sol";
import "../src/mocks/MockERC20.sol";

contract MockProtocolTest is Test {
    MockProtocol public protocol;
    MockERC20 public underlyingToken;
    MockERC20 public rewardToken;

    address public owner;
    address public alice;
    address public bob;

    uint256 constant INITIAL_BALANCE = 1000 ether;
    uint256 constant PROTOCOL_REWARD_BALANCE = 100000 ether;

    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardsClaimed(address indexed user, uint256 amount);

    function setUp() public {
        // Set up accounts
        owner = address(this);
        alice = makeAddr("alice");
        bob = makeAddr("bob");

        // Deploy tokens
        underlyingToken = new MockERC20("Underlying Token", "UNDER", 18);
        rewardToken = new MockERC20("Reward Token", "REWARD", 18);

        // Deploy protocol
        protocol = new MockProtocol(
            address(underlyingToken),
            address(rewardToken)
        );

        // Setup test accounts with initial tokens
        underlyingToken.mint(alice, INITIAL_BALANCE);
        underlyingToken.mint(bob, INITIAL_BALANCE);

        // Fund protocol with reward tokens
        rewardToken.mint(address(protocol), PROTOCOL_REWARD_BALANCE);
    }

    // ============ Constructor Tests ============

    function test_Constructor_SetsCorrectUnderlyingToken() public {
        assertEq(address(protocol.underlyingToken()), address(underlyingToken));
    }

    function test_Constructor_SetsCorrectRewardToken() public {
        assertEq(address(protocol.rewardToken()), address(rewardToken));
    }

    // ============ Deposit Tests ============

    function test_Deposit_DepositTokensSuccessfully() public {
        uint256 depositAmount = 100 ether;

        // Approve and deposit as Alice
        vm.startPrank(alice);
        underlyingToken.approve(address(protocol), depositAmount);

        // Check event emission
        vm.expectEmit(true, true, true, true);
        emit Deposited(alice, depositAmount);

        protocol.deposit(depositAmount);
        vm.stopPrank();

        // Verify balances
        assertEq(protocol.deposits(alice), depositAmount);
        assertEq(protocol.rewards(alice), depositAmount / 10); // 10% rewards
        assertEq(
            underlyingToken.balanceOf(alice),
            INITIAL_BALANCE - depositAmount
        );
        assertEq(underlyingToken.balanceOf(address(protocol)), depositAmount);
    }

    function test_Deposit_HandleMultipleDeposits() public {
        uint256 firstDeposit = 100 ether;
        uint256 secondDeposit = 50 ether;
        uint256 totalDeposit = firstDeposit + secondDeposit;

        vm.startPrank(alice);
        underlyingToken.approve(address(protocol), totalDeposit);

        protocol.deposit(firstDeposit);
        protocol.deposit(secondDeposit);
        vm.stopPrank();

        assertEq(protocol.deposits(alice), totalDeposit);
        assertEq(protocol.rewards(alice), totalDeposit / 10);
    }

    function test_Deposit_RevertWithZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(MockProtocol.ZeroAmount.selector);
        protocol.deposit(0);
    }

    function test_Deposit_RevertWithoutApproval() public {
        uint256 depositAmount = 100 ether;

        vm.prank(alice);
        vm.expectRevert();
        protocol.deposit(depositAmount);
    }

    // ============ Withdraw Tests ============

    function test_Withdraw_WithdrawTokensSuccessfully() public {
        uint256 depositAmount = 100 ether;
        uint256 withdrawAmount = 50 ether;

        // Setup: Alice deposits first
        vm.startPrank(alice);
        underlyingToken.approve(address(protocol), depositAmount);
        protocol.deposit(depositAmount);

        // Test withdrawal
        vm.expectEmit(true, true, true, true);
        emit Withdrawn(alice, withdrawAmount);

        protocol.withdraw(withdrawAmount);
        vm.stopPrank();

        assertEq(protocol.deposits(alice), depositAmount - withdrawAmount);
        assertEq(
            underlyingToken.balanceOf(alice),
            INITIAL_BALANCE - depositAmount + withdrawAmount
        );
    }

    function test_Withdraw_AllowFullWithdrawal() public {
        uint256 depositAmount = 100 ether;

        // Setup: Alice deposits first
        vm.startPrank(alice);
        underlyingToken.approve(address(protocol), depositAmount);
        protocol.deposit(depositAmount);

        // Full withdrawal
        protocol.withdraw(depositAmount);
        vm.stopPrank();

        assertEq(protocol.deposits(alice), 0);
        assertEq(underlyingToken.balanceOf(alice), INITIAL_BALANCE);
    }

    function test_Withdraw_RevertWithInsufficientBalance() public {
        uint256 depositAmount = 100 ether;

        // Setup: Alice deposits first
        vm.startPrank(alice);
        underlyingToken.approve(address(protocol), depositAmount);
        protocol.deposit(depositAmount);

        // Try to withdraw more than deposited
        vm.expectRevert(MockProtocol.InsufficientBalance.selector);
        protocol.withdraw(depositAmount + 1);
        vm.stopPrank();
    }

    function test_Withdraw_RevertWithZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(MockProtocol.ZeroAmount.selector);
        protocol.withdraw(0);
    }

    // ============ Claim Rewards Tests ============

    function test_ClaimRewards_ClaimRewardsSuccessfully() public {
        uint256 depositAmount = 100 ether;
        uint256 expectedRewards = depositAmount / 10;

        // Setup: Alice deposits to generate rewards
        vm.startPrank(alice);
        underlyingToken.approve(address(protocol), depositAmount);
        protocol.deposit(depositAmount);

        // Claim rewards
        vm.expectEmit(true, true, true, true);
        emit RewardsClaimed(alice, expectedRewards);

        protocol.claimRewards();
        vm.stopPrank();

        // Verify balances
        assertEq(protocol.rewards(alice), 0);
        assertEq(rewardToken.balanceOf(alice), expectedRewards);
    }

    function test_ClaimRewards_RevertWithZeroRewards() public {
        vm.prank(alice);
        vm.expectRevert(MockProtocol.ZeroAmount.selector);
        protocol.claimRewards();
    }

    function test_ClaimRewards_HandleMultipleClaims() public {
        uint256 depositAmount = 100 ether;
        uint256 rewardsPerDeposit = depositAmount / 10;

        vm.startPrank(alice);
        underlyingToken.approve(address(protocol), depositAmount * 2);

        // First deposit and claim
        protocol.deposit(depositAmount);
        protocol.claimRewards();

        // Second deposit and claim
        protocol.deposit(depositAmount);
        protocol.claimRewards();
        vm.stopPrank();

        assertEq(rewardToken.balanceOf(alice), rewardsPerDeposit * 2);
    }

    // ============ View Functions Tests ============

    function test_ViewFunctions_ReturnCorrectBalance() public {
        uint256 depositAmount = 100 ether;

        vm.startPrank(alice);
        underlyingToken.approve(address(protocol), depositAmount);
        protocol.deposit(depositAmount);
        vm.stopPrank();

        assertEq(protocol.getBalance(alice), depositAmount);
        assertEq(protocol.getBalance(bob), 0);
    }

    function test_ViewFunctions_ReturnRewardTokenAddress() public {
        assertEq(protocol.getRewardToken(), address(rewardToken));
    }

    // ============ Integration Tests ============

    function test_Integration_HandleMultipleUsersCorrectly() public {
        uint256 aliceDeposit = 100 ether;
        uint256 bobDeposit = 200 ether;

        // Alice deposits
        vm.startPrank(alice);
        underlyingToken.approve(address(protocol), aliceDeposit);
        protocol.deposit(aliceDeposit);
        vm.stopPrank();

        // Bob deposits
        vm.startPrank(bob);
        underlyingToken.approve(address(protocol), bobDeposit);
        protocol.deposit(bobDeposit);
        vm.stopPrank();

        // Verify individual balances
        assertEq(protocol.deposits(alice), aliceDeposit);
        assertEq(protocol.deposits(bob), bobDeposit);
        assertEq(protocol.rewards(alice), aliceDeposit / 10);
        assertEq(protocol.rewards(bob), bobDeposit / 10);

        // Alice withdraws half
        vm.prank(alice);
        protocol.withdraw(aliceDeposit / 2);

        // Bob claims rewards
        vm.prank(bob);
        protocol.claimRewards();

        // Final verification
        assertEq(protocol.deposits(alice), aliceDeposit / 2);
        assertEq(protocol.deposits(bob), bobDeposit);
        assertEq(protocol.rewards(bob), 0);
        assertEq(rewardToken.balanceOf(bob), bobDeposit / 10);
    }

    function test_Integration_HandleComplexFlow() public {
        uint256 amount = 100 ether;

        // Alice: deposit -> partial withdraw -> claim -> deposit again
        vm.startPrank(alice);
        underlyingToken.approve(address(protocol), amount * 2);

        protocol.deposit(amount);
        protocol.withdraw(amount / 2);
        protocol.claimRewards();
        protocol.deposit(amount / 2);
        vm.stopPrank();

        assertEq(protocol.deposits(alice), amount);
        assertEq(protocol.rewards(alice), amount / 20); // 5% from second deposit
        assertEq(rewardToken.balanceOf(alice), amount / 10); // 10% from first deposit
    }

    // ============ Fuzz Tests ============

    function testFuzz_Deposit_VariousAmounts(uint256 amount) public {
        // Bound the amount to reasonable values
        amount = bound(amount, 1, INITIAL_BALANCE);

        vm.startPrank(alice);
        underlyingToken.approve(address(protocol), amount);
        protocol.deposit(amount);
        vm.stopPrank();

        assertEq(protocol.deposits(alice), amount);
        assertEq(protocol.rewards(alice), amount / 10);
    }

    function testFuzz_WithdrawAfterDeposit(
        uint256 depositAmount,
        uint256 withdrawAmount
    ) public {
        // Bound amounts to reasonable values
        depositAmount = bound(depositAmount, 1, INITIAL_BALANCE);
        withdrawAmount = bound(withdrawAmount, 1, depositAmount);

        // Setup deposit
        vm.startPrank(alice);
        underlyingToken.approve(address(protocol), depositAmount);
        protocol.deposit(depositAmount);

        // Test withdrawal
        protocol.withdraw(withdrawAmount);
        vm.stopPrank();

        assertEq(protocol.deposits(alice), depositAmount - withdrawAmount);
        assertEq(
            underlyingToken.balanceOf(alice),
            INITIAL_BALANCE - depositAmount + withdrawAmount
        );
    }
}
