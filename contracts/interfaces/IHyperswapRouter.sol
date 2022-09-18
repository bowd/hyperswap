// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import {Token} from "../libraries/HyperswapLibrary.sol";

interface IHyperswapRouter {
  function factory() external view returns (address);

  function handleCustodianResponse(
    uint32 domain,
    bytes32 seqId,
    uint256 opIndex,
    bool success
  ) external;

  function addLiquidity(
    Token calldata tokenA,
    Token calldata tokenB,
    uint256 amountADesired,
    uint256 amountBDesired,
    uint256 amountAMin,
    uint256 amountBMin,
    address to,
    uint256 deadline
  ) external returns (bytes32 seqId);

  function removeLiquidity(
    Token calldata tokenA,
    Token calldata tokenB,
    uint256 liquidity,
    uint256 amountAMin,
    uint256 amountBMin,
    address to,
    uint256 deadline
  ) external returns (bytes32 seqId);

  function removeLiquidityWithPermit(
    Token calldata tokenA,
    Token calldata tokenB,
    uint256 liquidity,
    uint256 amountAMin,
    uint256 amountBMin,
    address to,
    uint256 deadline,
    bool approveMax,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external returns (bytes32 seqId);

  function swapExactTokensForTokens(
    uint256 amountIn,
    uint256 amountOutMin,
    Token[] calldata path,
    address to,
    uint256 deadline
  ) external returns (bytes32 seqId);

  function swapTokensForExactTokens(
    uint256 amountOut,
    uint256 amountInMax,
    Token[] calldata path,
    address to,
    uint256 deadline
  ) external returns (bytes32 seqId);

  function quote(
    uint256 amountA,
    uint256 reserveA,
    uint256 reserveB
  ) external view returns (uint256 amountB);

  function getAmountOut(
    uint256 amountIn,
    uint256 reserveIn,
    uint256 reserveOut
  ) external view returns (uint256 amountOut);

  function getAmountIn(
    uint256 amountOut,
    uint256 reserveIn,
    uint256 reserveOut
  ) external view returns (uint256 amountIn);

  function getAmountsOut(uint256 amountIn, Token[] calldata path)
    external
    view
    returns (uint256[] memory amounts);

  function getAmountsIn(uint256 amountOut, Token[] calldata path)
    external
    view
    returns (uint256[] memory amounts);
}
