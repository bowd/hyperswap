// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2 as console} from "forge-std/Test.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AbacusConnectionManager} from "@abacus-network/core/contracts/AbacusConnectionManager.sol";

import {IHyperswapPair} from "contracts/interfaces/IHyperswapPair.sol";

import {HyperswapFactory} from "contracts/HyperswapFactory.sol";
import {HyperswapRouter} from "contracts/HyperswapRouter.sol";
import {HyperswapRemoteRouter} from "contracts/HyperswapRemoteRouter.sol";
import {HyperswapPair} from "contracts/HyperswapPair.sol";
import {Token, HyperswapLibrary} from "contracts/libraries/HyperswapLibrary.sol";

import {MockInbox} from "./utils/MockInbox.sol";
import {MockOutbox} from "./utils/MockOutbox.sol";

contract IntegrationTest is Test {
    uint32 constant HostChainDomain = 0x3333;
    uint32 constant RemoteChainDomain = 0x4444;


    address abcDeployer;
    address hswapDeployer;
    address user;

    AbacusConnectionManager hostACM;
    MockInbox hostInbox;
    MockOutbox hostOutbox;

    AbacusConnectionManager remoteACM;
    MockInbox remoteInbox;
    MockOutbox remoteOutbox;

    HyperswapFactory factory;
    HyperswapRouter router;
    HyperswapRemoteRouter remoteRouter;

    ERC20 token0;
    ERC20 token1;

    function setUp() public {
        abcDeployer = vm.addr(0xff - 1);
        hswapDeployer = vm.addr(0xff - 2);
        user = vm.addr(0xff - 3);
        vm.label(user, "user");

        changePrank(abcDeployer);
        remoteInbox = new MockInbox(RemoteChainDomain);
        vm.label(address(remoteInbox), "RemoteInbox");
        hostInbox = new MockInbox(HostChainDomain);
        vm.label(address(hostInbox), "HostInbox");

        hostOutbox = new MockOutbox(address(remoteInbox), HostChainDomain);
        vm.label(address(hostOutbox), "HostOutbox");
        remoteOutbox = new MockOutbox(address(hostInbox), RemoteChainDomain);
        vm.label(address(remoteOutbox), "RemoteOutbox");

        hostACM = new AbacusConnectionManager();
        hostACM.setOutbox(address(hostOutbox));
        hostACM.enrollInbox(RemoteChainDomain, address(hostInbox));
        vm.label(address(hostACM), "HostACM");

        remoteACM = new AbacusConnectionManager();
        remoteACM.setOutbox(address(remoteOutbox));
        remoteACM.enrollInbox(HostChainDomain, address(remoteInbox));
        vm.label(address(remoteACM), "RemoteACM");


        changePrank(hswapDeployer);
        // factory = new HyperswapFactory(hswapDeployer);
        router = new HyperswapRouter(hswapDeployer);
        router.initialize(address(hostACM));

        factory = HyperswapFactory(router.factory());

        remoteRouter = new HyperswapRemoteRouter();
        remoteRouter.initialize(address(remoteACM));

        router.enrollRemoteRouter(
            RemoteChainDomain,
            bytes32(uint256(uint160(address(remoteRouter))))
        );

        remoteRouter.enrollRemoteRouter(
            HostChainDomain,
            bytes32(uint256(uint160(address(router))))
        );


        token0 = new ERC20("Token0", "TK0");
        vm.label(address(token0), "TK0");
        token1 = new ERC20("Token1", "TK1");
        vm.label(address(token1), "TK1");

        deal(address(token0), user, 1e23);
        deal(address(token1), user, 1e23);
    }


    function test_addLiquidity() public {
        changePrank(user);

        token0.approve(address(router), 1e22);
        token1.approve(address(remoteRouter), 9e21);

        Token memory tt0 = Token({
            domainID: HostChainDomain,
            tokenAddr: address(token0)
        });
        Token memory tt1 = Token({
            domainID: RemoteChainDomain,
            tokenAddr: address(token1)
        });

        router.addLiquidity(
            tt0,
            tt1,
            1e22,
            9e21,
            1e22,
            9e21,
            user,
            block.timestamp + 1000
        );

        remoteInbox.processNextPendingMessage();
        hostInbox.processNextPendingMessage();

        address pair = factory.getPair(tt0, tt1);
        vm.label(IHyperswapPair(pair).tokenRemoteProxy(), "TK1Proxy");
        uint256 lpTokens = IHyperswapPair(pair).balanceOf(user);
        console.log(lpTokens);

        IHyperswapPair(pair).approve(address(router), lpTokens);

        router.removeLiquidity(
            tt0,
            tt1,
            lpTokens,
            0,
            0,
            user,
            block.timestamp + 1000
        );



        remoteInbox.processNextPendingMessage();
        hostInbox.processNextPendingMessage();
    }
}