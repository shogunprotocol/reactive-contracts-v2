// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console} from "forge-std/console.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import "forge-std/Script.sol";

contract AddLargeLiquidityScript is Script {
    /////////////////////////////////////

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        MockERC20 mockERC20 = new MockERC20("MockERC20", "MCK", 18);
        console.log("MockERC20 deployed at:", address(mockERC20));
        vm.stopBroadcast();
    }
}
