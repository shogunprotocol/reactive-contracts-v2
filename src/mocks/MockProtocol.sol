// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title MockProtocol
 * @dev A mock protocol that simulates a DeFi protocol with basic functionality
 * @notice This is used for testing the Strategies contract
 */
contract MockProtocol {
    using SafeERC20 for IERC20;

    // State variables
    IERC20 public immutable underlyingToken;
    IERC20 public immutable rewardToken;
    mapping(address => uint256) public deposits;
    mapping(address => uint256) public rewards;

    // Events
    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardsClaimed(address indexed user, uint256 amount);

    // Errors
    error InsufficientBalance();
    error ZeroAmount();

    constructor(address _underlyingToken, address _rewardToken) {
        underlyingToken = IERC20(_underlyingToken);
        rewardToken = IERC20(_rewardToken);
    }

    /**
     * @dev Deposits tokens into the protocol
     * @param amount Amount of tokens to deposit
     */
    function deposit(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();

        underlyingToken.safeTransferFrom(msg.sender, address(this), amount);
        deposits[msg.sender] += amount;

        // Simulate some rewards (10% of deposit)
        rewards[msg.sender] += amount / 10;

        emit Deposited(msg.sender, amount);
    }

    /**
     * @dev Withdraws tokens from the protocol
     * @param amount Amount of tokens to withdraw
     */
    function withdraw(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        if (deposits[msg.sender] < amount) revert InsufficientBalance();

        deposits[msg.sender] -= amount;
        underlyingToken.safeTransfer(msg.sender, amount);

        emit Withdrawn(msg.sender, amount);
    }

    /**
     * @dev Claims rewards from the protocol
     */
    function claimRewards() external {
        uint256 rewardAmount = rewards[msg.sender];
        if (rewardAmount == 0) revert ZeroAmount();

        rewards[msg.sender] = 0;
        rewardToken.safeTransfer(msg.sender, rewardAmount);

        emit RewardsClaimed(msg.sender, rewardAmount);
    }

    /**
     * @dev Gets the balance of a user
     * @param user Address of the user
     * @return uint256 Balance of the user
     */
    function getBalance(address user) external view returns (uint256) {
        return deposits[user];
    }

    /**
     * @dev Gets the reward token address
     * @return address Address of the reward token
     */
    function getRewardToken() external view returns (address) {
        return address(rewardToken);
    }
}
