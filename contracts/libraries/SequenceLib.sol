// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

library SequenceLib {
  struct CustodianOperation {
    uint8 opType;
    uint256 deadline;
    bytes payload;
    bool completed;
    bool succeeded;
  }

  struct Sequence {
    // Cross-chain sequence
    uint8 seqType;
    address pair;
    address initiator;
    bytes context;
    uint32 remoteOpsQueued;
    uint32 remoteOpsFinished;
    uint32 remoteOpsFailed;
    uint32 stage;
    uint32 queuedStage;
  }

  function create(
    uint8 seqType,
    address pair,
    address initiator,
    bytes memory context
  ) internal pure returns (Sequence memory) {
    return Sequence(seqType, pair, initiator, context, 0, 0, 0, 1, 1);
  }

  function hasPendingCustodianOps(Sequence memory self)
    internal
    pure
    returns (bool)
  {
    return self.remoteOpsFinished < self.remoteOpsQueued;
  }

  function canTransition(Sequence memory self) internal pure returns (bool) {
    return self.queuedStage == self.stage && self.remoteOpsFailed == 0;
  }

  function getUpdatedStage(Sequence memory self)
    internal
    pure
    returns (uint32)
  {
    return
      self.remoteOpsFinished < self.remoteOpsQueued || self.remoteOpsFailed > 0
        ? self.stage
        : self.queuedStage;
  }

  function addCustodianOp(
    Sequence memory self,
    uint8 opType,
    bytes memory payload
  ) internal view returns (Sequence memory, CustodianOperation memory) {
    CustodianOperation memory remoteOp = CustodianOperation(
      opType,
      block.timestamp + 1000000, // TODO: What should the deadline be / how should it play in?
      payload,
      false,
      false
    );
    self.remoteOpsQueued += 1;
    return (self, remoteOp);
  }

  function finishCustodianOp(
    Sequence memory self,
    CustodianOperation memory remoteOp,
    bool success
  ) internal pure returns (Sequence memory, CustodianOperation memory) {
    remoteOp.completed = true;
    remoteOp.succeeded = success;

    self.remoteOpsFinished++;
    if (success == false) {
      self.remoteOpsFailed++;
    }
    self.stage = getUpdatedStage(self);
    return (self, remoteOp);
  }
}
