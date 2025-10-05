// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/console2.sol";
import "forge-std/Script.sol";
import {UniswapV4StateMulticall} from "../src/UniswapV4StateMulticall.sol";

contract DeployUniswapV4StateMulticall is Script {
    function setUp() public {}

    function run() public returns (UniswapV4StateMulticall stateMulticall) {
        vm.startBroadcast();

        stateMulticall = new UniswapV4StateMulticall();
        console2.log("UniswapV4StateMulticall deployed at:", address(stateMulticall));

        vm.stopBroadcast();
    }
}