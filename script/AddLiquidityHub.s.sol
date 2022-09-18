// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {HyperswapRouter} from "contracts/HyperswapRouter.sol";
import {IERC20} from "contracts/interfaces/IERC20.sol";

import {Token, HyperswapToken, HyperswapLibrary} from "contracts/libraries/HyperswapLibrary.sol";

contract AddLiquidityHub is Script {
    uint32 constant HubChainDomain = 1000;
    uint32 constant SpokeChainDomain = 80001;
    address cUSD_ = 0x874069Fa1Eb16D44d622F2e0Ca25eeA172369bC1;
    address LINK_ = 0x326C977E6efc84E512bB9C30f76E30c160eD06FB;
    address router = 0xae00F93a2E1c787a21FFf40666C312d7702690A9;

    function run() external {
        HyperswapRouter router = HyperswapRouter(payable(router));

        Token memory cUSD = Token({
            domainID: HubChainDomain,
            tokenAddr: address(cUSD_)
        });
        Token memory LINK = Token({
            domainID: SpokeChainDomain,
            tokenAddr: address(LINK_)
        });



        vm.startBroadcast();
        IERC20(cUSD_).approve(address(router), 1e14);
        router.addLiquidity(
            cUSD,
            LINK,
            1e14,
            1e10,
            1e14,
            1e10,
            0x118923444DE650eB6321f5BF7955812c507b98d7,
            block.timestamp + 1000000
        );
        vm.stopBroadcast();
    }
}
