// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;


interface IHyperswapCallee {
    function hyperswapCall(address sender, uint amount0, uint amount1, bytes calldata data) external;
}
