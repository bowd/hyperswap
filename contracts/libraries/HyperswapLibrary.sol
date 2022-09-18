// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import {console2 as console} from "forge-std/Test.sol";

import {IHyperswapPair} from "../interfaces/IHyperswapPair.sol";
import {HyperswapPair} from "../HyperswapPair.sol";

struct Token {
    uint32 domainID; // hyperlane domain IDs https://docs.hyperlane.xyz/hyperlane-docs/developers/domains
    address tokenAddr;
}

library HyperswapToken {
    function id(Token memory self) external pure returns (bytes32) {
        return bytes32(uint256(self.domainID) * 2**224 + uint160(self.tokenAddr));
    }

    function eq(Token memory self, Token memory other) external pure returns (bool) {
        return (self.domainID == other.domainID) && (self.tokenAddr == other.tokenAddr);
    }

    function lt(Token memory self, Token memory other) external pure returns (bool) {
        if (self.domainID < other.domainID) {
            return true;
        } else if (self.domainID > other.domainID) {
            return false;
        } else {
            return self.tokenAddr < other.tokenAddr;
        }
    }
}

library HyperswapLibrary {
    using HyperswapToken for Token;
    // returns sorted token addresses, used to handle return values from pairs sorted in this order
    function sortTokens(Token memory tokenA, Token memory tokenB) public pure returns (Token memory token0, Token memory token1) {
        (token0, token1) = tokenA.lt(tokenB) ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0.tokenAddr != address(0), "HyperswapLibrary: ZERO_ADDRESS");
    }

    // calculates the CREATE2 address for a pair without making any external calls
    function pairFor(address factory, Token memory tokenA, Token memory tokenB) public pure returns (address pair) {
        (Token memory token0, Token memory token1) = sortTokens(tokenA, tokenB);
        pair = address(uint160(uint(keccak256(abi.encodePacked(
                hex"ff",
                factory,
                keccak256(abi.encode(token0, token1)),
                keccak256(type(HyperswapPair).creationCode)
                // hex"a8aa07b463f557e577c78b16e48ab4b9b7942247de81242aafb448bb26b4b90e" // init code hash
            )))));
    }

    // fetches and sorts the reserves for a pair
    function getReserves(address factory, Token memory tokenA, Token memory tokenB) public view returns (uint reserveA, uint reserveB) {
        (Token memory token0,) = sortTokens(tokenA, tokenB);
        console.log(pairFor(factory, tokenA, tokenB));
        (uint reserve0, uint reserve1,) = IHyperswapPair(pairFor(factory, tokenA, tokenB)).getReserves();
        (reserveA, reserveB) = (tokenA.domainID == token0.domainID && tokenA.tokenAddr == token0.tokenAddr) ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    function getReservesForPair(address pair, Token memory tokenA, Token memory tokenB) external view returns (uint reserveA, uint reserveB) {
        (Token memory token0,) = sortTokens(tokenA, tokenB);
        (uint reserve0, uint reserve1,) = IHyperswapPair(pair).getReserves();
        (reserveA, reserveB) = (tokenA.domainID == token0.domainID && tokenA.tokenAddr == token0.tokenAddr) ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    // given some amount of an asset and pair reserves, returns an equivalent amount of the other asset
    function quote(uint amountA, uint reserveA, uint reserveB) external pure returns (uint amountB) {
        require(amountA > 0, "HyperswapLibrary: INSUFFICIENT_AMOUNT");
        require(reserveA > 0 && reserveB > 0, "HyperswapLibrary: INSUFFICIENT_LIQUIDITY");
        amountB = (amountA * reserveB) / reserveA;
    }

    // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) public pure returns (uint amountOut) {
        require(amountIn > 0, "HyperswapLibrary: INSUFFICIENT_INPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "HyperswapLibrary: INSUFFICIENT_LIQUIDITY");
        uint amountInWithFee = amountIn * 997;
        uint numerator = amountInWithFee * reserveOut;
        uint denominator = (reserveIn * 1000) + amountInWithFee;
        amountOut = numerator / denominator;
    }

    // given an output amount of an asset and pair reserves, returns a required input amount of the other asset
    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut) public pure returns (uint amountIn) {
        require(amountOut > 0, "HyperswapLibrary: INSUFFICIENT_OUTPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "HyperswapLibrary: INSUFFICIENT_LIQUIDITY");
        uint numerator = (reserveIn * amountOut) * 1000;
        uint denominator = (reserveOut - amountOut) * (997);
        amountIn = (numerator / denominator) + 1;
    }

    // performs chained getAmountOut calculations on any number of pairs
    function getAmountsOut(address factory, uint amountIn, Token[] memory path) external view returns (uint[] memory amounts) {
        require(path.length >= 2, "HyperswapLibrary: INVALID_PATH");
        amounts = new uint[](path.length);
        amounts[0] = amountIn;
        for (uint i; i < path.length - 1; i++) {
            (uint reserveIn, uint reserveOut) = getReserves(factory, path[i], path[i + 1]);
            amounts[i + 1] = getAmountOut(amounts[i], reserveIn, reserveOut);
        }
    }

    // performs chained getAmountIn calculations on any number of pairs
    function getAmountsIn(address factory, uint amountOut, Token[] memory path) external view returns (uint[] memory amounts) {
        require(path.length >= 2, "HyperswapLibrary: INVALID_PATH");
        amounts = new uint[](path.length);
        amounts[amounts.length - 1] = amountOut;
        for (uint i = path.length - 1; i > 0; i--) {
            (uint reserveIn, uint reserveOut) = getReserves(factory, path[i - 1], path[i]);
            amounts[i - 1] = getAmountIn(amounts[i], reserveIn, reserveOut);
        }
    }
}
