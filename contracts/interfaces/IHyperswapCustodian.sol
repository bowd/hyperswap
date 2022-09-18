// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

interface IHyperswapCustodian {
  function execute(
    bytes32 seqId,
    uint256 opIndex,
    uint8 opType,
    bytes calldata payload
  ) external returns (bool);
}
