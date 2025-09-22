// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/Strategies.sol";

/// @title VaultCore
/// @notice Handles core vault functionality including strategy management
/// @dev Provides strategy management and core vault operations
abstract contract VaultCore {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    // ============ State Variables ============
    /// @notice Set of strategy addresses for efficient management
    /// @dev Uses EnumerableSet for O(1) add/remove operations
    EnumerableSet.AddressSet private _strategies;

    /// @notice Annual yield rate in basis points (500 = 5%)
    uint256 public yieldRate;

    /// @notice Maximum yield rate allowed (50%)
    uint256 public constant MAX_YIELD_RATE = 5000;

    /// @notice Timestamp of last yield accrual
    uint256 public lastYieldUpdate;

    /// @notice Total yield accrued but not yet distributed
    uint256 public accruedYield;

    /// @notice Base asset amount (deposits minus withdrawals, excluding yield)
    uint256 public baseAssets;

    // ============ Events ============
    event StrategyAdded(address indexed strategy);
    event StrategyRemoved(address indexed strategy);
    event StrategyExecuted(address indexed strategy, bytes data);
    event StrategyHarvested(address indexed strategy, bytes data);
    event EmergencyExit(address indexed strategy, bytes data);

    // ============ Errors ============
    error InvalidStrategy();
    error StrategyAlreadyExists();
    error StrategyDoesNotExist();
    error ExecutionFailed();
    error InvalidAddress();
    error InsufficientBalance();

    // ============ Modifiers (to be implemented by inheriting contract) ============
    modifier onlyManager() virtual {
        _;
    }

    modifier onlyAgent() virtual {
        _;
    }

    // These modifiers will be provided by the inheriting contract
    modifier whenVaultNotPaused() virtual;
    modifier nonReentrantVault() virtual;

    // ============ Strategy Management Functions ============
    /**
     * @dev Adds a new strategy to the vault
     * @param strategy The address of the strategy to add
     */
    function addStrategy(address strategy) external onlyManager {
        if (strategy == address(0)) revert InvalidAddress();
        if (_strategies.contains(strategy)) revert StrategyAlreadyExists();

        _strategies.add(strategy);

        emit StrategyAdded(strategy);
    }

    /**
     * @dev Removes a strategy from the vault
     * @param strategy The address of the strategy to remove
     */
    function removeStrategy(address strategy) external onlyManager {
        if (!_strategies.contains(strategy)) revert StrategyDoesNotExist();

        _strategies.remove(strategy);

        emit StrategyRemoved(strategy);
    }

    /**
     * @dev Executes a strategy with the given data
     * @param strategy The address of the strategy to execute
     * @param data The data to pass to the strategy
     */
    function executeStrategy(
        address strategy,
        bytes calldata data
    ) external onlyAgent nonReentrantVault whenVaultNotPaused {
        if (!_strategies.contains(strategy)) revert StrategyDoesNotExist();

        (bool success, ) = strategy.call(data);
        if (!success) revert ExecutionFailed();

        emit StrategyExecuted(strategy, data);
    }

    /**
     * @dev Deposits assets to a strategy and executes it
     * @param strategy The address of the strategy to deposit to
     * @param amount The amount of assets to deposit
     * @param data Additional data for the strategy execution
     */
    function depositToStrategy(
        address strategy,
        uint256 amount,
        bytes calldata data
    ) external onlyAgent nonReentrantVault whenVaultNotPaused {
        if (!_strategies.contains(strategy)) revert StrategyDoesNotExist();
        if (amount == 0) revert InvalidAddress(); // Reusing error for zero amount

        // Check vault has enough assets
        uint256 vaultBalance = IERC20(asset()).balanceOf(address(this));
        if (vaultBalance < amount) revert InsufficientBalance();

        // Approve strategy to spend vault's tokens (safe approval pattern)
        IERC20(asset()).safeIncreaseAllowance(strategy, amount);

        // Call strategy execute function
        IStrategies(strategy).execute(amount, data);

        // Reset allowance to zero for security (only if there's remaining allowance)
        uint256 remainingAllowance = IERC20(asset()).allowance(
            address(this),
            strategy
        );
        if (remainingAllowance > 0) {
            IERC20(asset()).safeDecreaseAllowance(strategy, remainingAllowance);
        }

        emit StrategyExecuted(strategy, data);
    }

    /**
     * @dev Harvests rewards from a strategy
     * @param strategy The address of the strategy to harvest from
     * @param data The data to pass to the strategy
     */
    function harvestStrategy(
        address strategy,
        bytes calldata data
    ) external onlyAgent nonReentrantVault whenVaultNotPaused {
        if (!_strategies.contains(strategy)) revert StrategyDoesNotExist();

        IStrategies(strategy).harvest(data);

        emit StrategyHarvested(strategy, data);
    }

    /**
     * @dev Performs an emergency exit from a strategy
     * @param strategy The address of the strategy to exit
     * @param data The data to pass to the strategy
     */
    function emergencyExitStrategy(
        address strategy,
        bytes calldata data
    ) external onlyAgent nonReentrantVault whenVaultNotPaused {
        if (!_strategies.contains(strategy)) revert StrategyDoesNotExist();

        IStrategies(strategy).emergencyExit(data);

        emit EmergencyExit(strategy, data);
    }

    // ============ View Functions ============
    /**
     * @dev Checks if an address is a registered strategy
     * @param strategy The address to check
     * @return bool Whether the address is a strategy
     */
    function isStrategy(address strategy) external view returns (bool) {
        return _strategies.contains(strategy);
    }

    /**
     * @dev Returns the number of registered strategies
     * @return uint256 The number of strategies
     */
    function getStrategiesCount() external view returns (uint256) {
        return _strategies.length();
    }

    /**
     * @dev Returns the strategy at the given index
     * @param index The index of the strategy
     * @return address The strategy address
     */
    function strategies(uint256 index) external view returns (address) {
        return _strategies.at(index);
    }

    /**
     * @dev Returns all strategy addresses
     * @return address[] Array of all strategy addresses
     */
    function getStrategies() external view returns (address[] memory) {
        uint256 length = _strategies.length();
        address[] memory strategiesArray = new address[](length);
        for (uint256 i = 0; i < length; i++) {
            strategiesArray[i] = _strategies.at(i);
        }
        return strategiesArray;
    }

    // ============ Abstract Functions ============
    /// @dev Returns the underlying asset address - must be implemented by inheriting contract
    function asset() public view virtual returns (address);
}
