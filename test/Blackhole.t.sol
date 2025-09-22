// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.20;

// import "forge-std/Test.sol";
// import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
// import {console} from "forge-std/console.sol";

// import {Blackhole} from "../src/strategies/Blackhole.sol";
// import {TickMath} from "@cryptoalgebra/integral-core/contracts/libraries/TickMath.sol";
// import {LiquidityAmounts} from "@cryptoalgebra/integral-periphery/contracts/libraries/LiquidityAmounts.sol";

// // ================== Interfaces mínimas ======================
// interface IPool {
//     function token0() external view returns (address);

//     function token1() external view returns (address);

//     function globalState()
//         external
//         view
//         returns (
//             uint160 sqrtPriceX96,
//             int24 tick,
//             uint16 lastFee,
//             uint8 pluginConfig,
//             uint128 activeLiquidity,
//             int24 nextTick,
//             int24 prevTick
//         );
// }

// interface INonfungiblePositionManager {
//     struct MintParams {
//         address token0;
//         address token1;
//         uint24 fee; // ignorado en Algebra
//         int24 tickLower;
//         int24 tickUpper;
//         uint256 amount0Desired;
//         uint256 amount1Desired;
//         uint256 amount0Min;
//         uint256 amount1Min;
//         address recipient;
//         uint256 deadline;
//     }
//     struct IncreaseLiquidityParams {
//         uint256 tokenId;
//         uint256 amount0Desired;
//         uint256 amount1Desired;
//         uint256 amount0Min;
//         uint256 amount1Min;
//         uint256 deadline;
//     }
//     struct DecreaseLiquidityParams {
//         uint256 tokenId;
//         uint128 liquidity;
//         uint256 amount0Min;
//         uint256 amount1Min;
//         uint256 deadline;
//     }
//     struct CollectParams {
//         uint256 tokenId;
//         address recipient;
//         uint128 amount0Max;
//         uint128 amount1Max;
//     }

//     function mint(
//         MintParams calldata
//     )
//         external
//         returns (
//             uint256 tokenId,
//             uint128 liquidity,
//             uint256 amount0,
//             uint256 amount1
//         );

//     function increaseLiquidity(
//         IncreaseLiquidityParams calldata
//     ) external returns (uint128 liquidity, uint256 amount0, uint256 amount1);

//     function decreaseLiquidity(DecreaseLiquidityParams calldata) external;

//     function collect(
//         CollectParams calldata
//     ) external returns (uint256 amount0, uint256 amount1);

//     function positions(
//         uint256 tokenId
//     )
//         external
//         view
//         returns (
//             uint96 nonce,
//             address operator,
//             address _token0,
//             address _token1,
//             uint24 fee,
//             int24 tickLower,
//             int24 tickUpper,
//             uint128 liquidity,
//             uint256 feeGrowthInside0LastX128,
//             uint256 feeGrowthInside1LastX128,
//             uint128 tokensOwed0,
//             uint128 tokensOwed1
//         );

//     function approve(address to, uint256 tokenId) external;
// }

// interface IGauge {
//     function deposit(uint256 tokenId) external;

//     function isDeposited(uint256 tokenId) external view returns (bool);
// }

// // ========================= Mocks ============================

// contract MockERC20 is ERC20 {
//     uint8 private _dec;

//     constructor(string memory n, string memory s, uint8 d) ERC20(n, s) {
//         _dec = d;
//     }

//     function decimals() public view override returns (uint8) {
//         return _dec;
//     }

//     function mint(address to, uint256 amt) external {
//         _mint(to, amt);
//     }
// }

// contract MockPool is IPool {
//     address public immutable t0;
//     address public immutable t1;
//     // Paridad: sqrt(1)*2^96
//     uint160 public sqrtPriceX96 = 79228162514264337593543950336;
//     int24 public tick = 0;

//     constructor(address _t0, address _t1) {
//         t0 = _t0;
//         t1 = _t1;
//     }

//     function token0() external view returns (address) {
//         return t0;
//     }

//     function token1() external view returns (address) {
//         return t1;
//     }

//     function setPrice(uint160 sp, int24 _tick) external {
//         sqrtPriceX96 = sp;
//         tick = _tick;
//     }

//     function globalState()
//         external
//         view
//         returns (uint160, int24, uint16, uint8, uint128, int24, int24)
//     {
//         return (sqrtPriceX96, tick, 0, 0, 0, 0, 0);
//     }

//     // Para compatibilidad con IHasTickSpacing
//     function tickSpacing() external pure returns (int24) {
//         return 60;
//     }
// }

// contract MockGauge is IGauge {
//     mapping(uint256 => bool) public dep;

//     function deposit(uint256 tokenId) external {
//         dep[tokenId] = true;
//     }

//     function isDeposited(uint256 tokenId) external view returns (bool) {
//         return dep[tokenId];
//     }
// }

// contract MockNFPM is INonfungiblePositionManager {
//     MockERC20 public immutable t0;
//     MockERC20 public immutable t1;
//     MockPool public immutable pool;

//     uint256 public nextId = 1;

//     struct Pos {
//         uint128 liq;
//         int24 lower;
//         int24 upper;
//         uint128 owed0;
//         uint128 owed1;
//         address owner; // vault (recipient)
//     }
//     mapping(uint256 => Pos) public pos;

//     constructor(address _t0, address _t1, address _pool) {
//         t0 = MockERC20(_t0);
//         t1 = MockERC20(_t1);
//         pool = MockPool(_pool);
//     }

//     function _bounds(
//         Pos storage ps
//     ) internal view returns (uint160 sqrtP, uint160 sa, uint160 sb) {
//         (sqrtP, , , , , , ) = pool.globalState();
//         sa = TickMath.getSqrtRatioAtTick(ps.lower);
//         sb = TickMath.getSqrtRatioAtTick(ps.upper);
//     }

//     function _boundsTicks(
//         int24 lower,
//         int24 upper
//     ) internal view returns (uint160 sqrtP, uint160 sa, uint160 sb) {
//         (sqrtP, , , , , , ) = pool.globalState();
//         sa = TickMath.getSqrtRatioAtTick(lower);
//         sb = TickMath.getSqrtRatioAtTick(upper);
//     }

//     function _computeUsedAndL(
//         int24 lower,
//         int24 upper,
//         uint256 a0Desired,
//         uint256 a1Desired
//     ) internal view returns (uint128 L, uint256 used0, uint256 used1) {
//         (uint160 sqrtP, uint160 sa, uint160 sb) = _boundsTicks(lower, upper);
//         L = uint128(
//             LiquidityAmounts.getLiquidityForAmounts(
//                 sqrtP,
//                 sa,
//                 sb,
//                 a0Desired,
//                 a1Desired
//             )
//         );
//         if (L == 0) return (0, 0, 0);
//         (used0, used1) = LiquidityAmounts.getAmountsForLiquidity(
//             sqrtP,
//             sa,
//             sb,
//             L
//         );
//         if (used0 > a0Desired) used0 = a0Desired;
//         if (used1 > a1Desired) used1 = a1Desired;
//     }

//     // === FIX: cobrar SIEMPRE del caller (el vault), coherente con approve del vault ===
//     function mint(
//         MintParams calldata p
//     )
//         external
//         returns (
//             uint256 tokenId,
//             uint128 liquidity,
//             uint256 amount0,
//             uint256 amount1
//         )
//     {
//         (uint128 L, uint256 used0, uint256 used1) = _computeUsedAndL(
//             p.tickLower,
//             p.tickUpper,
//             p.amount0Desired,
//             p.amount1Desired
//         );

//         require(used0 >= p.amount0Min, "amount0<min");
//         require(used1 >= p.amount1Min, "amount1<min");

//         if (used0 > 0)
//             require(t0.transferFrom(msg.sender, address(this), used0), "t0 tf");
//         if (used1 > 0)
//             require(t1.transferFrom(msg.sender, address(this), used1), "t1 tf");

//         tokenId = nextId++;
//         liquidity = L;
//         pos[tokenId] = Pos({
//             liq: L,
//             lower: p.tickLower,
//             upper: p.tickUpper,
//             owed0: 0,
//             owed1: 0,
//             owner: p.recipient
//         });

//         amount0 = used0;
//         amount1 = used1;
//     }

//     function increaseLiquidity(
//         IncreaseLiquidityParams calldata p
//     ) external returns (uint128 liquidity, uint256 amount0, uint256 amount1) {
//         Pos storage ps = pos[p.tokenId];
//         require(ps.owner != address(0), "no-pos");

//         (uint128 addL, uint256 used0, uint256 used1) = _computeUsedAndL(
//             ps.lower,
//             ps.upper,
//             p.amount0Desired,
//             p.amount1Desired
//         );

//         require(used0 >= p.amount0Min, "inc0<min");
//         require(used1 >= p.amount1Min, "inc1<min");

//         if (used0 > 0)
//             require(t0.transferFrom(msg.sender, address(this), used0), "t0 tf");
//         if (used1 > 0)
//             require(t1.transferFrom(msg.sender, address(this), used1), "t1 tf");

//         ps.liq += addL;

//         liquidity = addL;
//         amount0 = used0;
//         amount1 = used1;
//     }

//     function decreaseLiquidity(DecreaseLiquidityParams calldata p) external {
//         Pos storage ps = pos[p.tokenId];
//         require(ps.owner != address(0), "no-pos");
//         require(p.liquidity <= ps.liq, "too-much");

//         (uint160 sqrtP, uint160 sa, uint160 sb) = _bounds(ps);
//         (uint256 amt0, uint256 amt1) = LiquidityAmounts.getAmountsForLiquidity(
//             sqrtP,
//             sa,
//             sb,
//             p.liquidity
//         );

//         require(amt0 >= p.amount0Min, "dec0<min");
//         require(amt1 >= p.amount1Min, "dec1<min");

//         ps.owed0 += uint128(amt0);
//         ps.owed1 += uint128(amt1);
//         ps.liq -= p.liquidity;

//         // Asegura balance suficiente para colectar todo lo owed
//         uint256 b0 = t0.balanceOf(address(this));
//         uint256 b1 = t1.balanceOf(address(this));
//         if (b0 < ps.owed0) t0.mint(address(this), ps.owed0 - b0);
//         if (b1 < ps.owed1) t1.mint(address(this), ps.owed1 - b1);
//     }

//     function collect(
//         CollectParams calldata p
//     ) external returns (uint256 amount0, uint256 amount1) {
//         Pos storage ps = pos[p.tokenId];
//         amount0 = ps.owed0;
//         amount1 = ps.owed1;

//         if (amount0 > 0) {
//             require(t0.transfer(p.recipient, amount0), "t0 pay");
//             ps.owed0 = 0;
//         }
//         if (amount1 > 0) {
//             require(t1.transfer(p.recipient, amount1), "t1 pay");
//             ps.owed1 = 0;
//         }
//     }

//     function positions(
//         uint256 tokenId
//     )
//         external
//         view
//         returns (
//             uint96,
//             address,
//             address,
//             address,
//             uint24,
//             int24,
//             int24,
//             uint128,
//             uint256,
//             uint256,
//             uint128,
//             uint128
//         )
//     {
//         Pos storage ps = pos[tokenId];
//         return (
//             0,
//             address(0),
//             address(t0),
//             address(t1),
//             0,
//             ps.lower,
//             ps.upper,
//             ps.liq,
//             0,
//             0,
//             ps.owed0,
//             ps.owed1
//         );
//     }

//     function approve(address, uint256) external {
//         /* noop */
//     }

//     // Simula fees
//     function addFees(uint256 tokenId, uint256 f0, uint256 f1) external {
//         if (f0 > 0) t0.mint(address(this), f0);
//         if (f1 > 0) t1.mint(address(this), f1);
//         pos[tokenId].owed0 += uint128(f0);
//         pos[tokenId].owed1 += uint128(f1);
//     }
// }

// // ====================== TEST SUITE ==========================

// contract BlackholeVaultTest is Test {
//     address public keeper = address(0xBEEF);
//     address public alice = address(0xA11CE);
//     address public bob = address(0xB0B);

//     MockERC20 public token0; // USDC
//     MockERC20 public token1; // USDT
//     MockPool public pool;
//     MockNFPM public nfpm;
//     MockGauge public gauge;
//     Blackhole public vault;

//     uint8 constant DEC = 6;
//     uint256 constant ONE = 10 ** DEC;
//     uint256 constant INIT = 1_000_000 * ONE;

//     address internal vaultOwner;

//     function _encodeError(
//         string memory signature
//     ) internal pure returns (bytes memory) {
//         return abi.encodeWithSignature(signature);
//     }

//     function setUp() public {
//         token0 = new MockERC20("USD Coin", "USDC", DEC);
//         token1 = new MockERC20("Tether USD", "USDT", DEC);
//         pool = new MockPool(address(token0), address(token1));
//         nfpm = new MockNFPM(address(token0), address(token1), address(pool));
//         gauge = new MockGauge();

//         vault = new Blackhole(
//             address(pool),
//             address(nfpm),
//             "Blackhole Vault",
//             "BLACK",
//             -120,
//             120,
//             keeper
//         );

//         vaultOwner = vault.owner();

//         // Ajustes de test
//         vm.prank(vaultOwner);
//         vault.setIdleBps(0);
//         vm.prank(vaultOwner);
//         vault.setMaxSlippageBps(2000);
//         vm.prank(vaultOwner);
//         vault.setDepositBalanceTolerance(0);

//         // Fondos y approvals
//         token0.mint(alice, INIT);
//         token1.mint(alice, INIT);
//         token0.mint(bob, INIT);
//         token1.mint(bob, INIT);

//         vm.startPrank(alice);
//         token0.approve(address(vault), type(uint256).max);
//         token1.approve(address(vault), type(uint256).max);
//         vm.stopPrank();

//         vm.startPrank(bob);
//         token0.approve(address(vault), type(uint256).max);
//         token1.approve(address(vault), type(uint256).max);
//         vm.stopPrank();
//     }

//     // ---- constructor & admin ----
//     function test_constructor_sets_state() public {
//         assertEq(vault.name(), "Blackhole Vault");
//         assertEq(vault.symbol(), "BLACK");
//         assertEq(address(vault.token0()), address(token0));
//         assertEq(address(vault.token1()), address(token1));
//         assertEq(vault.tickLower(), -120);
//         assertEq(vault.tickUpper(), 120);
//         assertEq(vault.keeper(), keeper);
//     }

//     function test_admin_setters_access() public {
//         vm.prank(vaultOwner);
//         vault.setKeeper(address(0xCAFE));
//         assertEq(vault.keeper(), address(0xCAFE));

//         vm.prank(vaultOwner);
//         vault.setGauge(address(gauge));
//         assertEq(address(vault.gauge()), address(gauge));

//         vm.prank(vault.keeper());
//         vault.setRange(-180, 180);
//         assertEq(vault.tickLower(), -180);
//         assertEq(vault.tickUpper(), 180);

//         vm.expectRevert(_encodeError("NotKeeper()"));
//         vm.prank(alice);
//         vault.setRange(-240, 240);

//         vm.prank(vault.keeper());
//         vm.expectRevert(bytes("bad-range"));
//         vault.setRange(100, -100);
//     }

//     // ---- deposits ----
//     function test_deposit_first_mints_shares() public {
//         vm.startPrank(alice);
//         (uint256 sh, uint256 u0, uint256 u1) = vault.depositDual(
//             1_000 * ONE,
//             1_000 * ONE,
//             0
//         );
//         vm.stopPrank();

//         assertGt(sh, 0);
//         assertGt(u0, 0);
//         assertGt(u1, 0);
//         assertEq(vault.totalSupply(), sh);
//         assertEq(vault.balanceOf(alice), sh);
//     }

//     function test_deposit_second_proportional() public {
//         vm.startPrank(alice);
//         (uint256 shA, , ) = vault.depositDual(1_000 * ONE, 1_000 * ONE, 0);
//         vm.stopPrank();

//         vm.startPrank(bob);
//         (uint256 shB, , ) = vault.depositDual(500 * ONE, 500 * ONE, 0);
//         vm.stopPrank();

//         assertApproxEqRel(shB * 2, shA, 0.01e18);
//     }

//     function test_deposit_single_sided_possible_by_range() public {
//         vm.prank(vault.keeper());
//         vault.setRange(60, 600);

//         vm.startPrank(alice);
//         (uint256 sh, uint256 u0, uint256 u1) = vault.depositDual(
//             2_000 * ONE,
//             1,
//             0
//         );
//         vm.stopPrank();

//         assertGt(sh, 0);
//         assertGt(u0, 0);
//         assertEq(u1, 0);
//     }

//     function test_deposit_zero_input_reverts() public {
//         vm.startPrank(alice);
//         vm.expectRevert(_encodeError("ZeroInput()"));
//         vault.depositDual(0, 0, 0);
//         vm.stopPrank();
//     }

//     // ---- withdraws ----
//     function test_withdraw_full_roundtrip() public {
//         vm.startPrank(alice);
//         (uint256 sh, , ) = vault.depositDual(2_000 * ONE, 2_000 * ONE, 0);

//         uint256 b0Before = token0.balanceOf(alice);
//         uint256 b1Before = token1.balanceOf(alice);

//         (uint256 o0, uint256 o1) = vault.withdrawDual(sh, 0, 0, alice);
//         vm.stopPrank();

//         assertGt(o0 + o1, 3_800 * ONE);
//         assertEq(token0.balanceOf(alice), b0Before + o0);
//         assertEq(token1.balanceOf(alice), b1Before + o1);
//         assertEq(vault.balanceOf(alice), 0);
//     }

//     function test_withdraw_partial() public {
//         vm.startPrank(alice);
//         (uint256 sh, , ) = vault.depositDual(2_000 * ONE, 2_000 * ONE, 0);
//         (uint256 o0, uint256 o1) = vault.withdrawDual(sh / 2, 0, 0, alice);
//         vm.stopPrank();

//         assertGt(o0 + o1, 1_800 * ONE);
//         assertEq(vault.balanceOf(alice), sh - sh / 2);
//     }

//     function test_withdraw_with_min_slippage_guard() public {
//         vm.startPrank(alice);
//         (uint256 sh, , ) = vault.depositDual(1_000 * ONE, 1_000 * ONE, 0);
//         vm.stopPrank();

//         token0.mint(address(vault), 500 * ONE);
//         token1.mint(address(vault), 500 * ONE);

//         vm.expectRevert();
//         vm.prank(alice);
//         vault.withdrawDual(sh, 1_500 * ONE, 1_500 * ONE, alice);
//     }

//     function test_withdraw_no_supply_reverts() public {
//         vm.prank(alice);
//         vm.expectRevert(bytes("no-supply"));
//         vault.withdrawDual(123, 0, 0, alice);
//     }

//     // ---- harvest & compound ----
//     function test_harvest_collects_fees() public {
//         vm.startPrank(alice);
//         vault.depositDual(1_000 * ONE, 1_000 * ONE, 0);
//         vm.stopPrank();

//         uint256 tid = vault.tokenId();
//         nfpm.addFees(tid, 10 * ONE, 12 * ONE);

//         vm.startPrank(keeper);
//         (uint256 c0, uint256 c1, , ) = vault.harvestAndCompound(0, 0);
//         vm.stopPrank();

//         assertEq(c0, 10 * ONE);
//         assertEq(c1, 12 * ONE);
//         assertTrue(token0.balanceOf(address(vault)) >= 10 * ONE);
//         assertTrue(token1.balanceOf(address(vault)) >= 12 * ONE);
//     }

//     function test_harvest_compound_adds_liquidity() public {
//         vm.startPrank(alice);
//         vault.depositDual(1_000 * ONE, 1_000 * ONE, 0);
//         vm.stopPrank();

//         token0.mint(address(vault), 100 * ONE);
//         token1.mint(address(vault), 100 * ONE);

//         vm.startPrank(keeper);
//         (, , uint256 u0, uint256 u1) = vault.harvestAndCompound(
//             100 * ONE,
//             100 * ONE
//         );
//         vm.stopPrank();

//         assertApproxEqAbs(u0, 100 * ONE, 2);
//         assertApproxEqAbs(u1, 100 * ONE, 2);
//     }

//     // ---- rebalance ----
//     function test_rebalance_moves_range_and_collects() public {
//         vm.startPrank(alice);
//         vault.depositDual(1_000 * ONE, 1_000 * ONE, 0);
//         vm.stopPrank();

//         vm.startPrank(keeper);
//         vault.rebalance(-180, 180, 0, 0, 0, 0);
//         vm.stopPrank();

//         assertEq(vault.tickLower(), -180);
//         assertEq(vault.tickUpper(), 180);
//         assertGt(
//             token0.balanceOf(address(vault)) + token1.balanceOf(address(vault)),
//             0
//         );
//     }

//     // ---- fees ----
//     function test_management_fee_accrues_over_time() public {
//         vm.prank(vaultOwner);
//         vault.setFees(100, 0); // 1% anual

//         vm.startPrank(alice);
//         vault.depositDual(2_000 * ONE, 2_000 * ONE, 0);
//         vm.stopPrank();

//         uint256 ts0 = vault.totalSupply();

//         skip(365 days);

//         vm.prank(keeper);
//         vault.harvestAndCompound(0, 0);

//         assertGt(vault.totalSupply(), ts0);
//         assertGt(vault.balanceOf(vaultOwner), 0);
//     }

//     // ---- fuzz round-trip ----
//     function testFuzz_deposit_withdraw_roundtrip(
//         uint256 a0,
//         uint256 a1
//     ) public {
//         a0 = bound(a0, 100 * ONE, 10_000 * ONE);
//         a1 = bound(a1, 100 * ONE, 10_000 * ONE);

//         uint256 mn = a0 < a1 ? a0 : a1;
//         a0 = mn;
//         a1 = mn;

//         vm.startPrank(alice);
//         (uint256 sh, , ) = vault.depositDual(a0, a1, 0);
//         (uint256 o0, uint256 o1) = vault.withdrawDual(sh, 0, 0, alice);
//         vm.stopPrank();

//         assertApproxEqRel(o0 + o1, a0 + a1, 0.05e18);
//     }
// }
