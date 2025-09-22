// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interfaces/IPool.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract MockPool is IPool, Ownable {
    address public token0_;
    address public token1_;

    // Mock state variables - more realistic simulation
    uint160 public sqrtPriceX96_;
    int24 public tick_;
    uint16 public lastFee_;
    uint8 public pluginConfig_;
    uint128 public activeLiquidity_;
    int24 public nextTick_;
    int24 public previousTick_;

    // Additional state for realistic behavior
    uint256 public feeGrowthGlobal0X128;
    uint256 public feeGrowthGlobal1X128;
    uint128 public liquidity;
    uint256 public totalFeesCollected0;
    uint256 public totalFeesCollected1;

    // Price simulation
    uint256 public constant Q96 = 2 ** 96;
    uint256 public constant PRICE_PRECISION = 1e18;

    // Events
    event Swap(
        address indexed sender,
        address indexed recipient,
        int256 amount0,
        int256 amount1,
        uint160 sqrtPriceX96,
        uint128 liquidity,
        int24 tick
    );

    event Mint(
        address indexed sender,
        address indexed owner,
        int24 indexed tickLower,
        int24 tickUpper,
        uint128 amount,
        uint256 amount0,
        uint256 amount1
    );

    constructor(address _token0, address _token1) Ownable(msg.sender) {
        token0_ = _token0;
        token1_ = _token1;

        // Initialize with realistic 1:1 price for stablecoins
        sqrtPriceX96_ = uint160((1 << 96) * 1); // sqrt(1) * 2^96 = 1:1 price
        tick_ = 0; // 1:1 price tick
        lastFee_ = 500; // 0.05% (5 bps)
        pluginConfig_ = 0;
        activeLiquidity_ = 1000000 ether; // High liquidity for stablecoins
        liquidity = activeLiquidity_;
        nextTick_ = 100; // Next tick up
        previousTick_ = -100; // Previous tick down

        // Initialize fee growth
        feeGrowthGlobal0X128 = 0;
        feeGrowthGlobal1X128 = 0;
    }

    function token0() external view returns (address) {
        return token0_;
    }

    function token1() external view returns (address) {
        return token1_;
    }

    function globalState()
        external
        view
        returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint16 lastFee,
            uint8 pluginConfig,
            uint128 activeLiquidity,
            int24 nextTick,
            int24 previousTick
        )
    {
        return (
            sqrtPriceX96_,
            tick_,
            lastFee_,
            pluginConfig_,
            activeLiquidity_,
            nextTick_,
            previousTick_
        );
    }

    // Simulate price impact when liquidity changes
    function updatePriceFromLiquidity(uint128 newLiquidity) internal {
        // Simplified price impact simulation
        if (newLiquidity > liquidity) {
            // Liquidity increase - small price movement toward 1:1
            uint160 priceAdjustment = uint160(
                uint256(newLiquidity - liquidity) / 1000
            );
            if (sqrtPriceX96_ < uint160(Q96) + priceAdjustment) {
                sqrtPriceX96_ = uint160(Q96); // Clamp to 1:1
            } else {
                sqrtPriceX96_ -= priceAdjustment;
            }
        } else {
            // Liquidity decrease - small price movement away from 1:1
            uint160 priceAdjustment = uint160(
                uint256(liquidity - newLiquidity) / 1000
            );
            sqrtPriceX96_ += priceAdjustment;
        }
        liquidity = newLiquidity;
        activeLiquidity_ = newLiquidity;
    }

    // Simulate fee collection over time
    function accrueFees(uint256 amount0In, uint256 amount1In) internal {
        if (amount0In > 0) {
            uint256 fee0 = (amount0In * lastFee_) / 10000; // Fee in basis points
            totalFeesCollected0 += fee0;
            feeGrowthGlobal0X128 += (fee0 << 128) / activeLiquidity_;
        }
        if (amount1In > 0) {
            uint256 fee1 = (amount1In * lastFee_) / 10000;
            totalFeesCollected1 += fee1;
            feeGrowthGlobal1X128 += (fee1 << 128) / activeLiquidity_;
        }
    }

    // Helper functions for testing
    function setPrice(uint160 _sqrtPriceX96) external onlyOwner {
        sqrtPriceX96_ = _sqrtPriceX96;
    }

    function setTick(int24 _tick) external onlyOwner {
        tick_ = _tick;
    }

    function setLiquidity(uint128 _liquidity) external onlyOwner {
        updatePriceFromLiquidity(_liquidity);
    }

    function setFee(uint16 _fee) external onlyOwner {
        lastFee_ = _fee;
    }

    function addLiquidity(uint128 amount) external onlyOwner {
        updatePriceFromLiquidity(liquidity + amount);
    }

    function removeLiquidity(uint128 amount) external onlyOwner {
        require(amount <= liquidity, "insufficient-liquidity");
        updatePriceFromLiquidity(liquidity - amount);
    }

    // Simulate swap with price impact
    function simulateSwap(
        int256 amount0Delta,
        int256 amount1Delta
    ) external onlyOwner {
        // Update price based on swap
        if (amount0Delta > 0) {
            // Buying token0, selling token1 - price of token0 increases
            sqrtPriceX96_ += uint160(uint256(amount0Delta) / 1000);
        } else if (amount1Delta > 0) {
            // Buying token1, selling token0 - price of token0 decreases
            uint160 priceChange = uint160(uint256(amount1Delta) / 1000);
            if (sqrtPriceX96_ > priceChange) {
                sqrtPriceX96_ -= priceChange;
            }
        }

        // Accrue fees
        accrueFees(
            amount0Delta > 0 ? uint256(amount0Delta) : 0,
            amount1Delta > 0 ? uint256(amount1Delta) : 0
        );

        emit Swap(
            msg.sender,
            msg.sender,
            amount0Delta,
            amount1Delta,
            sqrtPriceX96_,
            liquidity,
            tick_
        );
    }

    // Get current price in human readable format
    function getPrice() external view returns (uint256 price) {
        // Convert sqrtPriceX96 to regular price
        uint256 sqrtPrice = uint256(sqrtPriceX96_) / Q96;
        return ((sqrtPrice * sqrtPrice) * PRICE_PRECISION) / PRICE_PRECISION;
    }

    // Check if price is within bounds
    function isPriceInRange(
        int24 tickLower,
        int24 tickUpper
    ) external view returns (bool) {
        return tick_ >= tickLower && tick_ <= tickUpper;
    }
}
