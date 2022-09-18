// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

interface IHyperswapCallee {
  function hyperswapCall(
    address sender,
    uint256 amount0,
    uint256 amount1,
    bytes calldata data
  ) external;
}
