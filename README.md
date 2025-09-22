# Counter Hook - Uniswap v4 Liquidity Monitoring Hook

This project implements a Uniswap v4 hook that monitors liquidity changes in pools.

## Overview

The project includes:

- `SimpleLiquidityHook`: A basic hook that monitors beforeAddLiquidity and beforeRemoveLiquidity operations
- `LiquidityChange`: A more advanced hook with threshold-based event emission (currently has compilation issues)
- Deployment scripts for creating pools with hooks

## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

- **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
- **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
- **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
- **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```

## Hook Usage

### Deploy Hook and Create Pool

Run the complete deployment script:

```bash
# For testnet
forge script script/CreatePoolWithLiquidityChangeHook.s.sol --rpc-url $RPC_URL --broadcast --verify

# For local testing
forge script script/CreatePoolWithLiquidityChangeHook.s.sol --fork-url $RPC_URL
```

### Test Hook Deployment

Test just the hook deployment:

```bash
forge script script/TestSimpleHookDeploy.s.sol --rpc-url $RPC_URL --broadcast
```

## Hook Functionality

The `SimpleLiquidityHook` implements:

- `beforeAddLiquidity`: Called before liquidity is added to a pool
- `beforeRemoveLiquidity`: Called before liquidity is removed from a pool
- Hook permissions configured to only monitor these operations

## Project Structure

```
src/
├── hook/
│   ├── SimpleLiquidityHook.sol    # Working basic hook
│   └── LiquidityChange.sol        # Advanced hook (needs fixes)
script/
├── CreatePoolWithLiquidityChangeHook.s.sol  # Complete deployment
├── TestSimpleHookDeploy.s.sol               # Hook-only deployment
└── base/
    ├── BaseScript.sol
    ├── AddressConstants.sol
    └── LiquidityHelpers.sol
```

## Next Steps

1. Fix the `LiquidityChange` contract compilation issues
2. Add more sophisticated monitoring logic
3. Implement threshold-based event emission
4. Add tests for hook functionality
# reactive-contracts-v2
