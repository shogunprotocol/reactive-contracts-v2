// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity >=0.8.0;

import "@reactive/interfaces/IReactive.sol";
import "@reactive/abstract-base/AbstractReactive.sol";

/**
 * @title StrategyEmergencyExitReactiveFixed
 * @dev FIXED VERSION: Reactive contract that monitors Strategy contracts for EmergencyExited events
 *      and triggers Uniswap V4 swaps via SimpleSwap callback
 */
contract StrategyEmergencyExitReactiveFixed is IReactive, AbstractReactive {
    event Subscribed(
        address indexed service_address,
        address indexed _contract,
        uint256 indexed topic_0
    );

    event EmergencyExitDetected(
        uint256 indexed balance,
        bytes data,
        address indexed strategy
    );

    event CallbackSent(address indexed callback_contract, uint256 balance);
    event SwapCompleted();
    event Done();

    // NEW: Debug events
    event ReactCalled(address contractAddr, uint256 topic0);
    event BalanceCheck(uint256 balance, bool willTrigger);

    // Constantsel c el ep
    uint256 private constant CHAIN_ID = 1;
    uint256 private constant EMERGENCY_EXITED_TOPIC_0 =
        0x33707543538a74978cfbe255a9a187ce79ed7695a03a48d36b5a3cf8b569aa52; // keccak256("EmergencyExited(uint256,bytes)")
    uint64 private constant CALLBACK_GAS_LIMIT = 1000000;

    // State variables
    address private strategy;
    address private simpleSwap;
    address private client;
    address private owner;

    // NEW: Auto-register flag
    bool private autoRegistered;

    constructor(
        address _strategy,
        address _simpleSwap,
        address _client
    ) payable {
        strategy = _strategy;
        simpleSwap = _simpleSwap;
        client = _client;
        owner = msg.sender;
        autoRegistered = false;
    }

    /**
     * @dev React to EmergencyExited events from the Strategy contract
     * @param log The log record from the monitored event
     */
    function react(LogRecord calldata log) external vmOnly {
        emit ReactCalled(log._contract, log.topic_0);

        // Verify this is from our monitored strategy
        if (log._contract != strategy) {
            return;
        }

        // Verify this is the EmergencyExited event
        if (log.topic_0 != EMERGENCY_EXITED_TOPIC_0) {
            return;
        }

        // Decode the event data: EmergencyExited(uint256 balance, bytes data)
        (uint256 balance, bytes memory data) = abi.decode(
            log.data,
            (uint256, bytes)
        );

        emit EmergencyExitDetected(balance, data, strategy);

        // DEBUG: Log balance decision
        emit BalanceCheck(balance, true);

        // Use minimum balance of 1000 wei if balance is 0 (for testing)
        uint256 swapAmount = balance > 0 ? balance : 1000;

        // Create simple payload for emergency swap
        bytes memory payload = abi.encodeWithSignature(
            "emergencySwap(uint256,address,uint256)",
            swapAmount,
            client,
            (swapAmount * 95) / 100 // minimum amount (5% slippage tolerance)
        );

        emit CallbackSent(simpleSwap, swapAmount);

        // Send callback to SimpleSwap on Sepolia
        emit Callback(CHAIN_ID, simpleSwap, CALLBACK_GAS_LIMIT, payload);
    }

    /**
     * @dev Get the monitored strategy address
     */
    function getStrategy() external view returns (address) {
        return strategy;
    }

    /**
     * @dev Get the SimpleSwap callback address
     */
    function getSimpleSwap() external view returns (address) {
        return simpleSwap;
    }

    /**
     * @dev Get the client address
     */
    function getClient() external view returns (address) {
        return client;
    }

    /**
     * @dev Register the reactive contract (must be called by owner)
     */
    function register() external {
        require(msg.sender == owner, "Only owner");
        service.subscribe(
            CHAIN_ID,
            strategy,
            EMERGENCY_EXITED_TOPIC_0,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );
        autoRegistered = true;
        emit Subscribed(address(service), strategy, EMERGENCY_EXITED_TOPIC_0);
    }

    /**
     * @dev Auto-register on first call (convenience function)
     */
    function autoRegister() external {
        require(msg.sender == owner, "Only owner");
        if (!autoRegistered) {
            service.subscribe(
                CHAIN_ID,
                strategy,
                EMERGENCY_EXITED_TOPIC_0,
                REACTIVE_IGNORE,
                REACTIVE_IGNORE,
                REACTIVE_IGNORE
            );
            autoRegistered = true;
            emit Subscribed(
                address(service),
                strategy,
                EMERGENCY_EXITED_TOPIC_0
            );
        }
    }

    /**
     * @dev Get the owner address
     */
    function getOwner() external view returns (address) {
        return owner;
    }

    /**
     * @dev Check if auto-registered
     */
    function isRegistered() external view returns (bool) {
        return autoRegistered;
    }
}
