// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title VaultFees
/// @notice Handles fee management and treasury operations for the vault
/// @dev Provides withdrawal fee calculation and treasury management
abstract contract VaultFees {
    using SafeERC20 for IERC20;

    // ============ State Variables ============
    /// @notice Withdrawal fee in basis points (1000 = 10%)
    /// @dev Fee charged on withdrawals, where 10000 = 100%
    uint256 public immutable withdrawalFee;

    /// @notice Maximum withdrawal fee allowed (10%)
    /// @dev Prevents setting fees higher than 10%
    uint256 public constant MAX_WITHDRAWAL_FEE = 1000;

    /// @notice Treasury address for fee collection
    /// @dev Address where collected fees are sent
    address public treasury;

    // ============ Events ============
    event WithdrawalFeeCollected(address indexed user, uint256 feeAmount);
    event FeesCollected(address indexed treasury, uint256 amount);
    event TreasuryUpdated(
        address indexed oldTreasury,
        address indexed newTreasury
    );

    // ============ Errors ============
    error WithdrawalFeeTooHigh();
    error InvalidTreasury();

    // ============ Modifiers (to be overridden by inheriting contract) ============
    modifier onlyManager() virtual {
        _;
    }

    // ============ Constructor ============
    /// @notice Initializes the fees module with withdrawal fee and treasury
    /// @param _withdrawalFee Withdrawal fee in basis points (max 1000 = 10%)
    /// @param _treasury Treasury address for fee collection
    constructor(uint256 _withdrawalFee, address _treasury) {
        if (_treasury == address(0)) revert InvalidTreasury();
        if (_withdrawalFee > MAX_WITHDRAWAL_FEE) revert WithdrawalFeeTooHigh();

        withdrawalFee = _withdrawalFee;
        treasury = _treasury;
    }

    // ============ Fee Management Functions ============
    /**
     * @dev Sets a new treasury address
     * @param newTreasury The new treasury address
     * @notice Only callable by owner
     */
    function setTreasury(address newTreasury) external {
        _requireOwner();

        if (newTreasury == address(0)) revert InvalidTreasury();

        address oldTreasury = treasury;
        treasury = newTreasury;

        emit TreasuryUpdated(oldTreasury, newTreasury);
    }

    /**
     * @dev Collects accumulated withdrawal fees and sends them to treasury
     * @notice Only callable by owner or manager
     * @dev Calculates fees as vault balance minus baseAssets and accruedYield
     */
    function collectFees() external {
        // Access control check will be implemented in the inheriting contract
        _requireOwnerOrManager();

        // Calculate available fees: total balance minus actual vault assets
        uint256 vaultBalance = IERC20(asset()).balanceOf(address(this));
        uint256 actualVaultAssets = getBaseAssets() + getAccruedYield();

        if (vaultBalance <= actualVaultAssets) {
            return; // No fees to collect
        }

        uint256 feesToCollect = vaultBalance - actualVaultAssets;

        if (feesToCollect > 0) {
            IERC20(asset()).safeTransfer(treasury, feesToCollect);
            emit FeesCollected(treasury, feesToCollect);
        }
    }

    // ============ View Functions ============
    /**
     * @dev Returns the amount of fees available for collection
     * @return uint256 The amount of fees that can be collected
     */
    function getCollectableFees() external view returns (uint256) {
        uint256 vaultBalance = IERC20(asset()).balanceOf(address(this));
        uint256 actualVaultAssets = getBaseAssets() +
            getAccruedYield() +
            calculatePendingYield();

        return
            vaultBalance > actualVaultAssets
                ? vaultBalance - actualVaultAssets
                : 0;
    }

    /**
     * @dev Returns the withdrawal fee in basis points
     * @return uint256 The withdrawal fee (10000 = 100%)
     */
    function getWithdrawalFee() external view returns (uint256) {
        return withdrawalFee;
    }

    /**
     * @dev Calculates the fee for a given withdrawal amount
     * @param assets The amount of assets being withdrawn
     * @return uint256 The fee amount
     */
    function calculateWithdrawalFee(
        uint256 assets
    ) external view returns (uint256) {
        return (assets * withdrawalFee) / 10000;
    }

    // ============ Internal Functions ============
    /**
     * @dev Internal function to check owner access
     * @dev Must be implemented by inheriting contract
     */
    function _requireOwner() internal view virtual;

    /**
     * @dev Internal function to check owner or manager access
     * @dev Must be implemented by inheriting contract
     */
    function _requireOwnerOrManager() internal view virtual;

    // ============ Abstract Functions ============
    /// @dev Returns the underlying asset address - must be implemented by inheriting contract
    function asset() public view virtual returns (address);

    /// @dev Returns the base assets amount - must be implemented by inheriting contract
    function getBaseAssets() public view virtual returns (uint256);

    /// @dev Returns the accrued yield amount - must be implemented by inheriting contract
    function getAccruedYield() public view virtual returns (uint256);

    /// @dev Returns the pending yield amount - must be implemented by inheriting contract
    function calculatePendingYield() public view virtual returns (uint256);
}
