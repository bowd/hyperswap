// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

interface IHyperswapBridgeRouter {
    function callCustodian(uint32 domain, bytes32 seqId, uint256 opIndex, uint8 opType, bytes memory payload) external;
    function localDomain() external returns (uint32);
}