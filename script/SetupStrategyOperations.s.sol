// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/strategies/Strategies.sol";

contract SetupStrategyOperations is Script {
    // Update this address after deploying the strategy
    address constant STRATEGY_ADDRESS =
        0x77969091a0312E48970Fe46C35a9550FccdDC113;
    address constant USDC = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;

    Strategies strategy;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("=== SETUP STRATEGY OPERATIONS ===");
        console.log("Deployer:", deployer);
        console.log("Strategy:", STRATEGY_ADDRESS);

        vm.startBroadcast(deployerPrivateKey);

        // Get strategy instance
        strategy = Strategies(STRATEGY_ADDRESS);

        // Step 1: Check deployer USDC balance
        console.log("\n1. Checking deployer USDC balance...");
        uint256 deployerUSDC = IToken(USDC).balanceOf(deployer);
        console.log("Deployer USDC balance:", deployerUSDC);

        // Step 2: Execute Emergency Exit to emit the event (reason = 1)
        console.log(
            "\n2. Executing Emergency Exit to emit event (reason = 1)..."
        );
        try strategy.emergencyExit(abi.encode(1)) {
            console.log("Emergency exit event emitted successfully!");
        } catch Error(string memory reason) {
            console.log(
                "Emergency exit failed (expected - just emitting event):",
                reason
            );
        }

        // Step 3: Check final balances
        console.log("\n3. Checking final balances...");
        uint256 finalStrategyUSDC = IToken(USDC).balanceOf(STRATEGY_ADDRESS);
        uint256 finalDeployerUSDC = IToken(USDC).balanceOf(deployer);
        console.log("Final Strategy USDC balance:", finalStrategyUSDC);
        console.log("Final Deployer USDC balance:", finalDeployerUSDC);

        vm.stopBroadcast();

        console.log("\n=== SETUP OPERATIONS COMPLETED ===");
    }
}

interface IToken {
    function balanceOf(address account) external view returns (uint256);

    function transfer(address to, uint256 amount) external returns (bool);

    function approve(address spender, uint256 amount) external returns (bool);
}
