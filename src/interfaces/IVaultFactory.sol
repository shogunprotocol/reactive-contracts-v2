// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title IVaultFactory Interface
/// @notice Interface for the VaultFactory contract
/// @dev Defines the core functionality for vault creation and management
interface IVaultFactory {
    // ============ Structs ============

    /// @notice Struct containing vault creation parameters
    struct VaultParams {
        IERC20 asset;
        string name;
        string symbol;
        address manager;
        address agent;
    }

    /// @notice Struct containing vault information
    struct VaultInfo {
        uint256 id;
        address vaultAddress;
        address asset;
        string name;
        string symbol;
        address manager;
        address agent;
        uint256 createdAt;
        address creator;
    }

    // ============ Events ============

    event VaultCreated(
        uint256 indexed vaultId,
        address indexed vaultAddress,
        address indexed asset,
        string name,
        string symbol,
        address manager,
        address agent,
        address creator
    );

    event DefaultManagerUpdated(
        address indexed oldManager,
        address indexed newManager
    );
    event DefaultAgentUpdated(
        address indexed oldAgent,
        address indexed newAgent
    );
    event CreationFeeUpdated(uint256 oldFee, uint256 newFee);
    event TreasuryUpdated(
        address indexed oldTreasury,
        address indexed newTreasury
    );
    event FeesWithdrawn(address indexed to, uint256 amount);

    // ============ Errors ============

    error InvalidAsset();
    error InvalidManager();
    error InvalidAgent();
    error InvalidTreasury();
    error EmptyName();
    error EmptySymbol();
    error InsufficientFee();
    error VaultNotFromFactory();
    error WithdrawalFailed();

    // ============ External Functions ============

    /// @notice Creates a new vault with specified parameters
    /// @param params Vault creation parameters
    /// @return vaultAddress Address of the created vault
    /// @return vaultId ID of the created vault
    function createVault(
        VaultParams calldata params
    ) external payable returns (address vaultAddress, uint256 vaultId);

    /// @notice Creates a vault with default manager and agent
    /// @param asset The underlying asset for the vault
    /// @param name Name of the vault token
    /// @param symbol Symbol of the vault token
    /// @return vaultAddress Address of the created vault
    /// @return vaultId ID of the created vault
    function createVaultWithDefaults(
        IERC20 asset,
        string calldata name,
        string calldata symbol
    ) external payable returns (address vaultAddress, uint256 vaultId);

    // ============ Admin Functions ============

    /// @notice Updates the default manager address
    /// @param _newDefaultManager New default manager address
    function setDefaultManager(address _newDefaultManager) external;

    /// @notice Updates the default agent address
    /// @param _newDefaultAgent New default agent address
    function setDefaultAgent(address _newDefaultAgent) external;

    /// @notice Updates the creation fee
    /// @param _newCreationFee New creation fee amount
    function setCreationFee(uint256 _newCreationFee) external;

    /// @notice Updates the treasury address
    /// @param _newTreasury New treasury address
    function setTreasury(address _newTreasury) external;

    /// @notice Withdraws accumulated fees to treasury
    function withdrawFees() external;

    // ============ View Functions ============

    /// @notice Returns the total number of vaults created
    /// @return count Total vault count
    function getVaultCount() external view returns (uint256 count);

    /// @notice Returns all vault addresses
    /// @return vaultAddresses Array of all vault addresses
    function getAllVaults()
        external
        view
        returns (address[] memory vaultAddresses);

    /// @notice Returns vault addresses for a specific asset
    /// @param asset Asset address
    /// @return vaultAddresses Array of vault addresses for the asset
    function getVaultsForAsset(
        address asset
    ) external view returns (address[] memory vaultAddresses);

    /// @notice Returns detailed information about a vault
    /// @param vaultId ID of the vault
    /// @return info Vault information struct
    function getVaultInfo(
        uint256 vaultId
    ) external view returns (VaultInfo memory info);

    /// @notice Returns vault information by vault address
    /// @param vaultAddress Address of the vault
    /// @return info Vault information struct
    function getVaultInfoByAddress(
        address vaultAddress
    ) external view returns (VaultInfo memory info);

    /// @notice Checks if a vault address was created by this factory
    /// @param vaultAddress Address to check
    /// @return isFromFactory True if vault was created by this factory
    function isVaultCreatedByFactory(
        address vaultAddress
    ) external view returns (bool isFromFactory);

    // ============ State Variable Getters ============

    /// @notice Returns the vault counter
    /// @return count Current vault counter
    function vaultCounter() external view returns (uint256 count);

    /// @notice Returns vault address by ID
    /// @param vaultId Vault ID
    /// @return vaultAddress Address of the vault
    function vaults(
        uint256 vaultId
    ) external view returns (address vaultAddress);

    /// @notice Returns vault ID by address
    /// @param vaultAddress Vault address
    /// @return vaultId ID of the vault
    function vaultIds(
        address vaultAddress
    ) external view returns (uint256 vaultId);

    /// @notice Returns the default manager address
    /// @return manager Default manager address
    function defaultManager() external view returns (address manager);

    /// @notice Returns the default agent address
    /// @return agent Default agent address
    function defaultAgent() external view returns (address agent);

    /// @notice Returns the creation fee
    /// @return fee Creation fee in wei
    function creationFee() external view returns (uint256 fee);

    /// @notice Returns the treasury address
    /// @return treasury Treasury address
    function treasury() external view returns (address treasury);
}
