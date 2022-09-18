// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

interface IProxyTokenFactory {
  function deployProxyToken(
    address owner,
    uint32 domain,
    address remoteToken,
    address pair
  ) external returns (address);
}
