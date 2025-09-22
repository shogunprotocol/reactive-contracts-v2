// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title MockUniswapV3
 * @dev A mock implementation of Uniswap V3 protocol for testing
 * @notice Simulates Uniswap V3's concentrated liquidity and fee tiers
 */
contract MockUniswapV3 {
    using SafeERC20 for IERC20;

    // State variables
    IERC20 public immutable token0;
    IERC20 public immutable token1;

    struct Position {
        uint256 liquidity;
        uint256 tokensOwed0;
        uint256 tokensOwed1;
        uint256 feeGrowthInside0LastX128;
        uint256 feeGrowthInside1LastX128;
        int24 tickLower;
        int24 tickUpper;
    }

    mapping(address => Position) public positions;
    mapping(address => uint256) public userFeesCollected0;
    mapping(address => uint256) public userFeesCollected1;

    // Pool parameters
    uint24 public fee = 3000; // 0.3% fee tier
    int24 public tick = 0; // Current tick
    uint160 public sqrtPriceX96 = 79228162514264337593543950336; // sqrt(1) in Q96
    uint256 public liquidity;

    // Fee parameters
    uint256 public feeGrowthGlobal0X128;
    uint256 public feeGrowthGlobal1X128;

    // Events
    event Mint(
        address indexed sender,
        address indexed owner,
        int24 indexed tickLower,
        int24 tickUpper,
        uint128 amount,
        uint256 amount0,
        uint256 amount1
    );
    event Burn(
        address indexed owner,
        int24 indexed tickLower,
        int24 tickUpper,
        uint128 amount,
        uint256 amount0,
        uint256 amount1
    );
    event Swap(
        address indexed sender,
        address indexed recipient,
        int256 amount0,
        int256 amount1,
        uint160 sqrtPriceX96,
        uint128 liquidity,
        int24 tick
    );
    event Collect(
        address indexed owner,
        address recipient,
        int24 indexed tickLower,
        int24 tickUpper,
        uint128 amount0,
        uint128 amount1
    );

    // Errors
    error InsufficientLiquidity();
    error InvalidTickRange();
    error ZeroAmount();

    constructor(address _token0, address _token1, uint24 _fee) {
        token0 = IERC20(_token0);
        token1 = IERC20(_token1);
        fee = _fee;
    }

    /**
     * @dev Mints a new position (adds liquidity)
     * @param tickLower Lower tick of the position
     * @param tickUpper Upper tick of the position
     * @param amount Liquidity amount to add
     */
    function mint(int24 tickLower, int24 tickUpper, uint128 amount) external {
        if (amount == 0) revert ZeroAmount();
        if (tickLower >= tickUpper) revert InvalidTickRange();

        // Calculate token amounts needed (simplified)
        uint256 amount0 = (uint256(amount) * 1e18) / 2 ** 96; // Simplified calculation
        uint256 amount1 = (uint256(amount) * 1e18) / 2 ** 96; // Simplified calculation

        // Transfer tokens from user
        token0.safeTransferFrom(msg.sender, address(this), amount0);
        token1.safeTransferFrom(msg.sender, address(this), amount1);

        // Update position
        Position storage position = positions[msg.sender];
        position.liquidity += amount;
        position.tickLower = tickLower;
        position.tickUpper = tickUpper;
        position.feeGrowthInside0LastX128 = feeGrowthGlobal0X128;
        position.feeGrowthInside1LastX128 = feeGrowthGlobal1X128;

        // Update global liquidity
        liquidity += amount;

        emit Mint(
            msg.sender,
            msg.sender,
            tickLower,
            tickUpper,
            amount,
            amount0,
            amount1
        );
    }

    /**
     * @dev Burns liquidity from a position
     * @param tickLower Lower tick of the position
     * @param tickUpper Upper tick of the position
     * @param amount Liquidity amount to remove
     */
    function burn(int24 tickLower, int24 tickUpper, uint128 amount) external {
        if (amount == 0) revert ZeroAmount();

        Position storage position = positions[msg.sender];
        if (position.liquidity < amount) revert InsufficientLiquidity();

        // Calculate token amounts to return (simplified)
        uint256 amount0 = (uint256(amount) * 1e18) / 2 ** 96; // Simplified calculation
        uint256 amount1 = (uint256(amount) * 1e18) / 2 ** 96; // Simplified calculation

        // Update position
        position.liquidity -= amount;
        position.tokensOwed0 += amount0;
        position.tokensOwed1 += amount1;

        // Update global liquidity
        liquidity -= amount;

        emit Burn(msg.sender, tickLower, tickUpper, amount, amount0, amount1);
    }

    /**
     * @dev Swaps tokens using the pool
     * @param zeroForOne Direction of swap (true: token0 -> token1)
     * @param amountSpecified Amount to swap (positive for exact input, negative for exact output)
     * @param sqrtPriceLimitX96 Price limit for the swap
     */
    function swap(
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96
    ) external {
        if (amountSpecified == 0) revert ZeroAmount();

        uint256 amountIn = uint256(amountSpecified);
        uint256 feeAmount = (amountIn * fee) / 1e6;
        uint256 amountInAfterFee = amountIn - feeAmount;

        // Simplified swap calculation
        uint256 amountOut = (amountInAfterFee * 99) / 100; // 1% slippage

        if (zeroForOne) {
            // Swap token0 for token1
            token0.safeTransferFrom(msg.sender, address(this), amountIn);
            token1.safeTransfer(msg.sender, amountOut);

            // Update fee growth
            feeGrowthGlobal0X128 += (feeAmount * 2 ** 128) / liquidity;
        } else {
            // Swap token1 for token0
            token1.safeTransferFrom(msg.sender, address(this), amountIn);
            token0.safeTransfer(msg.sender, amountOut);

            // Update fee growth
            feeGrowthGlobal1X128 += (feeAmount * 2 ** 128) / liquidity;
        }

        // Update price (simplified)
        if (zeroForOne) {
            sqrtPriceX96 = (sqrtPriceX96 * 99) / 100; // Price decreases
            tick -= 1;
        } else {
            sqrtPriceX96 = (sqrtPriceX96 * 101) / 100; // Price increases
            tick += 1;
        }

        emit Swap(
            msg.sender,
            msg.sender,
            zeroForOne ? int256(amountIn) : -int256(amountOut),
            zeroForOne ? -int256(amountOut) : int256(amountIn),
            sqrtPriceX96,
            uint128(liquidity),
            tick
        );
    }

    /**
     * @dev Collects fees and tokens owed from a position
     * @param tickLower Lower tick of the position
     * @param tickUpper Upper tick of the position
     * @param amount0Requested Amount of token0 to collect
     * @param amount1Requested Amount of token1 to collect
     */
    function collect(
        int24 tickLower,
        int24 tickUpper,
        uint128 amount0Requested,
        uint128 amount1Requested
    ) external {
        Position storage position = positions[msg.sender];

        // Calculate fees earned (simplified)
        uint256 fees0 = (position.liquidity *
            (feeGrowthGlobal0X128 - position.feeGrowthInside0LastX128)) /
            2 ** 128;
        uint256 fees1 = (position.liquidity *
            (feeGrowthGlobal1X128 - position.feeGrowthInside1LastX128)) /
            2 ** 128;

        // Add to tokens owed
        position.tokensOwed0 += fees0;
        position.tokensOwed1 += fees1;

        // Update fee growth
        position.feeGrowthInside0LastX128 = feeGrowthGlobal0X128;
        position.feeGrowthInside1LastX128 = feeGrowthGlobal1X128;

        // Calculate amounts to collect
        uint256 amount0 = amount0Requested > position.tokensOwed0
            ? position.tokensOwed0
            : amount0Requested;
        uint256 amount1 = amount1Requested > position.tokensOwed1
            ? position.tokensOwed1
            : amount1Requested;

        // Update tokens owed
        position.tokensOwed0 -= amount0;
        position.tokensOwed1 -= amount1;

        // Transfer tokens
        if (amount0 > 0) {
            token0.safeTransfer(msg.sender, amount0);
            userFeesCollected0[msg.sender] += amount0;
        }
        if (amount1 > 0) {
            token1.safeTransfer(msg.sender, amount1);
            userFeesCollected1[msg.sender] += amount1;
        }

        emit Collect(
            msg.sender,
            msg.sender,
            tickLower,
            tickUpper,
            uint128(amount0),
            uint128(amount1)
        );
    }

    /**
     * @dev Gets the position info for a user
     * @param user Address of the user
     * @return position The position struct
     */
    function getPosition(
        address user
    ) external view returns (Position memory position) {
        return positions[user];
    }

    /**
     * @dev Gets the current pool state
     * @return _sqrtPriceX96 Current sqrt price
     * @return _tick Current tick
     * @return _liquidity Current liquidity
     */
    function slot0()
        external
        view
        returns (uint160 _sqrtPriceX96, int24 _tick, uint256 _liquidity)
    {
        return (sqrtPriceX96, tick, liquidity);
    }

    /**
     * @dev Gets user's liquidity balance
     * @param user Address of the user
     * @return uint256 Liquidity balance
     */
    function getUserLiquidity(address user) external view returns (uint256) {
        return positions[user].liquidity;
    }

    /**
     * @dev Gets user's uncollected fees
     * @param user Address of the user
     * @return amount0 Uncollected fees for token0
     * @return amount1 Uncollected fees for token1
     */
    function getUnclaimedFees(
        address user
    ) external view returns (uint256 amount0, uint256 amount1) {
        Position storage position = positions[user];

        // Calculate fees earned (simplified)
        uint256 fees0 = (position.liquidity *
            (feeGrowthGlobal0X128 - position.feeGrowthInside0LastX128)) /
            2 ** 128;
        uint256 fees1 = (position.liquidity *
            (feeGrowthGlobal1X128 - position.feeGrowthInside1LastX128)) /
            2 ** 128;

        return (position.tokensOwed0 + fees0, position.tokensOwed1 + fees1);
    }

    /**
     * @dev Updates fee tier (for testing purposes)
     * @param newFee New fee tier (in basis points * 100, e.g., 3000 for 0.3%)
     */
    function updateFee(uint24 newFee) external {
        fee = newFee;
    }
}
