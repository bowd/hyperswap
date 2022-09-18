// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AbacusConnectionManager} from "@abacus-network/core/contracts/AbacusConnectionManager.sol";

import {IHyperswapPair} from "contracts/interfaces/IHyperswapPair.sol";

import {HyperswapFactory} from "contracts/HyperswapFactory.sol";
import {HyperswapRouter} from "contracts/HyperswapRouter.sol";
import {HyperswapBridgeRouter} from "contracts/HyperswapBridgeRouter.sol";
import {HyperswapCustodian} from "contracts/HyperswapCustodian.sol";
import {HyperswapPair} from "contracts/HyperswapPair.sol";
import {ProxyTokenFactory} from "contracts/ProxyTokenFactory.sol";
import {Token, HyperswapLibrary} from "contracts/libraries/HyperswapLibrary.sol";

contract DeployHub is Script {
    HyperswapBridgeRouter hubRouter;
    HyperswapBridgeRouter spokeRouter;

    HyperswapFactory factory;
    ProxyTokenFactory proxyTokenFactory;
    HyperswapRouter router;
    HyperswapCustodian custodian;

    function run() external {
        address hubACM = 0xc41169650335Ad274157Ea5116Cdf227430A68a3; /// alfajores
        vm.startBroadcast();
        hubRouter = new HyperswapBridgeRouter();
        router = new HyperswapRouter(address(hubRouter), 1000);
        hubRouter.initialize(address(hubACM), address(0), address(router), true);
        proxyTokenFactory = new ProxyTokenFactory(); 
        factory = new HyperswapFactory(address(0), address(router), address(proxyTokenFactory));
        router.setFactory(address(factory));
        vm.stopBroadcast();
    }
}
