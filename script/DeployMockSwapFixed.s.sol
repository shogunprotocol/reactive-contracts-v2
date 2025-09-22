// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/MockEmergencySwap.sol";

contract DeployMockSwapFixed is Script {
    address constant CALLBACK_PROXY_MAINNET =
        0x1D5267C1bb7D8bA68964dDF3990601BDB7902D76;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy with callback proxy support
        MockEmergencySwap mockSwap = new MockEmergencySwap(
            CALLBACK_PROXY_MAINNET
        );

        vm.stopBroadcast();

        console.log("NEW MockSwap Address:", address(mockSwap));

        console.log(vm.toString(address(mockSwap)));
    }
}
