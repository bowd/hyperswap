// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { MockInbox } from "./MockInbox.sol";

contract MockOutbox {

  uint32 public localDomain;
  mapping(uint32 => MockInbox) public inboxes;

  constructor(address _inbox, uint32 _localDomain) {
    localDomain = _localDomain;
    addInbox(_inbox);
  }

  function addInbox(address _inbox) public {
    MockInbox inbox = MockInbox(_inbox);
    require(address(inboxes[inbox.localDomain()]) == address(0), "Inbox already registered for domain");
    inboxes[inbox.localDomain()] = inbox;
  }

  function dispatch(
    uint32 _destinationDomain,
    bytes32 _recipientAddress,
    bytes calldata _messageBody
  ) external returns (uint256) {
    return inboxes[_destinationDomain].addPendingMessage(
      localDomain,
      addressToBytes32(msg.sender),
      _recipientAddress,
      _messageBody
    );    
  }

  function addressToBytes32(address _addr) internal pure returns (bytes32) {
    return bytes32(uint256(uint160(_addr)));
  }
}