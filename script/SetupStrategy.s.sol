// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/strategies/Strategies.sol";

contract SetupStrategy is Script {
    // Deployed contract addresses
    address constant STRATEGY_ADDRESS =
        0xACF69128c3577c9C154E4D46A8B7C2576C230e2C;
    address constant WETH = 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14;
    address constant USDC = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;

    Strategies strategy;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("=== SETUP STRATEGY ===");
        console.log("Deployer:", deployer);
        console.log("Strategy:", STRATEGY_ADDRESS);

        vm.startBroadcast(deployerPrivateKey);

        // Get strategy instance
        strategy = Strategies(STRATEGY_ADDRESS);

        // Step 1: Check current vault
        console.log("\n1. Checking current vault...");
        address currentVault = strategy.vault();
        console.log("Current vault:", currentVault);

        // Step 2: Set vault if not set
        if (currentVault == address(0)) {
            console.log("\n2. Setting vault to deployer address...");
            try strategy.setVault(deployer) {
                console.log("Vault set successfully!");
            } catch Error(string memory reason) {
                console.log("Failed to set vault:", reason);
            } catch {
                console.log("Failed to set vault with unknown error");
            }
        } else {
            console.log("Vault already set to:", currentVault);
        }

        // Step 3: Check deployer token balances
        console.log("\n3. Checking deployer token balances...");
        uint256 deployerWETH = IToken(WETH).balanceOf(deployer);
        uint256 deployerUSDC = IToken(USDC).balanceOf(deployer);
        console.log("Deployer WETH:", deployerWETH);
        console.log("Deployer USDC:", deployerUSDC);

        // Step 4: Approve tokens for strategy
        console.log("\n4. Approving tokens for strategy...");
        uint256 approveAmount = 1 ether; // 1 WETH

        try IToken(WETH).approve(STRATEGY_ADDRESS, approveAmount) {
            console.log("WETH approved for strategy!");
        } catch Error(string memory reason) {
            console.log("Failed to approve WETH:", reason);
        } catch {
            console.log("Failed to approve WETH with unknown error");
        }

        // Step 5: Execute strategy with tokens
        console.log("\n5. Executing strategy with tokens...");
        uint256 depositAmount = 0.1 ether; // 0.1 WETH

        try strategy.execute(depositAmount, "") {
            console.log("Strategy executed successfully!");
        } catch Error(string memory reason) {
            console.log("Failed to execute strategy:", reason);
        } catch {
            console.log("Failed to execute strategy with unknown error");
        }

        // Step 6: Check final balances
        console.log("\n6. Checking final balances...");
        uint256 finalDeployerWETH = IToken(WETH).balanceOf(deployer);
        uint256 finalStrategyWETH = IToken(WETH).balanceOf(STRATEGY_ADDRESS);
        console.log("Final Deployer WETH:", finalDeployerWETH);
        console.log("Final Strategy WETH:", finalStrategyWETH);

        vm.stopBroadcast();

        console.log("\n=== SETUP COMPLETED ===");
    }
}

interface IToken {
    function balanceOf(address account) external view returns (uint256);

    function transfer(address to, uint256 amount) external returns (bool);

    function approve(address spender, uint256 amount) external returns (bool);
}
