// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/// @title YieldMath
/// @notice Library for calculating compound interest and yield
/// @dev Provides efficient yield calculation methods with different precision levels
library YieldMath {
    // ============ Constants ============
    /// @notice Fixed point scale factor (18 decimals)
    uint256 private constant SCALE = 1e18;
    /// @notice Seconds in a year for compound interest calculations
    uint256 private constant SECONDS_PER_YEAR = 365 days;
    /// @notice Threshold for using linear approximation (7 days)
    uint256 private constant LINEAR_THRESHOLD = 7 days;
    /// @notice Maximum days for compound calculation (2 years)
    uint256 private constant MAX_DAYS = 730;

    // ============ Errors ============
    error InvalidParameters();

    // ============ Yield Calculation Functions ============
    /**
     * @dev Computes compound interest yield using efficient approximation
     * @param principal The principal amount to calculate yield for
     * @param yieldRate The annual yield rate in basis points
     * @param timeElapsed The time elapsed in seconds
     * @return yieldAmount The computed compound interest yield amount
     */
    function computeYield(
        uint256 principal,
        uint256 yieldRate,
        uint256 timeElapsed
    ) internal pure returns (uint256 yieldAmount) {
        if (principal == 0 || yieldRate == 0 || timeElapsed == 0) {
            return 0;
        }

        // For very short periods, use linear approximation for gas efficiency
        if (timeElapsed <= LINEAR_THRESHOLD) {
            uint256 annualYield = (principal * yieldRate) / 10000;
            return (annualYield * timeElapsed) / SECONDS_PER_YEAR;
        }

        // For longer periods, use compound interest with efficient approximation
        uint256 daysElapsed = timeElapsed / 1 days;
        if (daysElapsed == 0) {
            // Less than a day, use linear approximation
            uint256 annualYield = (principal * yieldRate) / 10000;
            return (annualYield * timeElapsed) / SECONDS_PER_YEAR;
        }

        // For reasonable periods (up to 2 years), use more precise calculation
        if (daysElapsed > MAX_DAYS) {
            // For very long periods, cap at 2 years to avoid precision issues
            daysElapsed = MAX_DAYS;
        }

        // Use approximation: (1 + r/n)^n ≈ e^r for compound interest
        // For daily compounding: (1 + r/365)^days
        // We'll use Taylor series approximation for efficiency

        // Daily rate in basis points: yieldRate / 365
        uint256 dailyRateBP = yieldRate / 365; // Daily rate in basis points

        // For small daily rates, use Taylor expansion: (1 + x)^n ≈ 1 + nx + n(n-1)x²/2
        // where x = dailyRate and n = days

        uint256 linearTerm = (principal * dailyRateBP * daysElapsed) / 10000;

        // Second order term for better precision: n(n-1)x²/2
        uint256 quadraticTerm = 0;
        if (daysElapsed > 1) {
            // (days * (days-1) * rate² * principal) / (2 * 10000²)
            uint256 rateSquared = (dailyRateBP * dailyRateBP) / 10000;
            quadraticTerm =
                (principal * daysElapsed * (daysElapsed - 1) * rateSquared) /
                (2 * 10000);
        }

        yieldAmount = linearTerm + quadraticTerm;

        // Handle remaining hours in the last partial day
        uint256 remainingSeconds = timeElapsed % 1 days;
        if (remainingSeconds > 0) {
            uint256 newPrincipal = principal + yieldAmount;
            uint256 annualYield = (newPrincipal * yieldRate) / 10000;
            uint256 additionalYield = (annualYield * remainingSeconds) /
                SECONDS_PER_YEAR;
            yieldAmount += additionalYield;
        }
    }

    /**
     * @dev Calculates simple linear yield for a given period
     * @param principal The principal amount
     * @param yieldRate The annual yield rate in basis points
     * @param timeInSeconds The time period in seconds
     * @return uint256 The linear yield amount
     */
    function calculateLinearYield(
        uint256 principal,
        uint256 yieldRate,
        uint256 timeInSeconds
    ) internal pure returns (uint256) {
        if (principal == 0 || yieldRate == 0 || timeInSeconds == 0) {
            return 0;
        }

        uint256 annualYield = (principal * yieldRate) / 10000;
        return (annualYield * timeInSeconds) / SECONDS_PER_YEAR;
    }

    /**
     * @dev Calculates annual yield for a given amount
     * @param amount The principal amount
     * @param yieldRate The annual yield rate in basis points
     * @return uint256 The expected annual yield for the amount
     */
    function calculateAnnualYield(
        uint256 amount,
        uint256 yieldRate
    ) internal pure returns (uint256) {
        return (amount * yieldRate) / 10000;
    }

    /**
     * @dev Calculates projected yield for a specific time period using linear approximation
     * @param amount The principal amount
     * @param yieldRate The annual yield rate in basis points
     * @param timeInSeconds The time period in seconds
     * @return uint256 The projected yield for the period
     */
    function calculateYieldForPeriod(
        uint256 amount,
        uint256 yieldRate,
        uint256 timeInSeconds
    ) internal pure returns (uint256) {
        if (yieldRate == 0) return 0;
        uint256 annualYield = (amount * yieldRate) / 10000;
        return (annualYield * timeInSeconds) / SECONDS_PER_YEAR;
    }

    /**
     * @dev Validates yield rate is within acceptable bounds
     * @param yieldRate The yield rate to validate
     * @param maxYieldRate The maximum allowed yield rate
     * @return bool Whether the yield rate is valid
     */
    function isValidYieldRate(
        uint256 yieldRate,
        uint256 maxYieldRate
    ) internal pure returns (bool) {
        return yieldRate <= maxYieldRate;
    }

    /**
     * @dev Validates withdrawal fee is within acceptable bounds
     * @param withdrawalFee The withdrawal fee to validate
     * @param maxWithdrawalFee The maximum allowed withdrawal fee
     * @return bool Whether the withdrawal fee is valid
     */
    function isValidWithdrawalFee(
        uint256 withdrawalFee,
        uint256 maxWithdrawalFee
    ) internal pure returns (bool) {
        return withdrawalFee <= maxWithdrawalFee;
    }
}
