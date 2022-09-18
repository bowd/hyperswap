// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import {IHyperswapFactory} from "./interfaces/IHyperswapFactory.sol";
import {IHyperswapPair} from "./interfaces/IHyperswapPair.sol";
import {HyperswapPair} from "./HyperswapPair.sol";
import {Token, HyperswapToken} from "./libraries/HyperswapLibrary.sol";
import {IProxyTokenFactory} from "./interfaces/IProxyTokenFactory.sol";

contract HyperswapFactory is IHyperswapFactory {
  using HyperswapToken for Token;
  address public feeTo;
  address public feeToSetter;
  address public router;
  address public proxyTokenFactory;

  mapping(bytes32 => mapping(bytes32 => address)) public pairs;
  address[] public allPairs;

  constructor(
    address _feeToSetter,
    address _router,
    address _proxyTokenFactory
  ) {
    feeToSetter = _feeToSetter;
    router = _router;
    proxyTokenFactory = _proxyTokenFactory;
  }

  function allPairsLength() external view returns (uint256) {
    return allPairs.length;
  }

  function getPair(Token calldata tokenA, Token calldata tokenB)
    external
    view
    returns (address pair)
  {
    return pairs[tokenA.id()][tokenB.id()];
  }

  // TODO: should be only router
  function createPair(
    Token calldata tokenA,
    Token calldata tokenB,
    uint32 localDomain
  ) external returns (address pair) {
    require(!tokenA.eq(tokenB), "Hyperswap: IDENTICAL_TOKENS");
    (Token memory token0, Token memory token1) = tokenA.lt(tokenB)
      ? (tokenA, tokenB)
      : (tokenB, tokenA);
    require(token0.tokenAddr != address(0), "Hyperswap: ZERO_ADDRESS");
    require(token1.tokenAddr != address(0), "Hyperswap: ZERO_ADDRESS");
    require(
      pairs[token0.id()][token1.id()] == address(0),
      "Hyperswap: PAIR_EXISTS"
    ); // single check is sufficient
    bytes memory bytecode = type(HyperswapPair).creationCode;
    bytes32 salt = keccak256(abi.encode(token0, token1));
    assembly {
      pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
    }

    pairs[token0.id()][token1.id()] = pair;
    pairs[token1.id()][token0.id()] = pair;
    allPairs.push(pair);

    if (token0.domainID == localDomain) {
      address proxyToken = IProxyTokenFactory(proxyTokenFactory)
        .deployProxyToken(router, token1.domainID, token1.tokenAddr, pair);
      IHyperswapPair(pair).initialize(token0, token1, proxyToken);
    } else {
      address proxyToken = IProxyTokenFactory(proxyTokenFactory)
        .deployProxyToken(router, token0.domainID, token0.tokenAddr, pair);
      IHyperswapPair(pair).initialize(token1, token0, proxyToken);
    }

    emit PairCreated(token0.id(), token1.id(), pair, allPairs.length);
  }

  function setFeeTo(address _feeTo) external {
    require(msg.sender == feeToSetter, "Hyperswap: FORBIDDEN");
    feeTo = _feeTo;
  }

  function setFeeToSetter(address _feeToSetter) external {
    require(msg.sender == feeToSetter, "Hyperswap: FORBIDDEN");
    feeToSetter = _feeToSetter;
  }
}
