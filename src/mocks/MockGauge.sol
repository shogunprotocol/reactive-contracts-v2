// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interfaces/IGauge.sol";

contract MockGauge is IGauge {
    mapping(uint256 => bool) public deposited;
    mapping(uint256 => uint256) public depositTime;
    mapping(uint256 => address) public depositor;

    uint256 public rewardRate = 1 ether; // 1 reward token per second
    uint256 public bonusRewardRate = 0.5 ether; // 0.5 bonus reward per second

    function deposit(uint256 tokenId) external {
        deposited[tokenId] = true;
        depositTime[tokenId] = block.timestamp;
        depositor[tokenId] = msg.sender;
    }

    function withdraw(uint256 tokenId) external {
        require(deposited[tokenId], "not-deposited");
        require(depositor[tokenId] == msg.sender, "not-depositor");
        deposited[tokenId] = false;
        delete depositTime[tokenId];
        delete depositor[tokenId];
    }

    function earned(
        uint256 tokenId
    ) external view returns (uint256 reward, uint256 bonusReward) {
        if (!deposited[tokenId]) return (0, 0);

        uint256 timeStaked = block.timestamp - depositTime[tokenId];
        reward = timeStaked * rewardRate;
        bonusReward = timeStaked * bonusRewardRate;
    }

    function getReward(uint256 tokenId, bool isBonusReward) external {
        require(deposited[tokenId], "not-deposited");
        require(depositor[tokenId] == msg.sender, "not-depositor");

        (uint256 reward, uint256 bonusReward) = this.earned(tokenId);

        if (isBonusReward) {
            // Reset deposit time to simulate claiming bonus reward
            depositTime[tokenId] = block.timestamp;
        } else {
            // For regular rewards, we don't reset time in this simple mock
        }
    }

    // Helper functions for testing
    function setRewardRate(uint256 _rewardRate) external {
        rewardRate = _rewardRate;
    }

    function setBonusRewardRate(uint256 _bonusRewardRate) external {
        bonusRewardRate = _bonusRewardRate;
    }

    function isDeposited(uint256 tokenId) external view returns (bool) {
        return deposited[tokenId];
    }
}
