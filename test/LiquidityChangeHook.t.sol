// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {Constants} from "@uniswap/v4-core/test/utils/Constants.sol";

import {EasyPosm} from "./utils/EasyPosm.sol";
import {Deployers} from "./utils/Deployers.sol";

import {LiquidityChange} from "../src/hook/LiquidityChange.sol";

contract LiquidityHookTest is Test, Deployers {
    using EasyPosm for IPositionManager;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    Currency currency0;
    Currency currency1;

    PoolKey poolKey;

    LiquidityChange hook;
    PoolId poolId;

    uint256 tokenId;
    int24 tickLower;
    int24 tickUpper;

    function setUp() public {
        // Deploys all required artifacts.
        deployArtifacts();

        (currency0, currency1) = deployCurrencyPair();

        // Deploy the hook to an address with the correct flags
        address flags = address(
            uint160(
                Hooks.BEFORE_SWAP_FLAG |
                    Hooks.AFTER_SWAP_FLAG |
                    Hooks.BEFORE_ADD_LIQUIDITY_FLAG |
                    Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG
            ) ^ (0x4444 << 144) // Namespace the hook to avoid collisions
        );
        bytes memory constructorArgs = abi.encode(poolManager); // Add all the necessary constructor arguments from the hook
        deployCodeTo(
            "LiquidityChange.sol:LiquidityChange",
            constructorArgs,
            flags
        );
        hook = LiquidityChange(flags);

        // Create the pool
        poolKey = PoolKey(currency0, currency1, 3000, 60, IHooks(hook));
        poolId = poolKey.toId();
        poolManager.initialize(poolKey, Constants.SQRT_PRICE_1_1);

        // Provide full-range liquidity to the pool
        tickLower = TickMath.minUsableTick(poolKey.tickSpacing);
        tickUpper = TickMath.maxUsableTick(poolKey.tickSpacing);

        uint128 liquidityAmount = 100e18;

        (uint256 amount0Expected, uint256 amount1Expected) = LiquidityAmounts
            .getAmountsForLiquidity(
                Constants.SQRT_PRICE_1_1,
                TickMath.getSqrtPriceAtTick(tickLower),
                TickMath.getSqrtPriceAtTick(tickUpper),
                liquidityAmount
            );

        (tokenId, ) = positionManager.mint(
            poolKey,
            tickLower,
            tickUpper,
            liquidityAmount,
            amount0Expected + 1,
            amount1Expected + 1,
            address(this),
            block.timestamp,
            Constants.ZERO_BYTES
        );
    }

    function testCounterHooks() public {
        // positions were created in setup()
        assertEq(hook.beforeAddLiquidityCount(poolId), 1);
        assertEq(hook.beforeRemoveLiquidityCount(poolId), 0);

        assertEq(hook.beforeSwapCount(poolId), 0);
        assertEq(hook.afterSwapCount(poolId), 0);

        // Perform a test swap //
        uint256 amountIn = 1e18;
        BalanceDelta swapDelta = swapRouter.swapExactTokensForTokens({
            amountIn: amountIn,
            amountOutMin: 0, // Very bad, but we want to allow for unlimited price impact
            zeroForOne: true,
            poolKey: poolKey,
            hookData: Constants.ZERO_BYTES,
            receiver: address(this),
            deadline: block.timestamp + 1
        });
        // ------------------- //

        assertEq(int256(swapDelta.amount0()), -int256(amountIn));

        assertEq(hook.beforeSwapCount(poolId), 1);
        assertEq(hook.afterSwapCount(poolId), 1);
    }

    function testLiquidityHooks() public {
        // positions were created in setup()
        assertEq(hook.beforeAddLiquidityCount(poolId), 1);
        assertEq(hook.beforeRemoveLiquidityCount(poolId), 0);

        // remove liquidity
        uint256 liquidityToRemove = 1e18;
        positionManager.decreaseLiquidity(
            tokenId,
            liquidityToRemove,
            0, // Max slippage, token0
            0, // Max slippage, token1
            address(this),
            block.timestamp,
            Constants.ZERO_BYTES
        );

        assertEq(hook.beforeAddLiquidityCount(poolId), 1);
        assertEq(hook.beforeRemoveLiquidityCount(poolId), 1);
    }

    function testLargeLiquidityAddEvent() public {
        // Add large liquidity (> 10e18) - should emit event
        uint128 largeLiquidity = 15e18; // Above threshold

        (uint256 amount0Expected, uint256 amount1Expected) = LiquidityAmounts
            .getAmountsForLiquidity(
                Constants.SQRT_PRICE_1_1,
                TickMath.getSqrtPriceAtTick(tickLower),
                TickMath.getSqrtPriceAtTick(tickUpper),
                largeLiquidity
            );

        // Expect the LargeLiquidityChange event to be emitted
        vm.expectEmit(true, false, false, true);
        emit LargeLiquidityChange(
            PoolId.unwrap(poolId),
            largeLiquidity,
            true // isAdd = true
        );

        positionManager.mint(
            poolKey,
            tickLower,
            tickUpper,
            largeLiquidity,
            amount0Expected + 1,
            amount1Expected + 1,
            address(this),
            block.timestamp,
            Constants.ZERO_BYTES
        );

        // Verify counter increased
        assertEq(hook.beforeAddLiquidityCount(poolId), 2);
    }

    function testSmallLiquidityAddNoEvent() public {
        // Add small liquidity (< 10e18) - should NOT emit event
        uint128 smallLiquidity = 5e18; // Below threshold

        (uint256 amount0Expected, uint256 amount1Expected) = LiquidityAmounts
            .getAmountsForLiquidity(
                Constants.SQRT_PRICE_1_1,
                TickMath.getSqrtPriceAtTick(tickLower),
                TickMath.getSqrtPriceAtTick(tickUpper),
                smallLiquidity
            );

        // Record logs to check no event was emitted
        vm.recordLogs();

        positionManager.mint(
            poolKey,
            tickLower,
            tickUpper,
            smallLiquidity,
            amount0Expected + 1,
            amount1Expected + 1,
            address(this),
            block.timestamp,
            Constants.ZERO_BYTES
        );

        // Check no LargeLiquidityChange event was emitted
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool eventEmitted = false;

        for (uint i = 0; i < logs.length; i++) {
            if (
                logs[i].topics[0] ==
                keccak256("LargeLiquidityChange(bytes32,uint256,bool)")
            ) {
                eventEmitted = true;
                break;
            }
        }

        assertFalse(
            eventEmitted,
            "LargeLiquidityChange event should not be emitted for small changes"
        );

        // But counter should still increase
        assertEq(hook.beforeAddLiquidityCount(poolId), 2);
    }

    function testLargeLiquidityRemoveEvent() public {
        // First add a lot of liquidity so we can remove a large amount
        uint128 largeLiquidity = 50e18;

        (uint256 amount0Expected, uint256 amount1Expected) = LiquidityAmounts
            .getAmountsForLiquidity(
                Constants.SQRT_PRICE_1_1,
                TickMath.getSqrtPriceAtTick(tickLower),
                TickMath.getSqrtPriceAtTick(tickUpper),
                largeLiquidity
            );

        // Add liquidity first
        (uint256 newTokenId, ) = positionManager.mint(
            poolKey,
            tickLower,
            tickUpper,
            largeLiquidity,
            amount0Expected + 1,
            amount1Expected + 1,
            address(this),
            block.timestamp,
            Constants.ZERO_BYTES
        );

        // Now remove large amount (> 10e18) - should emit event
        uint256 largeRemoval = 15e18; // Above threshold

        // Expect the LargeLiquidityChange event to be emitted
        vm.expectEmit(true, false, false, true);
        emit LargeLiquidityChange(
            PoolId.unwrap(poolId),
            largeRemoval,
            false // isAdd = false
        );

        positionManager.decreaseLiquidity(
            newTokenId,
            largeRemoval,
            0, // Max slippage, token0
            0, // Max slippage, token1
            address(this),
            block.timestamp,
            Constants.ZERO_BYTES
        );

        // Verify counters
        assertEq(hook.beforeAddLiquidityCount(poolId), 2); // Original + new mint
        assertEq(hook.beforeRemoveLiquidityCount(poolId), 1); // One removal
    }

    // Event declaration for testing
    event LargeLiquidityChange(
        bytes32 indexed poolId,
        uint256 liquidityAmount,
        bool isAdd
    );
}
