// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

contract HyperswapConstants {
    uint8 constant RemoteOP_EscrowFunds = 0x11;
    uint8 constant RemoteOP_ReleaseDifference = 0x12;
    uint8 constant RemoteOP_Withdraw = 0x13;

    uint8 constant Seq_AddLiquidity = 0x21;
    uint8 constant Seq_RemoveLiquidity = 0x22;
    uint8 constant Seq_Swap = 0x23;
}