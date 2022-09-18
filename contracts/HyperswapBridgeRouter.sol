// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Router as BridgeRouter} from "@abacus-network/app/contracts/Router.sol";
import {IHyperswapCustodian} from "./interfaces/IHyperswapCustodian.sol";
import {IHyperswapRouter} from "./interfaces/IHyperswapRouter.sol";
import {IHyperswapBridgeRouter} from "./interfaces/IHyperswapBridgeRouter.sol";
import {SequenceLib} from "./libraries/SequenceLib.sol";

contract HyperswapBridgeRouter is IHyperswapBridgeRouter, BridgeRouter {
  uint8 public constant CUSTODIAN_MESSAGE = 0x11;
  uint8 public constant CUSTODIAN_RESPONSE = 0x12;

  address public custodian;
  address public router;
  bool public isHub;

  struct Message {
    uint8 messageType;
    bytes payload;
  }

  struct CustodianMessage {
    bytes32 seqId;
    uint256 opIndex;
    uint8 opType;
    bytes payload;
  }

  struct CustodianResponse {
    bytes32 seqId;
    uint256 opIndex;
    bool success;
  }

  modifier onlyHyperswapRouter() {
    require(isHub && _msgSender() == router, "not allowed");
    _;
  }

  function initialize(
    address _abacusConnectionManager,
    address _custodian,
    address _router,
    bool _isHub
  ) external initializer {
    __Router_initialize(_abacusConnectionManager);
    if (_isHub) {
      require(_router != address(0), "router must be set");
      router = _router;
      isHub = true;
    } else {
      require(_custodian != address(0), "custodian must be set");
      custodian = _custodian;
      isHub = false;
    }
  }

  function _handle(
    uint32 domain,
    bytes32,
    bytes memory _message
  ) internal override {
    Message memory message = abi.decode(_message, (Message));
    if (message.messageType == CUSTODIAN_MESSAGE) {
      require(isHub == false, "Only spokes handle CUSTOIDAN_MESSAGE");
      CustodianMessage memory cMessage = abi.decode(
        message.payload,
        (CustodianMessage)
      );
      bool success = IHyperswapCustodian(custodian).execute(
        cMessage.seqId,
        cMessage.opIndex,
        cMessage.opType,
        cMessage.payload
      );
      CustodianResponse memory cResponse = CustodianResponse(
        cMessage.seqId,
        cMessage.opIndex,
        success
      );
      Message memory response = Message(
        CUSTODIAN_RESPONSE,
        abi.encode(cResponse)
      );
      _dispatch(domain, abi.encode(response));
    } else if (message.messageType == CUSTODIAN_RESPONSE) {
      require(isHub, "Only hubs handle CUSTODIAN_RESPONSE");
      CustodianResponse memory cResponse = abi.decode(
        message.payload,
        (CustodianResponse)
      );
      IHyperswapRouter(router).handleCustodianResponse(
        domain,
        cResponse.seqId,
        cResponse.opIndex,
        cResponse.success
      );
    } else {
      revert("messageType not supported");
    }
  }

  function callCustodian(
    uint32 domain,
    bytes32 seqId,
    uint256 opIndex,
    SequenceLib.CustodianOperation memory op
  ) external onlyHyperswapRouter {
    CustodianMessage memory cMessage = CustodianMessage(
      seqId,
      opIndex,
      op.opType,
      op.payload
    );
    Message memory message = Message(CUSTODIAN_MESSAGE, abi.encode(cMessage));
    _dispatch(domain, abi.encode(message));
  }

  function localDomain() external view returns (uint32) {
    return _localDomain();
  }
}
