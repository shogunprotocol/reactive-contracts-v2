// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/reactive/StrategyEmergencyExitReactiveFixed.sol";

contract RegisterFixedContract is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Get the deployed contract address from environment or file
        address contractAddress;

        // Try to read from deployment file first
        try vm.readFile("deployment-reactive-fixed.txt") returns (
            string memory content
        ) {
            // Parse the address from the file content
            // Format: "FIXED_REACTIVE_ADDRESS=0x..."
            bytes memory contentBytes = bytes(content);
            if (contentBytes.length > 22) {
                // "FIXED_REACTIVE_ADDRESS=".length = 22
                string memory addressStr = "";
                for (
                    uint i = 22;
                    i < contentBytes.length && contentBytes[i] != bytes1("\n");
                    i++
                ) {
                    addressStr = string(
                        abi.encodePacked(
                            addressStr,
                            string(abi.encodePacked(contentBytes[i]))
                        )
                    );
                }
                contractAddress = vm.parseAddress(addressStr);
            }
        } catch {
            // Fallback: use environment variable or manual input
            try vm.envAddress("FIXED_REACTIVE_ADDRESS") returns (address addr) {
                contractAddress = addr;
            } catch {
                revert(
                    "Please set FIXED_REACTIVE_ADDRESS environment variable or ensure deployment-reactive-fixed.txt exists"
                );
            }
        }

        console.log("=== REGISTERING FIXED REACTIVE CONTRACT ===");
        console.log("Deployer:", deployer);
        console.log("Contract Address:", contractAddress);

        vm.startBroadcast(deployerPrivateKey);

        // Get the contract instance
        StrategyEmergencyExitReactiveFixed reactive = StrategyEmergencyExitReactiveFixed(
                payable(contractAddress)
            );

        // Verify ownership
        address owner = reactive.getOwner();
        console.log("Contract Owner:", owner);
        console.log("Current Deployer:", deployer);

        require(owner == deployer, "You are not the owner of this contract");

        // Check if already registered
        bool alreadyRegistered = reactive.isRegistered();
        console.log("Already Registered:", alreadyRegistered);

        if (alreadyRegistered) {
            console.log("Contract is already registered!");
        } else {
            console.log("Attempting to register...");

            // Try to register
            try reactive.register() {
                console.log("Contract registered successfully!");
            } catch Error(string memory reason) {
                console.log(" Registration failed:", reason);
                console.log("This is a known issue with the reactive service");
                console.log(
                    "The contract can still work without registration for testing"
                );
            } catch {
                console.log(" Registration failed with unknown error");
                console.log(" This is a known issue with the reactive service");
                console.log(
                    " The contract can still work without registration for testing"
                );
            }
        }

        vm.stopBroadcast();

        console.log("\n=== REGISTRATION ATTEMPT COMPLETE ===");
        console.log("Contract:", contractAddress);
        console.log("Strategy:", reactive.getStrategy());
        console.log("SimpleSwap:", reactive.getSimpleSwap());
        console.log("Client:", reactive.getClient());
        console.log("Registered:", reactive.isRegistered());

        console.log("\n=== NEXT STEPS ===");
        console.log("1. Test the contract by triggering emergency exit:");
        console.log(
            '   cast send 0x77969091a0312E48970Fe46C35a9550FccdDC113 "emergencyExit(bytes)" 0x \\'
        );
        console.log(
            "     --rpc-url YOUR_SEPOLIA_RPC --private-key YOUR_PRIVATE_KEY"
        );
        console.log("2. Monitor the contract:");
        console.log(
            "   cast call",
            vm.toString(contractAddress),
            '"isTriggered()" --rpc-url https://lasna-rpc.rnk.dev'
        );
        console.log("3. Check for debug events:");
        console.log(
            "   cast logs",
            vm.toString(contractAddress),
            "--rpc-url https://lasna-rpc.rnk.dev --from-block latest"
        );
    }
}
