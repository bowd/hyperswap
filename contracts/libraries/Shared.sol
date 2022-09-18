// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {SequenceLib} from "./SequenceLib.sol";

library Shared {
    uint8 constant RemoteOP_LockFunds = 0x11;
    uint8 constant RemoteOP_ReleaseFunds = 0x12;

    uint8 constant Seq_AddLiquidity = 0x21;
    uint8 constant Seq_RemoveLiquidity = 0x22;
    uint8 constant Seq_Swap = 0x23;

    struct TokenTransferOp {
        address token;
        address user;
        uint256 amount;
    }

    function createSequence(address pair, uint8 seqType, bytes memory context, uint256 nonce) public view returns (bytes32 seqId, SequenceLib.Sequence memory seq) {
        seq = SequenceLib.create(seqType, pair, msg.sender, context);
        seqId = keccak256(abi.encode(block.number, seq.initiator, seq.pair, nonce));
        // emit SequenceCreated(seqId, seq.pair, seq.initiator);
    }
}