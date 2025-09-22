// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./base/VaultAccessControl.sol";
import "./base/VaultCore.sol";
import "./base/VaultFees.sol";
import "./libraries/YieldMath.sol";

/// @title Vault Contract
/// @notice This contract implements an ERC4626 vault with modular architecture
/// @dev Extends ERC4626 for vault functionality and inherits from modular base contracts
contract Vault is
    VaultAccessControl,
    VaultCore,
    VaultFees,
    ERC4626,
    ReentrancyGuard,
    Pausable
{
    using SafeERC20 for IERC20;
    using YieldMath for uint256;

    // ============ State Variables ============
    // Yield state is now inherited from VaultCore

    // ============ Events ============
    event YieldAccrued(uint256 yieldAmount, uint256 totalAssets);
    event YieldRateUpdated(uint256 oldRate, uint256 newRate);

    // ============ Errors ============
    /// @dev Thrown when yield rate exceeds maximum allowed
    error YieldRateTooHigh();

    /// @dev Thrown when trying to withdraw more than available balance
    error InsufficientFunds();

    /// @dev Thrown when invalid parameters are provided
    error InvalidParameters();

    // ============ Constructor ============
    /// @notice Initializes the vault with the underlying asset and token details
    /// @dev Sets up initial roles and initializes ERC4626 and ERC20
    /// @param _asset The underlying ERC20 token
    /// @param _name Name of the vault token
    /// @param _symbol Symbol of the vault token
    /// @param manager The initial manager address
    /// @param agent The initial agent address
    /// @param _withdrawalFee Withdrawal fee in basis points (max 1000 = 10%)
    /// @param _yieldRate Annual yield rate in basis points (max 2000 = 20%)
    /// @param _treasury Treasury address for fee collection
    constructor(
        IERC20 _asset,
        string memory _name,
        string memory _symbol,
        address manager,
        address agent,
        uint256 _withdrawalFee,
        uint256 _yieldRate,
        address _treasury
    )
        ERC4626(_asset)
        ERC20(_name, _symbol)
        VaultAccessControl(msg.sender, manager, agent)
        VaultFees(_withdrawalFee, _treasury)
    {
        if (!YieldMath.isValidYieldRate(_yieldRate, MAX_YIELD_RATE))
            revert YieldRateTooHigh();

        yieldRate = _yieldRate;
        lastYieldUpdate = block.timestamp;
        accruedYield = 0;
        baseAssets = 0;
    }

    // ============ Override Modifiers ============
    /// @dev Override the VaultCore modifier to use VaultAccessControl
    modifier onlyManager() override(VaultAccessControl, VaultCore, VaultFees) {
        require(
            hasRole(MANAGER_ROLE, msg.sender),
            "Vault: caller is not a manager"
        );
        _;
    }

    /// @dev Override the VaultCore modifier to use VaultAccessControl
    modifier onlyAgent() override(VaultAccessControl, VaultCore) {
        require(
            hasRole(AGENT_ROLE, msg.sender),
            "Vault: caller is not an agent"
        );
        _;
    }

    /// @dev Implementation of VaultCore modifiers using OpenZeppelin contracts
    modifier nonReentrantVault() override {
        _;
    }

    modifier whenVaultNotPaused() override {
        _;
    }

    // ============ Yield Functions ============
    /**
     * @notice Updates the accrued yield based on time elapsed since last update
     * @dev This function should be called before any deposit/withdrawal to ensure accurate yield calculation
     * @dev Uses YieldMath library for efficient compound interest calculations
     */
    function updateYield() public {
        if (baseAssets == 0 || yieldRate == 0) {
            lastYieldUpdate = block.timestamp;
            return;
        }

        uint256 timeElapsed = block.timestamp - lastYieldUpdate;
        if (timeElapsed == 0) return;

        uint256 currentTotalAssets = baseAssets + accruedYield;
        uint256 yieldForPeriod = YieldMath.computeYield(
            currentTotalAssets,
            yieldRate,
            timeElapsed
        );

        accruedYield += yieldForPeriod;
        lastYieldUpdate = block.timestamp;

        emit YieldAccrued(yieldForPeriod, currentTotalAssets + yieldForPeriod);
    }

    /**
     * @notice Calculates the pending yield that would be accrued if updateYield() was called now
     * @dev View function that doesn't modify state, safe to call anytime
     * @return pendingYield The amount of yield that can be accrued
     */
    function calculatePendingYield()
        public
        view
        override
        returns (uint256 pendingYield)
    {
        if (baseAssets == 0 || yieldRate == 0) {
            return 0;
        }

        uint256 timeElapsed = block.timestamp - lastYieldUpdate;
        uint256 currentTotalAssets = baseAssets + accruedYield;
        pendingYield = YieldMath.computeYield(
            currentTotalAssets,
            yieldRate,
            timeElapsed
        );
    }

    /**
     * @notice Sets a new yield rate (only callable by manager)
     * @dev Updates yield before changing rate to ensure accurate calculations
     * @param newYieldRate The new yield rate in basis points (max 5000 = 50%)
     * @custom:security Only MANAGER_ROLE can call this function
     */
    function setYieldRate(uint256 newYieldRate) external onlyManager {
        if (!YieldMath.isValidYieldRate(newYieldRate, MAX_YIELD_RATE))
            revert YieldRateTooHigh();

        updateYield();

        uint256 oldRate = yieldRate;
        yieldRate = newYieldRate;

        emit YieldRateUpdated(oldRate, newYieldRate);
    }

    // ============ Pause Functions ============
    /**
     * @dev Pauses the vault, stopping deposits and withdrawals
     * @notice Only callable by addresses with PAUSER_ROLE
     */
    function pause() external onlyPauser {
        _pause();
    }

    /**
     * @dev Unpauses the vault, allowing deposits and withdrawals
     * @notice Only callable by addresses with PAUSER_ROLE
     */
    function unpause() external onlyPauser {
        _unpause();
    }

    // ============ ERC4626 Functions ============
    /**
     * @dev Returns the total amount of assets held by the vault including accrued yield
     * @return Total assets including yield
     */
    function totalAssets() public view override returns (uint256) {
        return baseAssets + accruedYield + calculatePendingYield();
    }

    /**
     * @dev See {IERC4626-deposit}
     * @dev Updates yield before processing deposit
     */
    function deposit(
        uint256 assets,
        address receiver
    ) public override nonReentrant whenNotPaused returns (uint256) {
        updateYield();
        uint256 shares = super.deposit(assets, receiver);
        baseAssets += assets;
        return shares;
    }

    /**
     * @dev See {IERC4626-mint}
     * @dev Updates yield before processing mint
     */
    function mint(
        uint256 shares,
        address receiver
    ) public override nonReentrant whenNotPaused returns (uint256) {
        updateYield();
        uint256 actualAssets = super.mint(shares, receiver);
        baseAssets += actualAssets;
        return actualAssets;
    }

    /**
     * @dev See {IERC4626-withdraw}
     * @dev Updates yield and charges withdrawal fee on the assets being withdrawn
     */
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public override nonReentrant whenNotPaused returns (uint256) {
        updateYield();

        uint256 feeAmount = (assets * withdrawalFee) / 10000;
        uint256 netAssets = assets - feeAmount;

        uint256 shares = super.withdraw(netAssets, receiver, owner);
        _updateAssetsOnWithdrawal(assets);

        if (feeAmount > 0) {
            emit WithdrawalFeeCollected(owner, feeAmount);
        }

        return shares;
    }

    /**
     * @dev See {IERC4626-redeem}
     * @dev Updates yield and charges withdrawal fee on the assets being redeemed
     */
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public override nonReentrant whenNotPaused returns (uint256) {
        updateYield();

        uint256 assets = previewRedeem(shares);
        uint256 feeAmount = (assets * withdrawalFee) / 10000;
        uint256 netAssets = assets - feeAmount;

        super.redeem(shares, address(this), owner);
        IERC20(asset()).safeTransfer(receiver, netAssets);
        _updateAssetsOnWithdrawal(assets);

        if (feeAmount > 0) {
            emit WithdrawalFeeCollected(owner, feeAmount);
        }

        return netAssets;
    }

    /**
     * @dev Internal function to update baseAssets and accruedYield proportionally on withdrawal
     * @param withdrawnAssets Total assets being withdrawn (including fees)
     */
    function _updateAssetsOnWithdrawal(uint256 withdrawnAssets) internal {
        uint256 totalAssetsBeforeWithdrawal = baseAssets + accruedYield;

        if (totalAssetsBeforeWithdrawal == 0) return;

        uint256 baseReduction = (baseAssets * withdrawnAssets) /
            totalAssetsBeforeWithdrawal;
        uint256 yieldReduction = (accruedYield * withdrawnAssets) /
            totalAssetsBeforeWithdrawal;

        baseReduction = baseReduction > baseAssets ? baseAssets : baseReduction;
        yieldReduction = yieldReduction > accruedYield
            ? accruedYield
            : yieldReduction;

        baseAssets -= baseReduction;
        accruedYield -= yieldReduction;
    }

    // ============ Internal Functions ============
    /**
     * @dev Internal function to check owner access for VaultFees
     */
    function _requireOwner() internal view override {
        require(msg.sender == owner(), "Vault: not owner");
    }

    /**
     * @dev Internal function to check owner or manager access for VaultFees
     */
    function _requireOwnerOrManager() internal view override {
        require(
            msg.sender == owner() || hasRole(MANAGER_ROLE, msg.sender),
            "Vault: not owner/manager"
        );
    }

    // ============ View Functions ============
    /**
     * @dev Returns the current yield rate in basis points
     * @return uint256 The yield rate (10000 = 100%)
     */
    function getYieldRate() external view returns (uint256) {
        return yieldRate;
    }

    /**
     * @dev Returns the total yield accrued (both distributed and pending)
     * @return uint256 The total accrued yield including pending
     */
    function getTotalAccruedYield() external view returns (uint256) {
        return accruedYield + calculatePendingYield();
    }

    /**
     * @dev Returns the timestamp of the last yield update
     * @return uint256 The last update timestamp
     */
    function getLastYieldUpdate() external view returns (uint256) {
        return lastYieldUpdate;
    }

    /**
     * @dev Calculates the annual percentage yield (APY) for a given amount
     * @param amount The principal amount
     * @return uint256 The expected annual yield for the amount
     */
    function calculateAnnualYield(
        uint256 amount
    ) external view returns (uint256) {
        return YieldMath.calculateAnnualYield(amount, yieldRate);
    }

    /**
     * @dev Calculates projected yield for a specific time period
     * @param amount The principal amount
     * @param timeInSeconds The time period in seconds
     * @return uint256 The projected yield for the period
     */
    function calculateYieldForPeriod(
        uint256 amount,
        uint256 timeInSeconds
    ) external view returns (uint256) {
        return
            YieldMath.calculateYieldForPeriod(amount, yieldRate, timeInSeconds);
    }

    // ============ Override Functions ============
    /// @dev Returns the underlying asset address
    function asset()
        public
        view
        override(ERC4626, VaultCore, VaultFees)
        returns (address)
    {
        return ERC4626.asset();
    }

    /// @dev Returns the base assets amount (principal deposits minus withdrawals)
    function getBaseAssets() public view override returns (uint256) {
        return baseAssets;
    }

    /// @dev Returns the accrued yield amount
    function getAccruedYield() public view override returns (uint256) {
        return accruedYield;
    }
}
