// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/reactive/LiquidityChangeReactive.sol";

contract DeployLiquidityChangeReactive is Script {
    // Configuration - you need to set these addresses
    // Pool address (your deployed hook pool)
    address POOL_ADDRESS; // Will be set from environment variable

    // Strategy address (could be the same as pool or a different contract)
    address STRATEGY_ADDRESS; // Will be set from environment variable

    // Client address (who receives benefits from the reactive contract)
    address constant CLIENT_ADDRESS =
        0xb70649baF7A93EEB95E3946b3A82F8F312477d2b; // Owner as client

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Get pool address from environment variable
        try vm.envAddress("POOL_ADDRESS") returns (address addr) {
            POOL_ADDRESS = addr;
        } catch {
            revert("Please set POOL_ADDRESS environment variable");
        }

        // Get strategy address from environment variable (could be same as pool)
        try vm.envAddress("STRATEGY_ADDRESS") returns (address addr) {
            STRATEGY_ADDRESS = addr;
        } catch {
            // Default to pool address if strategy not specified
            STRATEGY_ADDRESS = POOL_ADDRESS;
            console.log(
                "STRATEGY_ADDRESS not set, using POOL_ADDRESS as strategy"
            );
        }

        console.log("=== DEPLOYING LIQUIDITY CHANGE REACTIVE CONTRACT ===");
        console.log("Deployer:", deployer);
        console.log("Pool (Sepolia):", POOL_ADDRESS);
        console.log("Strategy (Sepolia):", STRATEGY_ADDRESS);
        console.log("Client:", CLIENT_ADDRESS);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy the reactive contract with initial funding
        LiquidityChangeReactive reactive = new LiquidityChangeReactive{
            value: 1 ether
        }(POOL_ADDRESS, STRATEGY_ADDRESS, CLIENT_ADDRESS);

        console.log(
            "LiquidityChangeReactive Contract deployed:",
            address(reactive)
        );
        console.log("Balance:", address(reactive).balance);

        // DON'T auto-register here - will be done separately
        console.log("Contract deployed successfully!");
        console.log("WARNING: Registration will be done separately!");
        // reactive.autoRegister();
        vm.stopBroadcast();

        console.log("\n=== DEPLOYMENT COMPLETE ===");
        console.log("Reactive Contract:", address(reactive));
        console.log("Owner:", reactive.getOwner());
        console.log("Pool:", reactive.getPool());
        console.log("Strategy:", reactive.getStrategy());
        console.log("Client:", reactive.getClient());
        console.log("Registered:", reactive.isRegistered());

        // Save deployment info to environment variable format
        console.log("\nCONTRACT ADDRESS:", vm.toString(address(reactive)));

        console.log("\n=== NEXT STEPS ===");
        console.log("==============");
        console.log("1. REGISTER the contract (separate step):");
        console.log(
            "   LIQUIDITY_REACTIVE_ADDRESS=",
            vm.toString(address(reactive))
        );
        console.log(
            "   forge script script/RegisterLiquidityChangeReactive.s.sol:RegisterLiquidityChangeReactive \\"
        );
        console.log(
            "     --rpc-url https://lasna-rpc.rnk.dev --account DEPLOYER --broadcast"
        );
        console.log("");
        console.log("2. TEST by adding large liquidity to trigger the hook:");
        console.log(
            "   HOOK_ADDRESS=<your_hook_address> forge script script/AddLargeLiquidity.s.sol:AddLargeLiquidityScript \\"
        );
        console.log("     --rpc-url sepolia --account DEPLOYER --broadcast");
        console.log("");
        console.log("3. MONITOR the reactive contract:");
        console.log(
            "   cast call",
            vm.toString(address(reactive)),
            '"isRegistered()" --rpc-url https://lasna-rpc.rnk.dev'
        );
        console.log("");
        console.log("4. CHECK for events:");
        console.log(
            "   cast logs",
            vm.toString(address(reactive)),
            "--rpc-url https://lasna-rpc.rnk.dev --from-block latest"
        );
    }
}
