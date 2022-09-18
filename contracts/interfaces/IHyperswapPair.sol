// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import {IHyperswapERC20} from "./IHyperswapERC20.sol";
import {Token} from "../libraries/HyperswapLibrary.sol";

interface IHyperswapPair is IHyperswapERC20 {
  event Mint(address indexed sender, uint256 amount0, uint256 amount1);
  event Burn(
    address indexed sender,
    uint256 amount0,
    uint256 amount1,
    address indexed to
  );
  event Swap(
    address indexed sender,
    uint256 amount0In,
    uint256 amount1In,
    uint256 amount0Out,
    uint256 amount1Out,
    address indexed to
  );
  event Sync(uint112 reserve0, uint112 reserve1);

  function MINIMUM_LIQUIDITY() external pure returns (uint256);

  function factory() external view returns (address);

  function getTokenLocal() external view returns (Token memory);

  function getTokenRemote() external view returns (Token memory);

  function tokenRemoteProxy() external view returns (address);

  function getReserves()
    external
    view
    returns (
      uint112 reserve0,
      uint112 reserve1,
      uint32 blockTimestampLast
    );

  function priceLocalCumulativeLast() external view returns (uint256);

  function priceRemoteCumulativeLast() external view returns (uint256);

  function kLast() external view returns (uint256);

  function mint(address to) external returns (uint256 liquidity);

  function burn(address to) external returns (uint256 amount0, uint256 amount1);

  function swap(
    uint256 amount0Out,
    uint256 amount1Out,
    address to,
    bytes calldata data
  ) external;

  function skim(address to) external;

  function sync() external;

  function initialize(
    Token calldata tokenLocal,
    Token calldata tokenRemote,
    address tokenRemoteProxy
  ) external;
}
