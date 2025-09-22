// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/strategies/Strategies.sol";

contract DeployAndSetupStrategy is Script {
    // Sepolia addresses - same as SimpleSwap
    address constant UNIVERSAL_ROUTER =
        0x3A9D48AB9751398BbFa63ad67599Bb04e4BdF98b;
    address constant POOL_MANAGER = 0xE03A1074c86CFeDd5C142C4F04F1a1536e203543;
    address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address constant CALLBACK_MANAGER =
        0xc9f36411C9897e7F959D99ffca2a0Ba7ee0D7bDA;
    address constant USDC = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;
    address constant WETH = 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14;

    Strategies strategy;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("=== DEPLOY AND SETUP STRATEGY ===");
        console.log("Deployer:", deployer);

        vm.startBroadcast(deployerPrivateKey);

        // Step 1: Deploy Strategy
        console.log("\n1. Deploying Strategy contract...");
        strategy = new Strategies(
            USDC, // underlyingToken - using USDC as main token
            UNIVERSAL_ROUTER, // protocol address
            bytes4(0x12345678), // depositSelector - dummy
            bytes4(0x87654321), // withdrawSelector - dummy
            bytes4(0x11111111), // claimSelector - dummy
            bytes4(0x22222222) // getBalanceSelector - dummy
        );
        console.log("Strategy deployed at:", address(strategy));

        // Step 2: Set vault to deployer
        console.log("\n2. Setting vault to deployer address...");
        try strategy.setVault(deployer) {
            console.log("Vault set successfully!");
        } catch Error(string memory reason) {
            console.log("Failed to set vault:", reason);
        }

        // Step 3: Check deployer USDC balance
        console.log("\n3. Checking deployer USDC balance...");
        uint256 deployerUSDC = IToken(USDC).balanceOf(deployer);
        console.log("Deployer USDC balance:", deployerUSDC);

        // Step 4: Approve USDC for strategy
        console.log("\n4. Approving USDC for strategy...");
        uint256 approveAmount = 10000000; // 10 USDC (6 decimals)

        try IToken(USDC).approve(address(strategy), approveAmount) {
            console.log("USDC approved for strategy!");
        } catch Error(string memory reason) {
            console.log("Failed to approve USDC:", reason);
        }

        // Step 5: Execute Emergency Exit to emit the event (reason = 1)
        console.log(
            "\n5. Executing Emergency Exit to emit event (reason = 1)..."
        );
        try strategy.emergencyExit(abi.encode(1)) {
            console.log("Emergency exit event emitted successfully!");
        } catch Error(string memory reason) {
            console.log(
                "Emergency exit failed (expected - just emitting event):",
                reason
            );
        }

        // Step 6: Check final balances
        console.log("\n6. Checking final balances...");
        uint256 finalStrategyUSDC = IToken(USDC).balanceOf(address(strategy));
        uint256 finalDeployerUSDC = IToken(USDC).balanceOf(deployer);
        console.log("Final Strategy USDC balance:", finalStrategyUSDC);
        console.log("Final Deployer USDC balance:", finalDeployerUSDC);

        vm.stopBroadcast();

        console.log("\n=== DEPLOY AND SETUP COMPLETED ===");
        console.log("Strategy Address:", address(strategy));
    }
}

interface IToken {
    function balanceOf(address account) external view returns (uint256);

    function transfer(address to, uint256 amount) external returns (bool);

    function approve(address spender, uint256 amount) external returns (bool);
}
