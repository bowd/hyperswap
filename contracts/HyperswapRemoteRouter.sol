// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {console2 as console} from "forge-std/Test.sol";
import {Router as BridgeRouter} from "@abacus-network/app/contracts/Router.sol";
import {IERC20} from "./interfaces/IERC20.sol";

contract HyperswapRemoteRouter is BridgeRouter {
    event OpSuccess(bytes32 indexed xopID, uint8 indexed opType, bytes opData);
    event OpFailed(bytes32 indexed xopID, uint8 indexed opType, bytes opData);

    uint8 constant OP_EscrowFunds = 0x22;
    uint8 constant OP_ReleaseDifference = 0x23;
    uint8 constant OP_Withdraw = 0x24;

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
        (bytes32 xopID, uint8 opType, bytes memory opData) = abi.decode(message, (bytes32, uint8, bytes));
        bool success = _execute(opType, opData);

        if (success) {
            emit OpSuccess(xopID, opType, opData);
        } else {
            emit OpFailed(xopID, opType, opData);
        }

        _dispatch(domain, abi.encode(xopID, opType, success, opData));
    }

    function _execute(uint8 opType, bytes memory opData) internal returns (bool) {
        if (opType == OP_EscrowFunds) {
            TokenTransferOp memory op = abi.decode(opData, (TokenTransferOp));
            try IERC20(op.token).transferFrom(op.user, address(this), op.amount) returns (bool) {
                return true;
            } catch {
                return false;
            } 
        } else if (opType == OP_ReleaseDifference || opType == OP_Withdraw) {
            TokenTransferOp memory op = abi.decode(opData, (TokenTransferOp));
            try IERC20(op.token).transfer(op.user, op.amount) returns (bool) {
                return true;
            } catch {
                return false;
            }
        } else {
            return false;
        }
    }
}