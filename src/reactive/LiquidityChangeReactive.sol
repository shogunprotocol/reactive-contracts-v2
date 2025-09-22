// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity >=0.8.0;

import "@reactive/interfaces/IReactive.sol";
import "@reactive/abstract-base/AbstractReactive.sol";

contract LiquidityChangeReactive is IReactive, AbstractReactive {
    event Subscribed(
        address indexed service_address,
        address indexed _contract,
        uint256 indexed topic_0
    );

    event LargeLiquidityChange(
        bytes32 indexed poolId,
        uint256 liquidityAmount,
        bool isAdd
    );
    event Done();

    // NEW: Debug events
    event ReactCalled(address contractAddr, uint256 topic0);
    event CallbackSent(address indexed callback_contract, uint256 balance);
    // Constantsel c el ep
    uint256 private constant CHAIN_ID = 1;
    uint256 private constant LARGE_LIQUIDITY_CHANGE_TOPIC_0 =
        0xe4f4dfad1e4128943809bc23077ed765f12b98ec17ea4a5adc9657cc762d319c; // keccak256("LargeLiquidityChange(bytes32,uint256,bool)")
    uint64 private constant CALLBACK_GAS_LIMIT = 1000000;

    // State variables
    address private pool;
    address private strategy;
    address private client;
    address private owner;

    // NEW: Auto-register flag
    bool private autoRegistered;

    constructor(address _pool, address _strategy, address _client) payable {
        pool = _pool;
        strategy = _strategy;
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

        if (log._contract != pool) {
            return;
        }

        // Verify this is the EmergencyExited event
        if (log.topic_0 != LARGE_LIQUIDITY_CHANGE_TOPIC_0) {
            return;
        }

        bytes memory payload = abi.encodeWithSignature("autoEmergencyExit()");

        emit CallbackSent(strategy, 0);

        // Send callback to SimpleSwap on Sepolia
        emit Callback(CHAIN_ID, strategy, CALLBACK_GAS_LIMIT, payload);
    }

    /**
     * @dev Get the monitored strategy address
     */
    function getPool() external view returns (address) {
        return pool;
    }

    /**
     * @dev Get the SimpleSwap callback address
     */
    function getStrategy() external view returns (address) {
        return strategy;
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
            LARGE_LIQUIDITY_CHANGE_TOPIC_0,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );
        autoRegistered = true;
        emit Subscribed(
            address(service),
            strategy,
            LARGE_LIQUIDITY_CHANGE_TOPIC_0
        );
    }

    /**
     * @dev Auto-register on first call (convenience function)
     */
    function autoRegister() external {
        require(msg.sender == owner, "Only owner");
        if (!autoRegistered) {
            service.subscribe(
                CHAIN_ID,
                pool,
                LARGE_LIQUIDITY_CHANGE_TOPIC_0,
                REACTIVE_IGNORE,
                REACTIVE_IGNORE,
                REACTIVE_IGNORE
            );
            autoRegistered = true;
            emit Subscribed(
                address(service),
                pool,
                LARGE_LIQUIDITY_CHANGE_TOPIC_0
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
