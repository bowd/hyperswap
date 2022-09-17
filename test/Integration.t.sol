// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2 as console} from "forge-std/Test.sol";

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

import {MockInbox} from "./utils/MockInbox.sol";
import {MockOutbox} from "./utils/MockOutbox.sol";

contract IntegrationTest is Test {
    uint32 constant HubChainDomain = 0x3333;
    uint32 constant SpokeChainDomain = 0x4444;


    address abcDeployer;
    address hswapDeployer;
    address user;

    AbacusConnectionManager hubACM;
    MockInbox hubInbox;
    MockOutbox hubOutbox;

    AbacusConnectionManager spokeACM;
    MockInbox spokeInbox;
    MockOutbox spokeOutbox;


    HyperswapBridgeRouter hubRouter;
    HyperswapBridgeRouter spokeRouter;

    HyperswapFactory factory;
    ProxyTokenFactory proxyTokenFactory;
    HyperswapRouter router;
    HyperswapCustodian custodian;

    ERC20 token0;
    ERC20 token1;

    function setUp() public {
        abcDeployer = vm.addr(0xff - 1);
        hswapDeployer = vm.addr(0xff - 2);
        user = vm.addr(0xff - 3);
        vm.label(user, "user");

        changePrank(abcDeployer);
        spokeInbox = new MockInbox(SpokeChainDomain);
        vm.label(address(spokeInbox), "spokeInbox");
        hubInbox = new MockInbox(HubChainDomain);
        vm.label(address(hubInbox), "hubInbox");

        hubOutbox = new MockOutbox(address(spokeInbox), HubChainDomain);
        vm.label(address(hubOutbox), "hubOutbox");
        spokeOutbox = new MockOutbox(address(hubInbox), SpokeChainDomain);
        vm.label(address(spokeOutbox), "spokeOutbox");

        hubACM = new AbacusConnectionManager();
        hubACM.setOutbox(address(hubOutbox));
        hubACM.enrollInbox(SpokeChainDomain, address(hubInbox));
        vm.label(address(hubACM), "hubACM");

        spokeACM = new AbacusConnectionManager();
        spokeACM.setOutbox(address(spokeOutbox));
        spokeACM.enrollInbox(HubChainDomain, address(spokeInbox));
        vm.label(address(spokeACM), "spokeACM");

        changePrank(hswapDeployer);

        hubRouter = new HyperswapBridgeRouter();
        vm.label(address(hubRouter), "HubBridgeRouter");
        router = new HyperswapRouter(address(hubRouter), hubACM.localDomain());
        hubRouter.initialize(address(hubACM), address(0), address(router), true);
        proxyTokenFactory = new ProxyTokenFactory(); 
        factory = new HyperswapFactory(hswapDeployer, address(router), address(proxyTokenFactory));
        router.setFactory(address(factory));


        spokeRouter = new HyperswapBridgeRouter();
        vm.label(address(spokeRouter), "SpokeBridgeRouter");
        custodian = new HyperswapCustodian(address(spokeRouter));
        spokeRouter.initialize(address(spokeACM), address(custodian), address(0), false);

        hubRouter.enrollRemoteRouter(
            SpokeChainDomain,
            bytes32(uint256(uint160(address(spokeRouter))))
        );

        spokeRouter.enrollRemoteRouter(
            HubChainDomain,
            bytes32(uint256(uint160(address(hubRouter))))
        );

        // spokeRouter.enrollRemoteRouter(
        //     HubChainDomain,
        //     bytes32(uint256(uint160(address(router))))
        // );


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
        token1.approve(address(custodian), 9e21);

        Token memory tt0 = Token({
            domainID: HubChainDomain,
            tokenAddr: address(token0)
        });
        Token memory tt1 = Token({
            domainID: SpokeChainDomain,
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

        spokeInbox.processNextPendingMessage();
        hubInbox.processNextPendingMessage();

        address pair = factory.getPair(tt0, tt1);
        vm.label(IHyperswapPair(pair).tokenRemoteProxy(), "TK1Proxy");
        uint256 lpTokens = IHyperswapPair(pair).balanceOf(user);
        console.log(lpTokens);

        IHyperswapPair(pair).approve(address(router), lpTokens);

        token0.approve(address(router), 1e20);

        Token[] memory path = new Token[](2);
        path[0] = tt0;
        path[1] = tt1;

        router.swapExactTokensForTokens(1e20, 0, path, user, block.timestamp + 1000);

        spokeInbox.processNextPendingMessage();
        hubInbox.processNextPendingMessage();

        token1.approve(address(custodian), 1e19);

        path[0] = tt1;
        path[1] = tt0;

        router.swapExactTokensForTokens(1e19, 0, path, user, block.timestamp + 1000);

        spokeInbox.processNextPendingMessage();
        hubInbox.processNextPendingMessage();

        router.removeLiquidity(
            tt0,
            tt1,
            lpTokens,
            0,
            0,
            user,
            block.timestamp + 1000
        );

        spokeInbox.processNextPendingMessage();
        hubInbox.processNextPendingMessage();
    }
}