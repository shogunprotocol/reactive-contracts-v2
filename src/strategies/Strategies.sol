// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "../../lib/reactive-lib/src/abstract-base/AbstractCallback.sol";

/**
 * @title GenericStrategyImplementation
 * @dev Implementation of the IStrategy interface that can interact with any protocol via function selectors
 * @notice This is a completely generic implementation that can be reused for any protocol
 * @custom:security-contact security@vaults.com
 */
contract Strategies is ReentrancyGuard, AbstractCallback {
    using SafeERC20 for IERC20;

    // State variables - immutable for gas optimization
    address public immutable underlyingToken;
    address public immutable protocol;
    bytes4 public immutable depositSelector;
    bytes4 public immutable withdrawSelector;
    bytes4 public immutable claimSelector;
    bytes4 public immutable getBalanceSelector;

    // Mutable state
    address public vault;
    bool public paused;

    // Optional secondary token mappings for rewards
    mapping(address => bool) public knownRewardTokens;
    address[] public rewardTokensList;

    // Events
    event Deposit(uint256 amount);
    event Withdraw(uint256 amount);
    event Claim(uint256 amount);
    event VaultSet(address vault);
    event PausedState(bool isPaused);
    event Executed(uint256 amount, bytes data);
    event Harvested(bytes data);
    event EmergencyExited(uint256 balance, bytes data);
    event RewardTokenAdded(address indexed token);
    event TokensForwarded(address indexed token, uint256 amount);
    event ClaimRewardsFailed(bytes reason);

    // Errors
    error NoVaultSet();
    error StrategyPaused();
    error DepositFailed(bytes reason);
    error WithdrawFailed(bytes reason);
    error ClaimFailed(bytes reason);
    error GetBalanceFailed(bytes reason);
    error NoUnderlyingBalance();
    error InvalidTokenAddress();
    error InvalidAmount();

    // Modifiers
    modifier onlyAgent() {
        if (vault == address(0)) revert NoVaultSet();
        if (msg.sender != vault) {
            revert("Only agent can call");
        }
        _;
    }

    modifier whenNotPaused() {
        if (paused) revert StrategyPaused();
        _;
    }

    /**
     * @dev Constructor for initializing the strategy
     * @param _underlyingToken Address of the underlying token
     * @param _protocol Address of the protocol
     * @param _depositSelector Function selector for deposit
     * @param _withdrawSelector Function selector for withdraw
     * @param _claimSelector Function selector for claim
     * @param _getBalanceSelector Function selector for getBalance
     */
    constructor(
        address _underlyingToken,
        address _protocol,
        bytes4 _depositSelector,
        bytes4 _withdrawSelector,
        bytes4 _claimSelector,
        bytes4 _getBalanceSelector,
        address _callback_sender
    ) AbstractCallback(_callback_sender) {
        require(_underlyingToken != address(0), "Invalid token address");
        require(_protocol != address(0), "Invalid protocol address");

        underlyingToken = _underlyingToken;
        protocol = _protocol;
        depositSelector = _depositSelector;
        withdrawSelector = _withdrawSelector;
        claimSelector = _claimSelector;
        getBalanceSelector = _getBalanceSelector;
    }

    /**
     * @dev Sets the vault address
     * @param _vault Address of the vault
     * @notice This can only be set once for security reasons
     */
    function setVault(address _vault) external {
        require(_vault != address(0), "Invalid vault address");
        require(vault == address(0), "Vault already set");
        vault = _vault;
        emit VaultSet(_vault);
    }

    /**
     * @dev Add a known reward token to track
     * @param tokenAddress Address of the reward token
     * @notice This helps the strategy automatically track and forward reward tokens
     */
    function addRewardToken(address tokenAddress) external onlyAgent {
        require(tokenAddress != address(0), "Invalid token address");
        require(!knownRewardTokens[tokenAddress], "Token already added");

        knownRewardTokens[tokenAddress] = true;
        rewardTokensList.push(tokenAddress);
        emit RewardTokenAdded(tokenAddress);
    }

    /**
     * @dev Executes the strategy by depositing tokens into the protocol
     * @param amount Amount of tokens to deposit
     * @param data Additional data needed for the deposit
     * @notice This function handles the transfer of tokens and interaction with the protocol
     */
    function execute(
        uint256 amount,
        bytes calldata data
    ) external onlyAgent nonReentrant whenNotPaused {
        if (amount == 0) revert InvalidAmount();

        // Handle the token transfer first
        IERC20(underlyingToken).safeTransferFrom(vault, address(this), amount);

        // Approve protocol to spend tokens
        uint256 currentAllowance = IERC20(underlyingToken).allowance(
            address(this),
            protocol
        );
        if (currentAllowance < amount) {
            if (currentAllowance > 0) {
                IERC20(underlyingToken).approve(protocol, 0);
            }
            IERC20(underlyingToken).approve(protocol, amount);
        }

        // Use provided data or build default calldata
        bytes memory callData;
        if (data.length > 0) {
            callData = data;
        } else {
            // Default: just use the selector with amount
            callData = abi.encodeWithSelector(depositSelector, amount);
        }

        // Execute the deposit
        (bool success, bytes memory result) = protocol.call(callData);

        if (!success) {
            // Revoke approval for security
            IERC20(underlyingToken).approve(protocol, 0);

            bytes memory revertReason;
            if (result.length > 0) {
                assembly {
                    revertReason := add(result, 0x20)
                }
            }
            revert DepositFailed(revertReason);
        }

        // Forward any reward tokens that might have been received
        _forwardRewardTokens();

        emit Deposit(amount);
        emit Executed(amount, data);
    }

    /**
     * @dev Harvests rewards from the protocol
     * @param data Additional data needed for harvesting
     */
    function harvest(bytes calldata data) external onlyAgent nonReentrant {
        claimRewards(data);
        emit Harvested(data);
    }

    /**
     * @dev Gets the current balance of the strategy in the protocol
     * @return uint256 Balance of the strategy
     * @notice This function retrieves the protocol balance using the provided selector
     */
    function getBalance() public view returns (uint256) {
        if (protocol == address(0) || underlyingToken == address(0)) {
            return 0;
        }

        // Try with address parameter first (most common)
        (bool success, bytes memory result) = protocol.staticcall(
            abi.encodeWithSelector(getBalanceSelector, address(this))
        );

        if (success && result.length >= 32) {
            return abi.decode(result, (uint256));
        }

        // Try without parameters
        (success, result) = protocol.staticcall(
            abi.encodeWithSelector(getBalanceSelector)
        );

        if (success && result.length >= 32) {
            return abi.decode(result, (uint256));
        }

        // Try with token and address parameters
        (success, result) = protocol.staticcall(
            abi.encodeWithSelector(
                getBalanceSelector,
                underlyingToken,
                address(this)
            )
        );

        if (success && result.length >= 32) {
            return abi.decode(result, (uint256));
        }

        return 0;
    }

    // /**
    //  * @dev Performs an emergency exit, withdrawing all funds from the protocol
    //  * @param data Additional data needed for emergency exit
    //  */
    function emergencyExit(
        bytes calldata data
    ) external onlyAgent nonReentrant {
        uint256 balance = getBalance();

        if (balance == 0) {
            revert NoUnderlyingBalance();
        }

        // Use provided data or build default calldata
        bytes memory callData;
        if (data.length > 0) {
            callData = data;
        } else {
            callData = abi.encodeWithSelector(withdrawSelector, balance);
        }

        // Execute the withdraw
        (bool success, bytes memory result) = protocol.call(callData);

        if (!success) {
            bytes memory revertReason;
            if (result.length > 0) {
                assembly {
                    revertReason := add(result, 0x20)
                }
            }
            revert WithdrawFailed(revertReason);
        }

        // Transfer tokens to the vault
        uint256 tokenBalance = IERC20(underlyingToken).balanceOf(address(this));
        if (tokenBalance > 0) {
            IERC20(underlyingToken).safeTransfer(vault, tokenBalance);
        }

        emit Withdraw(tokenBalance);
        emit EmergencyExited(tokenBalance, data);
    }

    /**
     * @dev Performs an emergency exit, withdrawing all funds from the protocol
     */
    function autoEmergencyExit() external authorizedSenderOnly nonReentrant {
        uint256 balance = getBalance();

        if (balance == 0) {
            revert NoUnderlyingBalance();
        }

        // Transfer tokens to the vault
        uint256 tokenBalance = IERC20(underlyingToken).balanceOf(address(this));
        if (tokenBalance > 0) {
            IERC20(underlyingToken).safeTransfer(vault, tokenBalance);
        }

        emit Withdraw(tokenBalance);
        emit EmergencyExited(tokenBalance, "");
    }

    /**
     * @dev Claims rewards from the protocol
     * @param data Additional data needed for claiming rewards
     */
    function claimRewards(bytes calldata data) public onlyAgent {
        // Skip if claimSelector is not set
        if (claimSelector == bytes4(0)) {
            return;
        }

        // Use provided data or build default calldata
        bytes memory callData;
        if (data.length > 0) {
            callData = data;
        } else {
            // Default: just use the selector
            callData = abi.encodeWithSelector(claimSelector);
        }

        // Execute the claim
        (bool success, bytes memory result) = protocol.call(callData);

        if (!success) {
            bytes memory revertReason;
            if (result.length > 0) {
                assembly {
                    revertReason := add(result, 0x20)
                }
            }
            emit ClaimRewardsFailed(revertReason);
            return;
        }

        // Forward reward tokens
        _forwardRewardTokens();

        emit Claim(0);
    }

    /**
     * @dev Forward all known reward tokens to the vault
     * @notice Gas optimized by avoiding unnecessary operations
     */
    function _forwardRewardTokens() internal {
        uint256 tokenCount = rewardTokensList.length;

        // Limit to avoid gas issues
        uint256 maxTokens = tokenCount > 10 ? 10 : tokenCount;

        for (uint256 i = 0; i < maxTokens; i++) {
            address tokenAddress = rewardTokensList[i];
            uint256 balance = IERC20(tokenAddress).balanceOf(address(this));
            if (balance > 0) {
                IERC20(tokenAddress).safeTransfer(vault, balance);
                emit TokensForwarded(tokenAddress, balance);
            }
        }
    }

    /**
     * @dev Sets the pause state
     * @param _paused New pause state
     */
    function setPaused(bool _paused) external onlyAgent {
        paused = _paused;
        emit PausedState(_paused);
    }
}
