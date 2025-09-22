// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console} from "forge-std/console.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {CurrencyLibrary, Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";

import {BaseScript} from "./base/BaseScript.sol";
import {LiquidityHelpers} from "./base/LiquidityHelpers.sol";

contract AddLargeLiquidityScript is BaseScript, LiquidityHelpers {
    using CurrencyLibrary for Currency;

    /////////////////////////////////////
    // --- Configure These ---
    /////////////////////////////////////

    uint24 lpFee = 3000; // 0.30%
    int24 tickSpacing = 60;
    uint160 startingPrice = 79228162514264337593543950336;
    // need parity 1:1, sqrt(1) * 2^96 = 79228162514264337593543950336

    // --- Small liquidity amounts to trigger the hook event ---
    // Hook threshold is now 1000, so small amounts should work
    // Paridad 1:1 - token0 (6 decimals) : token1 (18 decimals)
    uint256 public token0Amount = 10e18; // 10 tokens with 6 decimals
    uint256 public token1Amount = 10e18; // 10 tokens with 18 decimals

    // Hook address (you need to set this to your deployed hook address)
    address public hookAddress;

    // range of the position, must be a multiple of tickSpacing
    int24 tickLower;
    int24 tickUpper;

    /////////////////////////////////////

    function run() external {
        // Get hook address from environment variable or user input
        try vm.envAddress("HOOK_ADDRESS") returns (address addr) {
            hookAddress = addr;
        } catch {
            revert("Please set HOOK_ADDRESS environment variable");
        }

        console.log("=== ADDING LARGE LIQUIDITY ===");
        console.log("Hook Address:", hookAddress);
        console.log("Token0 Amount:", token0Amount);
        console.log("Token1 Amount:", token1Amount);
        console.log(
            "Expected to trigger LargeLiquidityChange event (threshold: 10e18)"
        );

        // Create pool key with the deployed hook
        PoolKey memory poolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: lpFee,
            tickSpacing: tickSpacing,
            hooks: IHooks(hookAddress)
        });

        bytes memory hookData = new bytes(0);

        int24 currentTick = TickMath.getTickAtSqrtPrice(startingPrice);

        tickLower = truncateTickSpacing(
            (currentTick - 750 * tickSpacing),
            tickSpacing
        );
        tickUpper = truncateTickSpacing(
            (currentTick + 750 * tickSpacing),
            tickSpacing
        );

        // Converts token amounts to liquidity units
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            startingPrice,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            token0Amount,
            token1Amount
        );

        console.log("Calculated liquidity:", liquidity);
        console.log("This should be > 10e18 to trigger the event");

        // slippage limits
        uint256 amount0Max = token0Amount + 1;
        uint256 amount1Max = token1Amount + 1;

        // Use the working liquidity helper from BaseScript
        (
            bytes memory actions,
            bytes[] memory mintParams
        ) = _mintLiquidityParams(
                poolKey,
                tickLower,
                tickUpper,
                liquidity,
                amount0Max,
                amount1Max,
                deployerAddress,
                hookData
            );

        // Prepare multicall parameters
        bytes[] memory params = new bytes[](1);

        // Mint Liquidity (pool should already be initialized)
        params[0] = abi.encodeWithSelector(
            positionManager.modifyLiquidities.selector,
            abi.encode(actions, mintParams),
            block.timestamp + 3600
        );

        // If the pool is an ETH pair, native tokens are to be transferred
        uint256 valueToPass = currency0.isAddressZero() ? amount0Max : 0;

        vm.startBroadcast();

        tokenApprovals();

        console.log("Adding liquidity to trigger hook event...");

        // Add liquidity - this should trigger the LargeLiquidityChange event
        positionManager.multicall{value: valueToPass}(params);

        vm.stopBroadcast();

        console.log("\n=== LIQUIDITY ADDED SUCCESSFULLY ===");
        console.log("Check for LargeLiquidityChange event emission!");
        console.log(
            "Pool Key Hash:",
            vm.toString(keccak256(abi.encode(poolKey)))
        );
        console.log(
            "Expected Event: LargeLiquidityChange(bytes32 indexed poolId, uint256 liquidityAmount, bool isAdd)"
        );
        console.log(
            "Expected poolId:",
            vm.toString(keccak256(abi.encode(poolKey)))
        );
        console.log("Expected liquidityAmount:", liquidity);
        console.log("Expected isAdd: true");
    }
}
