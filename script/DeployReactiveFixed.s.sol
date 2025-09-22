// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/reactive/StrategyEmergencyExitReactiveFixed.sol";

contract DeployReactiveFixed is Script {
    // Configuration from your FINAL_STATUS_REPORT.md
    address constant STRATEGY_ADDRESS =
        0xACF69128c3577c9C154E4D46A8B7C2576C230e2C;
    address constant MOCK_SWAP_ADDRESS =
        0xb8f7d84109c7475bF8f0A5364B8Be5dC306C09CC;
    address constant CLIENT_ADDRESS =
        0xb70649baF7A93EEB95E3946b3A82F8F312477d2b; // Owner as client

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("=== DEPLOYING FIXED REACTIVE CONTRACT ===");
        console.log("Deployer:", deployer);
        console.log("Strategy (Sepolia):", STRATEGY_ADDRESS);
        console.log("MockSwap (Sepolia):", MOCK_SWAP_ADDRESS);
        console.log("Client:", CLIENT_ADDRESS);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy the fixed reactive contract with initial funding
        StrategyEmergencyExitReactiveFixed reactive = new StrategyEmergencyExitReactiveFixed{
                value: 1 ether
            }(STRATEGY_ADDRESS, MOCK_SWAP_ADDRESS, CLIENT_ADDRESS);

        console.log("Fixed Reactive Contract deployed:", address(reactive));
        console.log("Balance:", address(reactive).balance);

        // DON'T auto-register here - will be done separately
        console.log("Contract deployed successfully!");
        console.log("WARNING: Registration will be done separately!");

        vm.stopBroadcast();

        console.log("\n=== DEPLOYMENT COMPLETE ===");
        console.log("Reactive Contract:", address(reactive));
        console.log("Owner:", reactive.getOwner());
        console.log("Strategy:", reactive.getStrategy());
        console.log("SimpleSwap:", reactive.getSimpleSwap());
        console.log("Client:", reactive.getClient());
        console.log("Registered:", reactive.isRegistered());

        // Save deployment info - COMMENTED OUT to avoid script failure
        // string memory deploymentInfo = string(
        //     abi.encodePacked(
        //         "FIXED_REACTIVE_ADDRESS=",
        //         vm.toString(address(reactive)),
        //         "\n"
        //     )
        // );
        // vm.writeFile("deployment-reactive-fixed.txt", deploymentInfo);

        console.log("\nCONTRACT ADDRESS:", vm.toString(address(reactive)));

        console.log(" NEXT STEPS:");
        console.log("==============");
        console.log("1. REGISTER the contract (separate step):");
        console.log(
            "   forge script script/RegisterFixedContract.s.sol:RegisterFixedContract \\"
        );
        console.log(
            "     --rpc-url https://lasna-rpc.rnk.dev --account DEPLOYER --broadcast"
        );
        console.log("");
        console.log("2. TEST by triggering emergency exit:");
        console.log(
            '   cast send 0x77969091a0312E48970Fe46C35a9550FccdDC113 "emergencyExit(bytes)" 0x \\'
        );
        console.log(
            "     --rpc-url YOUR_SEPOLIA_RPC --private-key YOUR_PRIVATE_KEY"
        );
        console.log("");
        console.log("3. MONITOR the contract:");
        console.log(
            "   cast call",
            vm.toString(address(reactive)),
            '"isTriggered()" --rpc-url https://lasna-rpc.rnk.dev'
        );
    }
}
