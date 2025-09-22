// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.13;

import "forge-std/Script.sol";

interface IStrategy {
    function emergencyExit(bytes calldata data) external;

    function getBalance() external view returns (uint256);
}

interface IReactive {
    function isTriggered() external view returns (bool);

    function isRegistered() external view returns (bool);

    function isDone() external view returns (bool);
}

interface IMockSwap {
    function getBalances()
        external
        view
        returns (uint256 usdcBalance, uint256 wethBalance);

    function emergencySwap(
        uint256 amount,
        address recipient,
        uint256 minAmount
    ) external returns (uint256);
}

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);

    function transfer(address to, uint256 amount) external returns (bool);

    function approve(address spender, uint256 amount) external returns (bool);
}

contract TestCompleteFlow is Script {
    // Addresses
    address constant STRATEGY = 0x77969091a0312E48970Fe46C35a9550FccdDC113;
    address constant NEW_REACTIVE = 0xF617e5061D1044e862F2e96c93cf73505fc23e63;
    address constant MOCK_SWAP = 0x36CA374BE371cC5c77C385D1Aa42F3389166F55a;
    address constant USDC = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;
    address constant WETH = 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("=== TESTING COMPLETE EMERGENCY EXIT FLOW ===");
        console.log("Deployer:", deployer);
        console.log("Strategy:", STRATEGY);
        console.log("Reactive:", NEW_REACTIVE);
        console.log("MockSwap:", MOCK_SWAP);

        // Check initial state
        console.log("\n=== INITIAL STATE ===");
        uint256 deployerUSDC = IERC20(USDC).balanceOf(deployer);
        uint256 deployerWETH = IERC20(WETH).balanceOf(deployer);
        console.log("Your USDC:", deployerUSDC);
        console.log("Your WETH:", deployerWETH);

        // Check reactive state
        bool reactiveRegistered = IReactive(NEW_REACTIVE).isRegistered();
        bool reactiveTriggered = IReactive(NEW_REACTIVE).isTriggered();
        console.log("Reactive registered:", reactiveRegistered);
        console.log("Reactive triggered:", reactiveTriggered);

        // Check MockSwap liquidez
        (uint256 mockUSDC, uint256 mockWETH) = IMockSwap(MOCK_SWAP)
            .getBalances();
        console.log("MockSwap USDC:", mockUSDC);
        console.log("MockSwap WETH:", mockWETH);

        vm.startBroadcast(deployerPrivateKey);

        // Step 1: Ensure MockSwap has enough WETH for emergency swaps
        console.log("\n=== STEP 1: ENSURING MOCKSWAP LIQUIDITY ===");
        if (mockWETH < 1e16) {
            // Less than 0.01 WETH
            console.log("Adding more WETH to MockSwap...");
            try IERC20(WETH).transfer(MOCK_SWAP, 5e15) {
                // 0.005 WETH
                console.log("WETH transferred to MockSwap");
            } catch {
                console.log("Failed to transfer WETH - may not have enough");
            }
        } else {
            console.log("MockSwap has enough WETH liquidity");
        }

        // Step 2: Send USDC to Strategy
        console.log("\n=== STEP 2: FUNDING STRATEGY ===");
        uint256 amountToSend = 3000000; // 3 USDC
        try IERC20(USDC).transfer(STRATEGY, amountToSend) {
            console.log("Sent", amountToSend, "USDC to Strategy");
        } catch Error(string memory reason) {
            console.log("Failed to send USDC to Strategy:", reason);
            vm.stopBroadcast();
            return;
        }

        // Step 3: Execute Emergency Exit
        console.log("\n=== STEP 3: EXECUTING EMERGENCY EXIT ===");
        try IStrategy(STRATEGY).emergencyExit(abi.encode(1)) {
            console.log("Emergency exit executed successfully!");
            console.log("EmergencyExited event should be emitted");
        } catch Error(string memory reason) {
            console.log("Emergency exit failed:", reason);
        }

        vm.stopBroadcast();

        console.log("\n=== NEXT STEPS ===");
        console.log("1. Wait 30-60 seconds for cross-chain processing");
        console.log("2. Check if reactive triggered:");
        console.log(
            "   cast call",
            vm.toString(NEW_REACTIVE),
            '"isTriggered()" --rpc-url https://lasna-rpc.rnk.dev'
        );
        console.log("3. Check MockSwap events:");
        console.log(
            "   cast logs",
            vm.toString(MOCK_SWAP),
            "--rpc-url sepolia --from-block latest"
        );
        console.log("4. Monitor reactive events:");
        console.log(
            "   cast logs",
            vm.toString(NEW_REACTIVE),
            "--rpc-url https://lasna-rpc.rnk.dev --from-block latest"
        );
    }
}
