// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import {Token} from "../libraries/HyperswapLibrary.sol";

interface IHyperswapFactory {
  event PairCreated(
    bytes32 indexed token0,
    bytes32 indexed token1,
    address pair,
    uint256 index
  );

  function feeTo() external view returns (address);

  function feeToSetter() external view returns (address);

  function getPair(Token calldata tokenA, Token calldata tokenB)
    external
    view
    returns (address pair);

  function allPairs(uint256) external view returns (address pair);

  function allPairsLength() external view returns (uint256);

  function createPair(
    Token calldata tokenA,
    Token calldata tokenB,
    uint32 localDomain
  ) external returns (address pair);

  function setFeeTo(address) external;

  function setFeeToSetter(address) external;
}
