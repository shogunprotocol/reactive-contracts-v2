// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console} from "forge-std/console.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {CurrencyLibrary, Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";

import {LiquidityChange} from "../src/hook/LiquidityChange.sol";
import {BaseScript} from "./base/BaseScript.sol";
import {LiquidityHelpers} from "./base/LiquidityHelpers.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";

contract CreatePoolWithLiquidityChangeHook is BaseScript, LiquidityHelpers {
    using CurrencyLibrary for Currency;

    address constant CREATE2_DEPLOYER =
        address(0x4e59b44847b379578588920cA78FbF26c0B4956C);

    // Deployed hook
    LiquidityChange public deployedHook;

    /////////////////////////////////////
    // --- Configure These ---
    /////////////////////////////////////

    uint24 lpFee = 3000; // 0.30%
    int24 tickSpacing = 60;
    uint160 startingPrice = 2 ** 96; // Starting price, sqrtPriceX96; floor(sqrt(1) * 2^96)

    // --- liquidity position configuration --- //
    // Paridad 1:1 - token0 (6 decimals) : token1 (18 decimals)
    // Using realistic amounts that you might have
    uint256 public token0Amount = 10e6; // 100 tokens with 6 decimals
    uint256 public token1Amount = 10e18; // 100 tokens with 18 decimals

    // range of the position, must be a multiple of tickSpacing
    int24 tickLower;
    int24 tickUpper;

    /////////////////////////////////////

    function run() external {
        // STEP 1: Mine hook address with correct flags (following v4-periphery pattern)
        uint160 flags = uint160(
            Hooks.BEFORE_SWAP_FLAG |
                Hooks.AFTER_SWAP_FLAG |
                Hooks.BEFORE_ADD_LIQUIDITY_FLAG |
                Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG
        );

        bytes memory constructorArgs = abi.encode(poolManager);

        // Mine a salt that will produce a hook address with the correct flags
        (address hookAddress, bytes32 salt) = HookMiner.find(
            CREATE2_DEPLOYER,
            flags,
            type(LiquidityChange).creationCode,
            constructorArgs
        );

        vm.startBroadcast();

        // Deploy the hook using CREATE2 with the mined salt
        deployedHook = new LiquidityChange{salt: salt}(poolManager);
        require(address(deployedHook) == hookAddress, "Hook address mismatch");

        console.log("Hook deployed at:", address(deployedHook));
        vm.label(address(deployedHook), "LiquidityChangeHook");
        deployedHook = LiquidityChange(hookAddress);
        // STEP 2: Now create pool with the deployed hook
        PoolKey memory poolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: lpFee,
            tickSpacing: tickSpacing,
            hooks: deployedHook // Use our deployed hook instead of address(0)
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

        // multicall parameters
        bytes[] memory params = new bytes[](2);

        // Initialize Pool
        params[0] = abi.encodeWithSelector(
            positionManager.initializePool.selector,
            poolKey,
            startingPrice,
            hookData
        );

        // Mint Liquidity
        params[1] = abi.encodeWithSelector(
            positionManager.modifyLiquidities.selector,
            abi.encode(actions, mintParams),
            block.timestamp + 3600
        );

        // If the pool is an ETH pair, native tokens are to be transferred
        uint256 valueToPass = currency0.isAddressZero() ? amount0Max : 0;

        tokenApprovals();

        // Multicall to atomically create pool & add liquidity
        positionManager.multicall{value: valueToPass}(params);
        vm.stopBroadcast();

        // DONE!
        console.log("SUCCESS:");
        console.log("Hook deployed at:", address(deployedHook));
        console.log("Pool created with hook integration");
    }
}
