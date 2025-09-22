// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title MockSushiSwap
 * @dev A mock implementation of SushiSwap protocol for testing
 * @notice Simulates SushiSwap's AMM functionality with liquidity provision and rewards
 */
contract MockSushiSwap {
    using SafeERC20 for IERC20;

    // State variables
    IERC20 public immutable token0;
    IERC20 public immutable token1;
    IERC20 public immutable sushiToken; // Reward token

    mapping(address => uint256) public liquidityProvided;
    mapping(address => uint256) public rewardsAccumulated;
    mapping(address => uint256) public lastStakeTime;

    // Pool parameters
    uint256 public totalLiquidity;
    uint256 public rewardRate = 100; // 1% per interaction
    uint256 public constant FEE_RATE = 30; // 0.3% trading fee
    uint256 public constant FEE_BASE = 10000;

    // Pool reserves
    uint256 public reserve0;
    uint256 public reserve1;

    // Events
    event LiquidityAdded(
        address indexed provider,
        uint256 amount0,
        uint256 amount1,
        uint256 liquidity
    );
    event LiquidityRemoved(
        address indexed provider,
        uint256 amount0,
        uint256 amount1,
        uint256 liquidity
    );
    event TokensSwapped(
        address indexed user,
        uint256 amountIn,
        uint256 amountOut,
        bool zeroForOne
    );
    event RewardsHarvested(address indexed user, uint256 amount);
    event Staked(address indexed user, uint256 amount);

    // Errors
    error InsufficientLiquidity();
    error InsufficientBalance();
    error ZeroAmount();
    error SlippageTooHigh();

    constructor(address _token0, address _token1, address _sushiToken) {
        token0 = IERC20(_token0);
        token1 = IERC20(_token1);
        sushiToken = IERC20(_sushiToken);
    }

    /**
     * @dev Adds liquidity to the SushiSwap pool
     * @param amount0 Amount of token0 to add
     * @param amount1 Amount of token1 to add
     */
    function addLiquidity(uint256 amount0, uint256 amount1) external {
        if (amount0 == 0 || amount1 == 0) revert ZeroAmount();

        token0.safeTransferFrom(msg.sender, address(this), amount0);
        token1.safeTransferFrom(msg.sender, address(this), amount1);

        // Simple liquidity calculation (geometric mean)
        uint256 liquidity = sqrt(amount0 * amount1);

        liquidityProvided[msg.sender] += liquidity;
        totalLiquidity += liquidity;
        lastStakeTime[msg.sender] = block.timestamp;

        // Update reserves
        reserve0 += amount0;
        reserve1 += amount1;

        // Generate rewards for liquidity provision
        uint256 rewards = (liquidity * rewardRate) / FEE_BASE;
        rewardsAccumulated[msg.sender] += rewards;

        emit LiquidityAdded(msg.sender, amount0, amount1, liquidity);
        emit Staked(msg.sender, liquidity);
    }

    /**
     * @dev Removes liquidity from the SushiSwap pool
     * @param liquidity Amount of liquidity tokens to remove
     */
    function removeLiquidity(uint256 liquidity) external {
        if (liquidity == 0) revert ZeroAmount();
        if (liquidityProvided[msg.sender] < liquidity)
            revert InsufficientLiquidity();

        liquidityProvided[msg.sender] -= liquidity;
        totalLiquidity -= liquidity;

        // Calculate proportional amounts
        uint256 amount0 = (liquidity * reserve0) / totalLiquidity;
        uint256 amount1 = (liquidity * reserve1) / totalLiquidity;

        // Update reserves
        reserve0 -= amount0;
        reserve1 -= amount1;

        // Transfer tokens back
        token0.safeTransfer(msg.sender, amount0);
        token1.safeTransfer(msg.sender, amount1);

        emit LiquidityRemoved(msg.sender, amount0, amount1, liquidity);
    }

    /**
     * @dev Swaps token0 for token1 or vice versa
     * @param amountIn Amount of tokens to swap
     * @param zeroForOne Direction of swap (true: token0->token1, false: token1->token0)
     * @param minAmountOut Minimum amount of tokens to receive
     */
    function swap(
        uint256 amountIn,
        bool zeroForOne,
        uint256 minAmountOut
    ) external {
        if (amountIn == 0) revert ZeroAmount();

        uint256 amountOut;

        if (zeroForOne) {
            // Swap token0 for token1
            token0.safeTransferFrom(msg.sender, address(this), amountIn);

            // Apply fee
            uint256 amountInAfterFee = amountIn -
                ((amountIn * FEE_RATE) / FEE_BASE);

            // Simple constant product formula
            amountOut =
                (reserve1 * amountInAfterFee) /
                (reserve0 + amountInAfterFee);

            if (amountOut < minAmountOut) revert SlippageTooHigh();
            if (reserve1 < amountOut) revert InsufficientLiquidity();

            reserve0 += amountIn;
            reserve1 -= amountOut;

            token1.safeTransfer(msg.sender, amountOut);
        } else {
            // Swap token1 for token0
            token1.safeTransferFrom(msg.sender, address(this), amountIn);

            // Apply fee
            uint256 amountInAfterFee = amountIn -
                ((amountIn * FEE_RATE) / FEE_BASE);

            // Simple constant product formula
            amountOut =
                (reserve0 * amountInAfterFee) /
                (reserve1 + amountInAfterFee);

            if (amountOut < minAmountOut) revert SlippageTooHigh();
            if (reserve0 < amountOut) revert InsufficientLiquidity();

            reserve1 += amountIn;
            reserve0 -= amountOut;

            token0.safeTransfer(msg.sender, amountOut);
        }

        emit TokensSwapped(msg.sender, amountIn, amountOut, zeroForOne);
    }

    /**
     * @dev Stakes liquidity tokens for additional rewards
     * @param amount Amount of liquidity to stake
     */
    function stakeLiquidity(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        if (liquidityProvided[msg.sender] < amount)
            revert InsufficientBalance();

        // Simulate staking by updating last stake time and adding rewards
        lastStakeTime[msg.sender] = block.timestamp;

        // Generate staking rewards
        uint256 stakingRewards = (amount * rewardRate * 2) / FEE_BASE; // 2x rewards for staking
        rewardsAccumulated[msg.sender] += stakingRewards;

        emit Staked(msg.sender, amount);
    }

    /**
     * @dev Harvests accumulated SUSHI rewards
     */
    function harvestRewards() external {
        uint256 rewards = rewardsAccumulated[msg.sender];
        if (rewards == 0) revert ZeroAmount();

        rewardsAccumulated[msg.sender] = 0;
        sushiToken.safeTransfer(msg.sender, rewards);

        emit RewardsHarvested(msg.sender, rewards);
    }

    /**
     * @dev Gets user's liquidity balance
     * @param user Address of the user
     * @return uint256 Liquidity balance
     */
    function getLiquidityBalance(address user) external view returns (uint256) {
        return liquidityProvided[user];
    }

    /**
     * @dev Gets user's pending rewards
     * @param user Address of the user
     * @return uint256 Pending rewards
     */
    function getPendingRewards(address user) external view returns (uint256) {
        uint256 baseRewards = rewardsAccumulated[user];

        // Add time-based rewards if user has liquidity
        if (liquidityProvided[user] > 0 && lastStakeTime[user] > 0) {
            uint256 timeStaked = block.timestamp - lastStakeTime[user];
            uint256 timeRewards = (liquidityProvided[user] *
                timeStaked *
                rewardRate) / (FEE_BASE * 86400); // Daily rewards
            return baseRewards + timeRewards;
        }

        return baseRewards;
    }

    /**
     * @dev Updates reward rate (for testing purposes)
     * @param newRate New reward rate (basis points)
     */
    function updateRewardRate(uint256 newRate) external {
        rewardRate = newRate;
    }

    /**
     * @dev Simple square root implementation for liquidity calculation
     * @param x Number to calculate square root of
     * @return uint256 Square root of x
     */
    function sqrt(uint256 x) internal pure returns (uint256) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        uint256 y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
        return y;
    }
}
