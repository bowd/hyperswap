// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {IERC20} from "contracts/interfaces/IERC20.sol";
import {HyperswapRouter} from "contracts/HyperswapRouter.sol";

import {Token, HyperswapToken, HyperswapLibrary} from "contracts/libraries/HyperswapLibrary.sol";

contract ApproveSpoke is Script {
    uint32 constant HubChainDomain = 1000;
    uint32 constant SpokeChainDomain = 80001;
    address cUSD_ = 0x874069Fa1Eb16D44d622F2e0Ca25eeA172369bC1;
    address LINK_ = 0x326C977E6efc84E512bB9C30f76E30c160eD06FB;

    address constant hyperswapCustodian = 0x2D3f58f8020761369f5c324ea7e35b149f2aBEb5;

    function run() external {
        vm.startBroadcast();
        IERC20(LINK_).approve(hyperswapCustodian, 1e10);
        vm.stopBroadcast();
    }
}
