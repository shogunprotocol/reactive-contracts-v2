// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IPool {
    function token0() external view returns (address);

    function token1() external view returns (address);

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
        );
}
