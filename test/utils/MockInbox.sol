// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface IMessageRecipient {
  function handle(
    uint32 _origin,
    bytes32 _sender,
    bytes calldata _message
  ) external;
}

contract MockInbox {
  uint32 public localDomain;

  struct PendingMessage {
    uint32 sourceDomain;
    bytes32 sender;
    bytes32 recipient;
    bytes messageBody;
  }

  constructor(uint32 _localDomain) {
    localDomain = _localDomain;
  }

  mapping(uint => PendingMessage) pendingMessages;
  uint totalMessages = 0;
  uint messageProcessed = 0;

  function addPendingMessage(
    uint32 _sourceDomain,
    bytes32 _sender,
    bytes32 _recipient,
    bytes memory _messageBody
  ) external returns (uint256) {
    pendingMessages[totalMessages] = PendingMessage(
      _sourceDomain,
      _sender,
      _recipient,
      _messageBody
    );
    totalMessages += 1;
    return totalMessages;
  }

  function processNextPendingMessage() public {
    PendingMessage memory pendingMessage = pendingMessages[messageProcessed];

    address recipient = bytes32ToAddress(pendingMessage.recipient);
    
    IMessageRecipient(recipient).handle(
      pendingMessage.sourceDomain,
      pendingMessage.sender,
      pendingMessage.messageBody
    );
    messageProcessed += 1;
  }

  function bytes32ToAddress(bytes32 _buf) internal pure returns (address) {
    return address(uint160(uint256(_buf)));
  }
}