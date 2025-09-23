# Reactive Hook System for Uniswap V4 Liquidity

## System Overview

This system implements a reactive hook that monitors large liquidity movements in a Uniswap V4 pool and automatically triggers an emergency function (autoEmergencyExit) when significant changes are detected.

## System Architecture

### 1. LiquidityChange Hook (Uniswap V4)

- **Function**: Monitors liquidity additions/removals in real-time
- **Threshold**: `1000` (very low to facilitate testing)
- **Event**: Emits `LargeLiquidityChange` when liquidity exceeds threshold

### 2. LiquidityChangeReactive (Reactive Network)

- **Function**: Listens to hook events and executes automatic callbacks
- **Action**: Calls `autoEmergencyExit()` on the strategy contract
- **Cross-chain**: Operates between Ethereum Mainnet (hook) and Reactive Mainnet

## Deployed Contract Addresses

### Ethereum Mainnet (Chain ID: 1)

#### Uniswap V4 Infrastructure

- **Pool Manager**: [`0x000000000004444c5dc75cB358380D2e3dE08A90`](https://etherscan.io/address/0x000000000004444c5dc75cB358380D2e3dE08A90)
- **Position Manager**: [`0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e`](https://etherscan.io/address/0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e)

#### Deployed Hook

- **LiquidityChange Hook**: [`0xcf8518c0ee072a5a2ef8de0585030086c89c4ac0`](https://etherscan.io/address/0xcf8518c0ee072a5a2ef8de0585030086c89c4ac0)
  - Threshold: `1000`
  - Monitors: `beforeAddLiquidity` and `beforeRemoveLiquidity`
  - Emits: `LargeLiquidityChange(bytes32 poolId, uint256 liquidityAmount, bool isAdd)`

#### Pool Configuration

- **Tick Spacing**: `60`
- **Hook Address**: [`0xcf8518c0ee072a5a2ef8de0585030086c89c4ac0`](https://etherscan.io/address/0xcf8518c0ee072a5a2ef8de0585030086c89c4ac0)

### Reactive Mainnet (Chain ID: 5318008)

#### Reactive Contract

- **LiquidityChangeReactive**: [`0x6428fbef03c165f7f6b918364dd824d8ee1fd242`](https://reactscan.net/address/0x7C65F77a4EbEa3D56368A73A12234bB4384ACB28)

  - Hook contract(see events): [`0xcf8518c0ee072a5a2ef8de0585030086c89c4ac0`](https://etherscan.io/address/0x52c73a3EDC6E3D82ED675533144fd28886DccAC0)

  - Balance: 1 ETH

## System Flow

### 1. Large Liquidity Detection

```solidity
// In LiquidityChange.sol
function _beforeAddLiquidity(...) internal override returns (bytes4) {
    if (params.liquidityDelta >= int256(LARGE_LIQUIDITY_THRESHOLD)) {
        emit LargeLiquidityChange(
            PoolId.unwrap(key.toId()),
            uint256(params.liquidityDelta),
            true // isAdd = true
        );
    }
}
```

### 2. Automatic Reaction

```solidity
// In LiquidityChangeReactive.sol
function react(LogRecord calldata log) external vmOnly {
    // Verify it's from the correct pool
    if (log._contract != pool) return;

    // Verify it's the correct event
    if (log.topic_0 != LARGE_LIQUIDITY_CHANGE_TOPIC_0) return;

    // Execute automatic callback
    bytes memory payload = abi.encodeWithSignature("autoEmergencyExit()");
    emit Callback(CHAIN_ID, strategy, CALLBACK_GAS_LIMIT, payload);
}
```

### 3. Emergency Execution

The system automatically calls `autoEmergencyExit()` on the strategy contract when:

- Added/removed liquidity exceeds `1000`
- Event comes from the correct hook
- Reactive contract is registered

## Configuration and Testing

### Key Parameters

- **Liquidity Threshold**: `1000` (very low for testing)
- **Topic Hash**: `0xe4f4dfad1e4128943809bc23077ed765f12b98ec17ea4a5adc9657cc762d319c`
- **Token Parity**: 1:1 (adjusted for decimals)

### Testing Amounts

- **Pool Creation**: 10 tokens each (`10e6` EURC, `10e18` TK2)
- **Add Liquidity**: 10 tokens each (`10e18` EURC, `10e18` TK2)

## Deployment Scripts

### 1. Deploy Hook and Pool

```bash
forge script script/CreatePoolWithLiquidityChangeHook.s.sol:CreatePoolWithLiquidityChangeHook \
  --rpc-url mainnet \
  --broadcast \
  --private-key $PRIVATE_KEY
```

### 2. Deploy Reactive Contract

```bash
POOL_ADDRESS=0xcf8518c0ee072a5a2ef8de0585030086c89c4ac0 \
STRATEGY_ADDRESS=0xACF69128c3577c9C154E4D46A8B7C2576C230e2C \
forge script script/DeployLiquidityChangeReactive.s.sol:DeployLiquidityChangeReactive \
  --rpc-url https://reactive-rpc.rnk.dev \
  --broadcast \
  --private-key $PRIVATE_KEY
```

### 3. Register Reactive Contract

```bash
LIQUIDITY_REACTIVE_ADDRESS=0x6428fbef03c165f7f6b918364dd824d8ee1fd242 \
forge script script/RegisterLiquidityChangeReactive.s.sol:RegisterLiquidityChangeReactive \
  --rpc-url https://reactive-rpc.rnk.dev \
  --broadcast \
  --private-key $PRIVATE_KEY
```

### 4. Test with Liquidity

```bash
HOOK_ADDRESS=0xcf8518c0ee072a5a2ef8de0585030086c89c4ac0 \
forge script script/AddLargeLiquidity.s.sol:AddLargeLiquidityScript \
  --rpc-url mainnet \
  --broadcast \
  --private-key $PRIVATE_KEY
```

## Monitoring and Verification

### Verify Hook Status

```bash
# Check threshold
cast call 0xcf8518c0ee072a5a2ef8de0585030086c89c4ac0 "LARGE_LIQUIDITY_THRESHOLD()" --rpc-url mainnet

# View emitted events
cast logs 0xcf8518c0ee072a5a2ef8de0585030086c89c4ac0 --rpc-url mainnet --from-block latest
```

### Verify Reactive Status

```bash
# Check if registered
cast call 0x6428fbef03c165f7f6b918364dd824d8ee1fd242 "isRegistered()" --rpc-url https://reactive-rpc.rnk.dev

# View reactive events
cast logs 0x6428fbef03c165f7f6b918364dd824d8ee1fd242 --rpc-url https://reactive-rpc.rnk.dev --from-block latest
```

## Use Cases

### Scenario 1: Protection Against Dumps

- User adds/removes > 1000 liquidity units
- Hook automatically detects the movement
- Reactive system executes `autoEmergencyExit()`
- Strategy protects itself automatically

### Scenario 2: Whale Monitoring

- Whales make large liquidity movements
- System reacts instantly
- Executes automatic protection measures

## Customization

### Adjust Threshold

```solidity
// In LiquidityChange.sol
uint256 public constant LARGE_LIQUIDITY_THRESHOLD = 1000; // Change this value
```

### Change Emergency Action

```solidity
// In LiquidityChangeReactive.sol
bytes memory payload = abi.encodeWithSignature("autoEmergencyExit()"); // Change function
```

## System Metrics

- **Current Threshold**: `1000`
- **Reaction Time**: ~1-2 blocks
- **Callback Gas Limit**: `1,000,000`
- **Reactive Funding**: 1 ETH
- **Status**: Active and Monitoring

## Important Notes

1. **Low Threshold**: Set to `1000` to facilitate testing
2. **1:1 Parity**: Tokens maintain 1:1 parity adjusted for decimals
3. **Cross-Chain**: Operates between Ethereum Mainnet and Reactive Mainnet
4. **Automation**: No manual intervention required once configured
5. **Continuous Monitoring**: Works 24/7 while registered

## Block Explorers

### Ethereum Mainnet

- **Hook Contract see events**: https://etherscan.io/address/0x52c73a3EDC6E3D82ED675533144fd28886DccAC0

- **LiquidityChangeReactive**: [`0x6428fbef03c165f7f6b918364dd824d8ee1fd242`](https://reactscan.net/address/0x7C65F77a4EbEa3D56368A73A12234bB4384ACB28)

### Reactive Mainnet

---

**System created for automatic protection against large liquidity movements in Uniswap V4**
