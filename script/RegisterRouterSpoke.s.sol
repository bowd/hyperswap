// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {HyperswapBridgeRouter} from "contracts/HyperswapBridgeRouter.sol";

contract RegisterRouterSpoke is Script {
    address hubRouter_ = 0x4735F2635de4B70c55Db57887a82a4D4377a5765;
    address spokeRouter_ = 0x98f9b9Dd9e8DA3895EC714f177F4D297F20Dd26D;

    function run() external {
        HyperswapBridgeRouter spokeRouter = HyperswapBridgeRouter(spokeRouter_);

        vm.startBroadcast();
        spokeRouter.enrollRemoteRouter(
            1000,
            bytes32(uint256(uint160(address(hubRouter_))))
        );
        vm.stopBroadcast();
    }
}
