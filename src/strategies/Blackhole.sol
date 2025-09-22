// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.29;

// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
// import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
// import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
// import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
// import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

// import {INonfungiblePositionManager} from "../interfaces/INonfungiblePositionManager.sol";
// import {IPool} from "../interfaces/IPool.sol";
// import {IGauge} from "../interfaces/IGauge.sol";
// import {TickMath} from "@cryptoalgebra/integral-core/contracts/libraries/TickMath.sol";
// import {LiquidityAmounts} from "@cryptoalgebra/integral-periphery/contracts/libraries/LiquidityAmounts.sol";

// interface IHasTickSpacing {
//     function tickSpacing() external view returns (int24);
// }

// /// @title Blackhole Stable-Stable Vault (USDT/USDC) — 1:1 Parity
// contract Blackhole is ERC20, Ownable, ReentrancyGuard {
//     using SafeERC20 for IERC20;

//     /*//////////////////////////////////////////////////////////////
//                                ERRORS
//     //////////////////////////////////////////////////////////////*/
//     error NotKeeper();
//     error NotSpaced();
//     error TooHigh();
//     error ZeroInput();
//     error SlippageShares();
//     error SlippageOut();
//     error UnbalancedDeposit();
//     error InsufficientIdle();
//     error NoLiquidityAdded();

//     /*//////////////////////////////////////////////////////////////
//                           IMMUTABLE CONFIG
//     //////////////////////////////////////////////////////////////*/
//     IPool public immutable pool;
//     IERC20 public immutable token0;
//     IERC20 public immutable token1;
//     INonfungiblePositionManager public immutable nfpm;

//     uint8 public immutable token0Decimals;
//     uint8 public immutable token1Decimals;

//     /*//////////////////////////////////////////////////////////////
//                              STRATEGY STATE
//     //////////////////////////////////////////////////////////////*/
//     uint256 public tokenId; // NFT actual (0 si no hay)
//     int24 public tickLower;
//     int24 public tickUpper;

//     address public keeper;
//     IGauge public gauge;

//     // Slippage y tolerancias
//     uint256 public maxSlippageBps = 300; // 3%
//     uint256 public depositBalanceToleranceBps = 100; // 1%

//     // Caja objetivo para retiros instantáneos
//     uint256 public idleBps = 1000; // 10%

//     // Fees
//     uint256 public managementFeeBps; // en shares, pro-rata tiempo
//     uint256 public performanceFeeBps; // hook (no-op aquí)
//     uint256 public lastFeeCharge;

//     /*//////////////////////////////////////////////////////////////
//                                  EVENTS
//     //////////////////////////////////////////////////////////////*/
//     event SetKeeper(address keeper);
//     event SetGauge(address gauge);
//     event SetRange(int24 lower, int24 upper);
//     event Harvest(uint256 collected0, uint256 collected1);
//     event Rebalanced(
//         int24 oldLower,
//         int24 oldUpper,
//         int24 newLower,
//         int24 newUpper
//     );
//     event SetMaxSlippage(uint256 bps);
//     event SetIdleBps(uint256 bps);
//     event SetDepositBalanceTolerance(uint256 bps);
//     event SetFees(uint256 mgmtBps, uint256 perfBps);
//     event GaugeStakingFailed(uint256 tokenId);
//     event Deposit(
//         address indexed user,
//         uint256 shares,
//         uint256 used0,
//         uint256 used1
//     );
//     event Withdraw(
//         address indexed user,
//         uint256 shares,
//         uint256 out0,
//         uint256 out1
//     );

//     /*//////////////////////////////////////////////////////////////
//                                 MODIFIERS
//     //////////////////////////////////////////////////////////////*/
//     modifier onlyKeeper() {
//         if (msg.sender != keeper && msg.sender != owner()) revert NotKeeper();
//         _;
//     }

//     /*//////////////////////////////////////////////////////////////
//                                CONSTRUCTOR
//     //////////////////////////////////////////////////////////////*/
//     constructor(
//         address _pool,
//         address _nfpm,
//         string memory _name,
//         string memory _symbol,
//         int24 _tickLower,
//         int24 _tickUpper,
//         address _keeper
//     ) ERC20(_name, _symbol) Ownable(msg.sender) {
//         pool = IPool(_pool);
//         nfpm = INonfungiblePositionManager(_nfpm);
//         token0 = IERC20(pool.token0());
//         token1 = IERC20(pool.token1());
//         token0Decimals = IERC20Metadata(address(token0)).decimals();
//         token1Decimals = IERC20Metadata(address(token1)).decimals();
//         if (token0Decimals != token1Decimals) revert("decimals-mismatch");

//         _assertSpaced(_tickLower, _tickUpper);
//         tickLower = _tickLower;
//         tickUpper = _tickUpper;
//         keeper = _keeper;
//         lastFeeCharge = block.timestamp;

//         emit SetKeeper(_keeper);
//         emit SetRange(_tickLower, _tickUpper);
//     }

//     /*//////////////////////////////////////////////////////////////
//                                   ADMIN
//     //////////////////////////////////////////////////////////////*/
//     function setKeeper(address k) external onlyOwner {
//         keeper = k;
//         emit SetKeeper(k);
//     }

//     function setGauge(address g) external onlyOwner {
//         gauge = IGauge(g);
//         emit SetGauge(g);
//     }

//     function setRange(int24 lower, int24 upper) external onlyKeeper {
//         if (upper <= lower) revert("bad-range");
//         _assertSpaced(lower, upper);
//         tickLower = lower;
//         tickUpper = upper;
//         emit SetRange(lower, upper);
//     }

//     function setMaxSlippageBps(uint256 bps) external onlyOwner {
//         if (bps > 2000) revert TooHigh();
//         maxSlippageBps = bps;
//         emit SetMaxSlippage(bps);
//     }

//     function setDepositBalanceTolerance(uint256 bps) external onlyOwner {
//         if (bps > 2000) revert TooHigh();
//         depositBalanceToleranceBps = bps;
//         emit SetDepositBalanceTolerance(bps);
//     }

//     function setIdleBps(uint256 bps) external onlyOwner {
//         if (bps > 5000) revert TooHigh();
//         idleBps = bps;
//         emit SetIdleBps(bps);
//     }

//     function setFees(uint256 mgmtBps, uint256 perfBps) external onlyOwner {
//         if (mgmtBps > 200 || perfBps > 2000) revert TooHigh();
//         managementFeeBps = mgmtBps;
//         performanceFeeBps = perfBps;
//         emit SetFees(mgmtBps, perfBps);
//     }

//     /*//////////////////////////////////////////////////////////////
//                             USER: DEPOSIT / WITHDRAW
//     //////////////////////////////////////////////////////////////*/

//     /// @notice Depósito dual: paridad 1:1 (USDC≈USDT)
//     function depositDual(
//         uint256 amount0Max,
//         uint256 amount1Max,
//         uint256 minShares
//     )
//         external
//         nonReentrant
//         returns (uint256 sharesMinted, uint256 used0, uint256 used1)
//     {
//         if (amount0Max == 0 && amount1Max == 0) revert ZeroInput();

//         _accrueMgmtFee();

//         // NAV antes
//         (uint256 nav0Before, uint256 nav1Before) = _navBalancesExact();
//         uint256 navBefore = nav0Before + nav1Before;

//         // Pull fondos del usuario al vault
//         if (amount0Max > 0)
//             token0.safeTransferFrom(msg.sender, address(this), amount0Max);
//         if (amount1Max > 0)
//             token1.safeTransferFrom(msg.sender, address(this), amount1Max);

//         // Añadir liquidez (o mintear posición)
//         (used0, used1) = _addLiquidity(amount0Max, amount1Max);
//         if (used0 == 0 && used1 == 0) revert NoLiquidityAdded();

//         // Chequeo de balanceo si ambos lados se usaron
//         if (used0 > 0 && used1 > 0 && depositBalanceToleranceBps > 0) {
//             uint256 mx = used0 > used1 ? used0 : used1;
//             uint256 mn = used0 > used1 ? used1 : used0;
//             uint256 diff = mx - mn;
//             if (diff * 1e4 > mx * depositBalanceToleranceBps)
//                 revert UnbalancedDeposit();
//         }

//         // Devolver sobrantes
//         if (amount0Max > used0)
//             token0.safeTransfer(msg.sender, amount0Max - used0);
//         if (amount1Max > used1)
//             token1.safeTransfer(msg.sender, amount1Max - used1);

//         // === FIX: shares por contribución usada (1:1), sin depender de navAfter-delta ===
//         uint256 contribution = used0 + used1;
//         sharesMinted = totalSupply() == 0
//             ? contribution
//             : (contribution * totalSupply()) / navBefore;
//         if (sharesMinted < minShares) revert SlippageShares();
//         _mint(msg.sender, sharesMinted);

//         // Mantener caja objetivo si aplica
//         if (idleBps > 0) {
//             (uint256 nav0After, uint256 nav1After) = _navBalancesExact();
//             _enforceIdle(nav0After + nav1After);
//         }

//         emit Deposit(msg.sender, sharesMinted, used0, used1);
//     }

//     function withdrawDual(
//         uint256 shares,
//         uint256 minAmount0,
//         uint256 minAmount1,
//         address to
//     ) external nonReentrant returns (uint256 out0, uint256 out1) {
//         return _withdrawCore(shares, minAmount0, minAmount1, 0, 0, to);
//     }

//     function withdrawDualWithMins(
//         uint256 shares,
//         uint256 minAmount0,
//         uint256 minAmount1,
//         uint256 minBurn0,
//         uint256 minBurn1,
//         address to
//     ) external nonReentrant returns (uint256 out0, uint256 out1) {
//         return
//             _withdrawCore(
//                 shares,
//                 minAmount0,
//                 minAmount1,
//                 minBurn0,
//                 minBurn1,
//                 to
//             );
//     }

//     /*//////////////////////////////////////////////////////////////
//                                 KEEPER
//     //////////////////////////////////////////////////////////////*/

//     function harvestAndCompound(
//         uint256 amount0Max,
//         uint256 amount1Max
//     )
//         external
//         onlyKeeper
//         nonReentrant
//         returns (
//             uint256 collected0,
//             uint256 collected1,
//             uint256 used0,
//             uint256 used1
//         )
//     {
//         _accrueMgmtFee();

//         (collected0, collected1) = _collectAll();
//         emit Harvest(collected0, collected1);

//         if (amount0Max > 0 || amount1Max > 0) {
//             (used0, used1) = _addLiquidity(amount0Max, amount1Max);
//         }

//         _chargePerfFee();
//     }

//     function rebalance(
//         int24 newLower,
//         int24 newUpper,
//         uint256 minOut0,
//         uint256 minOut1,
//         uint256 add0,
//         uint256 add1
//     ) external onlyKeeper nonReentrant {
//         if (newUpper <= newLower) revert("bad-range");
//         _assertSpaced(newLower, newUpper);

//         int24 oldL = tickLower;
//         int24 oldU = tickUpper;

//         (uint128 liq, , ) = _positionLiquidity();
//         if (liq > 0) {
//             (uint256 o0, uint256 o1) = _decreaseAndCollectWithMins(
//                 liq,
//                 minOut0,
//                 minOut1
//             );
//             if (o0 < minOut0 || o1 < minOut1) revert SlippageOut();
//         }

//         tickLower = newLower;
//         tickUpper = newUpper;
//         emit Rebalanced(oldL, oldU, newLower, newUpper);

//         if (add0 > 0 || add1 > 0) {
//             _addLiquidity(add0, add1);
//         }
//     }

//     /*//////////////////////////////////////////////////////////////
//                               INTERNAL CORE
//     //////////////////////////////////////////////////////////////*/

//     function _addLiquidity(
//         uint256 amount0Max,
//         uint256 amount1Max
//     ) internal returns (uint256 used0, uint256 used1) {
//         if (amount0Max > 0)
//             token0.safeIncreaseAllowance(address(nfpm), amount0Max);
//         if (amount1Max > 0)
//             token1.safeIncreaseAllowance(address(nfpm), amount1Max);

//         if (tokenId == 0) {
//             INonfungiblePositionManager.MintParams
//                 memory mp = INonfungiblePositionManager.MintParams({
//                     token0: address(token0),
//                     token1: address(token1),
//                     fee: 0,
//                     tickLower: tickLower,
//                     tickUpper: tickUpper,
//                     amount0Desired: amount0Max,
//                     amount1Desired: amount1Max,
//                     amount0Min: (amount0Max * (1e4 - maxSlippageBps)) / 1e4,
//                     amount1Min: (amount1Max * (1e4 - maxSlippageBps)) / 1e4,
//                     recipient: address(this),
//                     deadline: block.timestamp
//                 });
//             (uint256 _id, uint128 liq, uint256 a0, uint256 a1) = nfpm.mint(mp);
//             tokenId = _id;
//             used0 = a0;
//             used1 = a1;
//             if (liq == 0 && used0 == 0 && used1 == 0) revert NoLiquidityAdded();
//             _stakeGaugeIfSet();
//         } else {
//             INonfungiblePositionManager.IncreaseLiquidityParams
//                 memory ip = INonfungiblePositionManager
//                     .IncreaseLiquidityParams({
//                         tokenId: tokenId,
//                         amount0Desired: amount0Max,
//                         amount1Desired: amount1Max,
//                         amount0Min: (amount0Max * (1e4 - maxSlippageBps)) / 1e4,
//                         amount1Min: (amount1Max * (1e4 - maxSlippageBps)) / 1e4,
//                         deadline: block.timestamp
//                     });
//             (uint128 liq, uint256 a0, uint256 a1) = nfpm.increaseLiquidity(ip);
//             used0 = a0;
//             used1 = a1;
//             if (liq == 0 && used0 == 0 && used1 == 0) revert NoLiquidityAdded();
//         }

//         // reset approvals (higiene)
//         if (amount0Max > 0) token0.forceApprove(address(nfpm), 0);
//         if (amount1Max > 0) token1.forceApprove(address(nfpm), 0);
//     }

//     function _withdrawCore(
//         uint256 shares,
//         uint256 minAmount0,
//         uint256 minAmount1,
//         uint256 minBurn0,
//         uint256 minBurn1,
//         address to
//     ) internal returns (uint256 out0, uint256 out1) {
//         if (shares == 0) revert ZeroInput();
//         uint256 ts = totalSupply();
//         if (ts == 0) revert("no-supply");

//         (uint256 nav0, uint256 nav1) = _navBalancesExact();
//         uint256 target0 = (nav0 * shares) / ts;
//         uint256 target1 = (nav1 * shares) / ts;

//         // idle primero
//         uint256 idle0 = token0.balanceOf(address(this));
//         uint256 idle1 = token1.balanceOf(address(this));
//         out0 = target0 <= idle0 ? target0 : idle0;
//         out1 = target1 <= idle1 ? target1 : idle1;

//         if (out0 < target0 || out1 < target1) {
//             (uint128 liq, , ) = _positionLiquidity();
//             if (liq > 0) {
//                 uint128 liqToBurn = uint128((uint256(liq) * shares) / ts);
//                 _decreaseAndCollectWithMins(liqToBurn, minBurn0, minBurn1);
//             }
//             // completa desde idle post-collect
//             uint256 idle0b = token0.balanceOf(address(this));
//             uint256 idle1b = token1.balanceOf(address(this));
//             uint256 need0 = target0 - out0;
//             uint256 need1 = target1 - out1;
//             uint256 add0 = need0 <= idle0b ? need0 : idle0b;
//             uint256 add1 = need1 <= idle1b ? need1 : idle1b;
//             out0 += add0;
//             out1 += add1;
//         }

//         if (out0 < minAmount0 || out1 < minAmount1) revert SlippageOut();

//         _burn(msg.sender, shares);
//         if (out0 > 0) token0.safeTransfer(to, out0);
//         if (out1 > 0) token1.safeTransfer(to, out1);

//         emit Withdraw(msg.sender, shares, out0, out1);
//     }

//     function _decreaseAndCollectWithMins(
//         uint128 liqToBurn,
//         uint256 minOut0,
//         uint256 minOut1
//     ) internal returns (uint256 out0, uint256 out1) {
//         if (tokenId == 0) return (0, 0);
//         INonfungiblePositionManager.DecreaseLiquidityParams
//             memory dp = INonfungiblePositionManager.DecreaseLiquidityParams({
//                 tokenId: tokenId,
//                 liquidity: liqToBurn,
//                 amount0Min: minOut0,
//                 amount1Min: minOut1,
//                 deadline: block.timestamp
//             });
//         nfpm.decreaseLiquidity(dp);

//         INonfungiblePositionManager.CollectParams
//             memory cp = INonfungiblePositionManager.CollectParams({
//                 tokenId: tokenId,
//                 recipient: address(this),
//                 amount0Max: type(uint128).max,
//                 amount1Max: type(uint128).max
//             });
//         (out0, out1) = nfpm.collect(cp);
//     }

//     function _collectAll() internal returns (uint256 out0, uint256 out1) {
//         if (tokenId == 0) return (0, 0);
//         INonfungiblePositionManager.CollectParams
//             memory cp = INonfungiblePositionManager.CollectParams({
//                 tokenId: tokenId,
//                 recipient: address(this),
//                 amount0Max: type(uint128).max,
//                 amount1Max: type(uint128).max
//             });
//         (out0, out1) = nfpm.collect(cp);
//     }

//     function _positionLiquidity()
//         internal
//         view
//         returns (uint128 liq, int24 lower, int24 upper)
//     {
//         if (tokenId == 0) return (0, tickLower, tickUpper);
//         (, , , , , , , uint128 _liquidity, , , , ) = nfpm.positions(tokenId);
//         return (_liquidity, tickLower, tickUpper);
//     }

//     function _stakeGaugeIfSet() internal {
//         if (address(gauge) != address(0) && tokenId != 0) {
//             nfpm.approve(address(gauge), tokenId);
//             try gauge.deposit(tokenId) {} catch {
//                 emit GaugeStakingFailed(tokenId);
//             }
//         }
//     }

//     /*//////////////////////////////////////////////////////////////
//                                 FEES
//     //////////////////////////////////////////////////////////////*/
//     function _accrueMgmtFee() internal {
//         if (managementFeeBps == 0) {
//             lastFeeCharge = block.timestamp;
//             return;
//         }
//         uint256 ts = totalSupply();
//         if (ts == 0) {
//             lastFeeCharge = block.timestamp;
//             return;
//         }
//         uint256 elapsed = block.timestamp - lastFeeCharge;
//         if (elapsed == 0) return;
//         uint256 feeShares = (ts * managementFeeBps * elapsed) /
//             (1e4 * 365 days);
//         if (feeShares > 0) _mint(owner(), feeShares);
//         lastFeeCharge = block.timestamp;
//     }

//     function _chargePerfFee() internal {
//         if (performanceFeeBps == 0) return;
//         // hook opcional (noop)
//     }

//     /*//////////////////////////////////////////////////////////////
//                             NAV (PARIDAD 1:1) EXACTO
//     //////////////////////////////////////////////////////////////*/
//     function _navBalancesExact()
//         internal
//         view
//         returns (uint256 nav0, uint256 nav1)
//     {
//         // idle
//         nav0 = token0.balanceOf(address(this));
//         nav1 = token1.balanceOf(address(this));

//         if (tokenId != 0) {
//             (
//                 ,
//                 ,
//                 ,
//                 ,
//                 ,
//                 int24 posLower,
//                 int24 posUpper,
//                 uint128 liq,
//                 ,
//                 ,
//                 uint128 owed0,
//                 uint128 owed1
//             ) = nfpm.positions(tokenId);

//             nav0 += owed0;
//             nav1 += owed1;

//             if (liq > 0) {
//                 (uint160 sqrtP, , , , , , ) = pool.globalState();
//                 uint160 sa = TickMath.getSqrtRatioAtTick(posLower);
//                 uint160 sb = TickMath.getSqrtRatioAtTick(posUpper);
//                 (uint256 amt0, uint256 amt1) = LiquidityAmounts
//                     .getAmountsForLiquidity(sqrtP, sa, sb, liq);
//                 nav0 += amt0;
//                 nav1 += amt1;
//             }
//         }
//     }

//     function navBalances() external view returns (uint256 nav0, uint256 nav1) {
//         return _navBalancesExact();
//     }

//     /*//////////////////////////////////////////////////////////////
//                                HELPERS
//     //////////////////////////////////////////////////////////////*/
//     function _assertSpaced(int24 lower, int24 upper) internal view {
//         int24 spacing = IHasTickSpacing(address(pool)).tickSpacing();
//         if (lower % spacing != 0 || upper % spacing != 0) revert NotSpaced();
//     }

//     function _enforceIdle(uint256 navAfter) internal view {
//         uint256 requiredIdle = (navAfter * idleBps) / 1e4;
//         uint256 currentIdle = token0.balanceOf(address(this)) +
//             token1.balanceOf(address(this));
//         if (currentIdle < requiredIdle) revert InsufficientIdle();
//     }

//     function positionLiquidity()
//         external
//         view
//         returns (uint128 liq, int24 lower, int24 upper)
//     {
//         return _positionLiquidity();
//     }
// }
