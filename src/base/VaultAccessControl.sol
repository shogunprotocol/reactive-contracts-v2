// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @title VaultAccessControl
/// @notice Handles all role-based access control for the vault
/// @dev Provides role management and access control functionality
contract VaultAccessControl is AccessControl, Ownable {
    // ============ Role Constants ============
    /// @notice Role identifier for vault managers
    /// @dev Used in AccessControl for manager permissions
    bytes32 public constant MANAGER_ROLE = keccak256("VAULT_MANAGER_ROLE");

    /// @notice Role identifier for vault agents
    /// @dev Used in AccessControl for agent permissions
    bytes32 public constant AGENT_ROLE = keccak256("VAULT_AGENT_ROLE");

    /// @notice Role identifier for vault pausers
    /// @dev Used in AccessControl for emergency pause permissions
    bytes32 public constant PAUSER_ROLE = keccak256("VAULT_PAUSER_ROLE");

    // ============ Constructor ============
    /// @notice Initializes the access control with owner and initial roles
    /// @param _owner The owner of the vault
    /// @param manager The initial manager address
    /// @param agent The initial agent address
    constructor(
        address _owner,
        address manager,
        address agent
    ) Ownable(msg.sender) {
        require(_owner != address(0), "Owner cannot be zero address");
        require(manager != address(0), "Manager cannot be zero address");
        require(agent != address(0), "Agent cannot be zero address");

        _transferOwnership(_owner);
        _grantRole(DEFAULT_ADMIN_ROLE, _owner);
        _grantRole(MANAGER_ROLE, manager);
        _grantRole(AGENT_ROLE, agent);
        _grantRole(PAUSER_ROLE, _owner); // Owner can pause by default
    }

    // ============ Modifiers ============
    /// @notice Restricts function access to addresses with MANAGER_ROLE
    /// @dev Reverts if caller doesn't have MANAGER_ROLE
    modifier onlyManager() virtual {
        require(
            hasRole(MANAGER_ROLE, msg.sender),
            "Vault: caller is not a manager"
        );
        _;
    }

    /// @notice Restricts function access to addresses with AGENT_ROLE
    /// @dev Reverts if caller doesn't have AGENT_ROLE
    modifier onlyAgent() virtual {
        require(
            hasRole(AGENT_ROLE, msg.sender),
            "Vault: caller is not an agent"
        );
        _;
    }

    /// @notice Restricts function access to addresses with PAUSER_ROLE
    /// @dev Reverts if caller doesn't have PAUSER_ROLE
    modifier onlyPauser() virtual {
        require(
            hasRole(PAUSER_ROLE, msg.sender),
            "Vault: caller is not a pauser"
        );
        _;
    }

    // ============ View Functions ============
    /// @dev Returns whether an address has the manager role
    /// @param account The address to check
    /// @return bool Whether the address has the manager role
    function hasManagerRole(address account) external view returns (bool) {
        return hasRole(MANAGER_ROLE, account);
    }

    /// @dev Returns whether an address has the agent role
    /// @param account The address to check
    /// @return bool Whether the address has the agent role
    function hasAgentRole(address account) external view returns (bool) {
        return hasRole(AGENT_ROLE, account);
    }

    /// @dev Returns whether an address has the pauser role
    /// @param account The address to check
    /// @return bool Whether the address has the pauser role
    function hasPauserRole(address account) external view returns (bool) {
        return hasRole(PAUSER_ROLE, account);
    }
}
