// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import {SequenceLib} from "../libraries/SequenceLib.sol";

interface IHyperswapBridgeRouter {
  function callCustodian(
    uint32 domain,
    bytes32 seqId,
    uint256 opIndex,
    SequenceLib.CustodianOperation memory op
  ) external;

  function localDomain() external returns (uint32);
}
