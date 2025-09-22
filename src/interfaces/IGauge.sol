// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IGauge {
    function deposit(uint256 tokenId) external;

    function withdraw(uint256 tokenId) external;

    function earned(
        uint256 tokenId
    ) external view returns (uint256 reward, uint256 bonusReward);

    function getReward(uint256 tokenId, bool isBonusReward) external;
}
