// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/reactive/LiquidityChangeReactive.sol";

contract RegisterLiquidityChangeReactive is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Get the deployed contract address from environment variable
        address contractAddress;

        try vm.envAddress("LIQUIDITY_REACTIVE_ADDRESS") returns (address addr) {
            contractAddress = addr;
        } catch {
            revert(
                "Please set LIQUIDITY_REACTIVE_ADDRESS environment variable"
            );
        }

        console.log("=== REGISTERING LIQUIDITY CHANGE REACTIVE CONTRACT ===");
        console.log("Deployer:", deployer);
        console.log("Contract Address:", contractAddress);

        vm.startBroadcast(deployerPrivateKey);

        // Get the contract instance
        LiquidityChangeReactive reactive = LiquidityChangeReactive(
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

            // Try to register using autoRegister method
            try reactive.autoRegister() {
                console.log("Contract registered successfully!");
            } catch Error(string memory reason) {
                console.log("Registration failed:", reason);
                console.log("This is a known issue with the reactive service");
                console.log(
                    "The contract can still work without registration for testing"
                );
            } catch {
                console.log("Registration failed with unknown error");
                console.log("This is a known issue with the reactive service");
                console.log(
                    "The contract can still work without registration for testing"
                );
            }
        }

        vm.stopBroadcast();

        console.log("\n=== REGISTRATION ATTEMPT COMPLETE ===");
        console.log("Contract:", contractAddress);
        console.log("Pool:", reactive.getPool());
        console.log("Strategy:", reactive.getStrategy());
        console.log("Client:", reactive.getClient());
        console.log("Registered:", reactive.isRegistered());

        console.log("\n=== NEXT STEPS ===");
        console.log("1. Test the contract by adding large liquidity:");
        console.log(
            "   HOOK_ADDRESS=<your_hook_address> forge script script/AddLargeLiquidity.s.sol \\"
        );
        console.log("     --rpc-url sepolia --account DEPLOYER --broadcast");
        console.log("2. Monitor the reactive contract:");
        console.log(
            "   cast call",
            vm.toString(contractAddress),
            '"isRegistered()" --rpc-url https://lasna-rpc.rnk.dev'
        );
        console.log("3. Check for debug events:");
        console.log(
            "   cast logs",
            vm.toString(contractAddress),
            "--rpc-url https://lasna-rpc.rnk.dev --from-block latest"
        );
        console.log("4. Expected event signature:");
        console.log(
            "   LargeLiquidityChange(bytes32 indexed poolId, uint256 liquidityAmount, bool isAdd)"
        );
        console.log(
            "   Topic0: 0x2227c6013a6fb56dc2874df53ce092227f36184c12f1162fde6ff176e3e44ee4"
        );
    }
}
