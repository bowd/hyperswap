// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {console2 as console} from "forge-std/Test.sol";
import {HyperswapFactory} from "contracts/HyperswapFactory.sol";
import {HyperswapRouter} from "contracts/HyperswapRouter.sol";
import {HyperswapPair} from "contracts/HyperswapPair.sol";
import {Token, HyperswapLibrary} from "contracts/libraries/HyperswapLibrary.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract SanityCheckTest is Test {
    address deployer;
    address user;

    HyperswapFactory factory;
    HyperswapRouter router;
    ERC20 token0;
    ERC20 token1;

    function setUp() public {
        deployer = vm.addr(0x1);
        user = vm.addr(0x2);

        changePrank(deployer);
        factory = new HyperswapFactory(deployer);
        router = new HyperswapRouter(address(factory));


        token0 = new ERC20("Token0", "TK0");
        vm.label(address(token0), "TK0");
        token1 = new ERC20("Token1", "TK1");
        vm.label(address(token1), "TK1");

        deal(address(token0), user, 1e23);
        deal(address(token1), user, 1e23);
    }


    function test_hyperswap() public {
        changePrank(user);

        token0.approve(address(router), 1e22);
        token1.approve(address(router), 9e21);

        Token memory tt0 = Token({
            domainID: 1111,
            tokenAddr: address(token0)
        });
        Token memory tt1 = Token({
            domainID: 1111,
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

        // (uint256 reserve0, uint256 reserve1) = HyperswapLibrary.getReserves(address(factory), tt0, tt1);


        uint256 amount0 = 1e20;
        token0.approve(address(router), amount0);
        // uint256 amount1 = router.quote(amount0, reserve0, reserve1);

        Token[] memory path = new Token[](2);
        path[0] = tt0;
        path[1] = tt1;
        uint[] memory amounts = router.swapExactTokensForTokens(
            amount0,
            0,
            path,
            user,
            block.timestamp + 1000
        );

        console.log(amounts[0]);
        console.log(amounts[1]);
    }
}