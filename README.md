# Reactive Hook System for Uniswap V4

A cross-chain reactive system that monitors large liquidity movements in Uniswap V4 pools and triggers automated emergency responses via the Reactive Network.

## Architecture

### Components

**1. LiquidityChange Hook (Ethereum Mainnet)**
- Monitors `beforeAddLiquidity` and `beforeRemoveLiquidity` events
- Emits `LargeLiquidityChange` when liquidity delta exceeds threshold
- Deployed at: [`0x52c73a3EDC6E3D82ED675533144fd28886DccAC0`](https://etherscan.io/address/0x52c73a3EDC6E3D82ED675533144fd28886DccAC0)

**2. LiquidityChangeReactive (Reactive Mainnet)**
- Listens to hook events from Ethereum Mainnet
- Triggers `autoEmergencyExit()` on the strategy contract
- Deployed at: [`0x04Ef9046624802FcbF476DC07F885aDcED074AFf`](https://reactscan.net/address/0xb70649baf7a93eeb95e3946b3a82f8f312477d2b/contract/0x04ef9046624802fcbf476dc07f885adced074aff?screen=rnk_transactions)

**3. Strategy Contract (Ethereum Mainnet)**
- Receives automated emergency callbacks
- Deployed at: [`0xa2Ec9eD7AA256a49d47570BFfB41F7e8455Daa99`](https://etherscan.io/address/0xa2Ec9eD7AA256a49d47570BFfB41F7e8455Daa99)

### Flow

```
Ethereum Mainnet                    Reactive Mainnet
┌─────────────────┐                ┌──────────────────┐
│ User adds/      │                │                  │
│ removes liq.    │                │                  │
└────────┬────────┘                │                  │
         │                         │                  │
         v                         │                  │
┌─────────────────┐     event      │                  │
│ LiquidityChange ├───────────────>│ Liquidity        │
│ Hook            │                │ ChangeReactive   │
└─────────────────┘                └────────┬─────────┘
         │                                  │
         │ Emit LargeLiquidityChange        │ react()
         │                                  │
         │                                  v
         │                         ┌──────────────────┐
         │                         │ Callback Emitted │
         │                         │ (autoEmergency   │
         │                         │  Exit)           │
         │                         └────────┬─────────┘
         │                                  │
         v                                  v
┌─────────────────┐                ┌──────────────────┐
│ Strategy        │<───────────────│ Cross-chain      │
│ Contract        │                │ Callback         │
└─────────────────┘                └──────────────────┘
```

## Deployed Contracts

### Ethereum Mainnet (Chain ID: 1)

| Contract | Address | Description |
|----------|---------|-------------|
| LiquidityChange Hook | [`0x52c73a3EDC6E3D82ED675533144fd28886DccAC0`](https://etherscan.io/address/0x52c73a3EDC6E3D82ED675533144fd28886DccAC0) | Custom hook with threshold: `1000` |
| Strategy Contract | [`0xa2Ec9eD7AA256a49d47570BFfB41F7e8455Daa99`](https://etherscan.io/address/0xa2Ec9eD7AA256a49d47570BFfB41F7e8455Daa99) | Receives emergency callbacks |

### Reactive Mainnet (Chain ID: 5318008)

| Contract | Address | Description |
|----------|---------|-------------|
| LiquidityChangeReactive | [`0x04Ef9046624802FcbF476DC07F885aDcED074AFf`](https://reactscan.net/address/0xb70649baf7a93eeb95e3946b3a82f8f312477d2b/contract/0x04ef9046624802fcbf476dc07f885adced074aff?screen=rnk_transactions) | Reactive contract (1 ETH balance) |

**Monitored Hook:** [`0x52c73a3EDC6E3D82ED675533144fd28886DccAC0`](https://etherscan.io/address/0x52c73a3EDC6E3D82ED675533144fd28886DccAC0)

## On-Chain Proof

**Live Transaction:** [Emergency callback triggered on Ethereum Mainnet](https://etherscan.io/tx/0x4bb284fd21b9885b2386c42041f5b4cd2731400133e39db9b6b67788b26ef0f5)

This transaction demonstrates the complete flow:
1. Large liquidity event detected by hook
2. Reactive contract processes event
3. `autoEmergencyExit()` successfully called on strategy contract

## Configuration

| Parameter | Value | Notes |
|-----------|-------|-------|
| Liquidity Threshold | `1000` | Low value for testing |
| Event Topic Hash | `0xe4f4dfad1e4128943809bc23077ed765f12b98ec17ea4a5adc9657cc762d319c` | `LargeLiquidityChange` event |
| Callback Gas Limit | `1,000,000` | Gas for emergency callback |
| Tick Spacing | `60` | Pool configuration |

## How It Works

### 1. Hook Detection

```solidity
function _beforeAddLiquidity(...) internal override returns (bytes4) {
    if (params.liquidityDelta >= int256(LARGE_LIQUIDITY_THRESHOLD)) {
        emit LargeLiquidityChange(
            PoolId.unwrap(key.toId()),
            uint256(params.liquidityDelta),
            true
        );
    }
    return this.beforeAddLiquidity.selector;
}
```

### 2. Reactive Listener

```solidity
function react(LogRecord calldata log) external vmOnly {
    if (log._contract != pool) return;
    if (log.topic_0 != LARGE_LIQUIDITY_CHANGE_TOPIC_0) return;

    bytes memory payload = abi.encodeWithSignature("autoEmergencyExit()");
    emit Callback(CHAIN_ID, strategy, CALLBACK_GAS_LIMIT, payload);
}
```

### 3. Automatic Execution

When liquidity delta ≥ `1000`:
1. Hook emits `LargeLiquidityChange` on Ethereum Mainnet
2. Reactive contract detects event on Reactive Mainnet
3. System calls `autoEmergencyExit()` on strategy contract

## Monitoring

### Check Hook Events

```bash
# View emitted events from hook
cast logs 0x52c73a3EDC6E3D82ED675533144fd28886DccAC0 \
  --rpc-url mainnet \
  --from-block latest
```

### Check Reactive Events

```bash
# View reactive contract events
cast logs 0x04Ef9046624802FcbF476DC07F885aDcED074AFf \
  --rpc-url https://reactive-rpc.rnk.dev \
  --from-block latest
```

## Use Cases

- **Liquidity Dump Protection**: Automatically exit positions when large liquidity is removed
- **Whale Monitoring**: React to significant liquidity movements in real-time
- **Risk Management**: Trigger emergency procedures based on pool liquidity changes

## Notes

- Threshold set to `1000` for testing purposes
- System operates continuously while registered
- Reaction time: ~1-2 blocks
- Cross-chain coordination between Ethereum Mainnet and Reactive Mainnet
- No manual intervention required after configuration
