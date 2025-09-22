// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/**
 * @title IVault
 * @dev Interface for the Vault contract that implements ERC4626 vault functionality
 * @notice This interface provides the standard methods for managing assets and strategies
 * @custom:security-contact security@vaults.com
 */
interface IVault is IERC20, IERC20Metadata {
    // ============ Events ============
    event StrategyAdded(address indexed strategy);
    event StrategyRemoved(address indexed strategy);
    event StrategyExecuted(address indexed strategy, bytes data);

    // ============ Errors ============
    error InvalidStrategy();
    error StrategyAlreadyExists();
    error StrategyDoesNotExist();
    error ExecutionFailed();
    error InvalidAddress();

    // ============ View Functions ============
    /**
     * @dev Returns the underlying asset of the vault
     * @return address The underlying asset address
     */
    function asset() external view returns (address);

    /**
     * @dev Returns the total assets managed by the vault
     * @return uint256 The total assets
     */
    function totalAssets() external view returns (uint256);

    /**
     * @dev Returns the list of strategies
     * @return address[] The list of strategies
     */
    function strategies() external view returns (address[] memory);

    /**
     * @dev Returns whether an address is a strategy
     * @param strategy The address to check
     * @return bool Whether the address is a strategy
     */
    function isStrategy(address strategy) external view returns (bool);

    /**
     * @dev Returns whether an address has the manager role
     * @param account The address to check
     * @return bool Whether the address has the manager role
     */
    function hasManagerRole(address account) external view returns (bool);

    /**
     * @dev Returns whether an address has the agent role
     * @param account The address to check
     * @return bool Whether the address has the agent role
     */
    function hasAgentRole(address account) external view returns (bool);

    // ============ State-Changing Functions ============
    /**
     * @dev Adds a new strategy to the vault
     * @param strategy The address of the strategy to add
     */
    function addStrategy(address strategy) external;

    /**
     * @dev Removes a strategy from the vault
     * @param strategy The address of the strategy to remove
     */
    function removeStrategy(address strategy) external;

    /**
     * @dev Executes a strategy with the given data
     * @param strategy The address of the strategy to execute
     * @param data The data to pass to the strategy
     */
    function executeStrategy(address strategy, bytes calldata data) external;

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
    ) external;

    /**
     * @dev Deposits assets into the vault
     * @param assets The amount of assets to deposit
     * @param receiver The address to receive the shares
     * @return uint256 The amount of shares minted
     */
    function deposit(
        uint256 assets,
        address receiver
    ) external returns (uint256);

    /**
     * @dev Mints shares for the receiver
     * @param shares The amount of shares to mint
     * @param receiver The address to receive the shares
     * @return uint256 The amount of assets deposited
     */
    function mint(uint256 shares, address receiver) external returns (uint256);

    /**
     * @dev Withdraws assets from the vault
     * @param assets The amount of assets to withdraw
     * @param receiver The address to receive the assets
     * @param owner The address that owns the shares
     * @return uint256 The amount of shares burned
     */
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) external returns (uint256);

    /**
     * @dev Redeems shares for assets
     * @param shares The amount of shares to redeem
     * @param receiver The address to receive the assets
     * @param owner The address that owns the shares
     * @return uint256 The amount of assets withdrawn
     */
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) external returns (uint256);
}
