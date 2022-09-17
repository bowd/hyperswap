// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {console2 as console} from "forge-std/Test.sol";
import {Router as BridgeRouter} from "@abacus-network/app/contracts/Router.sol";
import {IERC20} from "./interfaces/IERC20.sol";

import {SequenceLib} from "./libraries/SequenceLib.sol";
import {HyperswapConstants} from "./HyperswapConstants.sol";

contract HyperswapRemoteRouter is BridgeRouter, HyperswapConstants {
    event OpSuccess(bytes32 indexed seqId, uint256 opIndex, uint8 indexed opType, bytes payload);
    event OpFailed(bytes32 indexed seqId, uint256 opIndex, uint8 indexed opType, bytes payload);

    struct TokenTransferOp {
        address token;
        address user;
        uint256 amount;
    }

    function initialize(address _abacusConnectionManager) external initializer {
        __Router_initialize(_abacusConnectionManager);
    }

    function _handle(
        uint32 domain,
        bytes32,
        bytes memory message
    ) internal override {
        (bytes32 seqId, uint256 opIndex, SequenceLib.RemoteOperation memory op) = abi.decode(message, (bytes32, uint256, SequenceLib.RemoteOperation));
        bool success = _execute(op);

        if (success) {
            emit OpSuccess(seqId, opIndex, op.remoteOpType, op.payload);
        } else {
            emit OpFailed(seqId, opIndex, op.remoteOpType, op.payload);
        }

        _dispatch(domain, abi.encode(seqId, opIndex, success));
    }

    function _execute(SequenceLib.RemoteOperation memory op) internal returns (bool) {
        if (op.remoteOpType == RemoteOP_EscrowFunds) {
            TokenTransferOp memory payload = abi.decode(op.payload, (TokenTransferOp));
            try IERC20(payload.token).transferFrom(payload.user, address(this), payload.amount) returns (bool) {
                return true;
            } catch {
                return false;
            } 
        } else if (op.remoteOpType == RemoteOP_ReleaseDifference || op.remoteOpType == RemoteOP_Withdraw) {
            TokenTransferOp memory payload = abi.decode(op.payload, (TokenTransferOp));
            try IERC20(payload.token).transfer(payload.user, payload.amount) returns (bool) {
                return true;
            } catch {
                return false;
            }
        } else {
            return false;
        }
    }
}