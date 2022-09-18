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

contract DeploySpoke is Script {
    HyperswapBridgeRouter hubRouter;
    HyperswapBridgeRouter spokeRouter;

    HyperswapFactory factory;
    ProxyTokenFactory proxyTokenFactory;
    HyperswapRouter router;
    HyperswapCustodian custodian;

    function run() public {
        address spokeACM = 0xb636B2c65A75d41F0dBe98fB33eb563d245a241a; // mumbai
        vm.startBroadcast();
        spokeRouter = new HyperswapBridgeRouter();
        custodian = new HyperswapCustodian(address(spokeRouter));
        spokeRouter.initialize(address(spokeACM), address(custodian), address(0), false);
        vm.stopBroadcast();
    }
}
