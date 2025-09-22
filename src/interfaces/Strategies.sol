// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

/**
 * @title IStrategies
 * @dev Interface for the Strategies contract that defines the core functionality for protocol interactions
 * @notice This interface provides the standard methods for interacting with various DeFi protocols
 * @custom:security-contact security@vaults.com
 */
interface IStrategies {
    // ============ Events ============
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

    // ============ Errors ============
    error NoVaultSet();
    error StrategyPaused();
    error DepositFailed(bytes reason);
    error WithdrawFailed(bytes reason);
    error ClaimFailed(bytes reason);
    error GetBalanceFailed(bytes reason);
    error NoUnderlyingBalance();
    error InvalidTokenAddress();
    error InvalidAmount();

    // ============ View Functions ============
    /**
     * @dev Returns the address of the underlying token
     * @return address The underlying token address
     */
    function underlyingToken() external view returns (address);

    /**
     * @dev Returns the address of the protocol
     * @return address The protocol address
     */
    function protocol() external view returns (address);

    /**
     * @dev Returns the deposit function selector
     * @return bytes4 The deposit function selector
     */
    function depositSelector() external view returns (bytes4);

    /**
     * @dev Returns the withdraw function selector
     * @return bytes4 The withdraw function selector
     */
    function withdrawSelector() external view returns (bytes4);

    /**
     * @dev Returns the claim function selector
     * @return bytes4 The claim function selector
     */
    function claimSelector() external view returns (bytes4);

    /**
     * @dev Returns the getBalance function selector
     * @return bytes4 The getBalance function selector
     */
    function getBalanceSelector() external view returns (bytes4);

    /**
     * @dev Returns the vault address
     * @return address The vault address
     */
    function vault() external view returns (address);

    /**
     * @dev Returns the paused state
     * @return bool The paused state
     */
    function paused() external view returns (bool);

    /**
     * @dev Returns whether a token is a known reward token
     * @param token The token address to check
     * @return bool Whether the token is a known reward token
     */
    function knownRewardTokens(address token) external view returns (bool);

    /**
     * @dev Returns the list of reward tokens
     * @return address[] The list of reward tokens
     */
    function rewardTokensList() external view returns (address[] memory);

    /**
     * @dev Gets the current balance of the strategy in the protocol
     * @return uint256 Balance of the strategy
     */
    function getBalance() external view returns (uint256);

    /**
     * @dev Query the protocol with custom parameters (read-only)
     * @param selector Function selector to call on the protocol
     * @param params Encoded parameters for the function call
     * @return bytes Raw response data from the protocol
     */
    function queryProtocol(
        bytes4 selector,
        bytes calldata params
    ) external view returns (bytes memory);

    // ============ State-Changing Functions ============
    /**
     * @dev Sets the vault address
     * @param _vault Address of the vault
     */
    function setVault(address _vault) external;

    /**
     * @dev Add a known reward token to track
     * @param tokenAddress Address of the reward token
     */
    function addRewardToken(address tokenAddress) external;

    /**
     * @dev Executes the strategy by depositing tokens into the protocol
     * @param amount Amount of tokens to deposit
     * @param data Additional data needed for the deposit
     */
    function execute(uint256 amount, bytes calldata data) external;

    /**
     * @dev Harvests rewards from the protocol
     * @param data Additional data needed for harvesting
     */
    function harvest(bytes calldata data) external;

    /**
     * @dev Performs an emergency exit, withdrawing all funds from the protocol
     * @param data Additional data needed for emergency exit
     */
    function emergencyExit(bytes calldata data) external;

    /**
     * @dev Claims rewards from the protocol
     * @param data Additional data needed for claiming rewards
     */
    function claimRewards(bytes calldata data) external;

    /**
     * @dev Sets the pause state
     * @param _paused New pause state
     */
    function setPaused(bool _paused) external;
}
