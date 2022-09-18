// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {console2 as console} from "forge-std/Test.sol";
import {Router as BridgeRouter} from "@abacus-network/app/contracts/Router.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";

import {IERC20} from "./interfaces/IERC20.sol";
import {IHyperswapCustodian} from "./interfaces/IHyperswapCustodian.sol";

import {Constants} from "./libraries/Constants.sol";

contract HyperswapCustodian is Context, IHyperswapCustodian {
  address public immutable bridgeRouter;

  event OpSuccess(
    bytes32 indexed seqId,
    uint256 opIndex,
    uint8 indexed opType,
    bytes payload
  );
  event OpFailed(
    bytes32 indexed seqId,
    uint256 opIndex,
    uint8 indexed opType,
    bytes payload
  );

  struct TokenTransferOp {
    address token;
    address user;
    uint256 amount;
  }

  constructor(address _bridgeRouter) {
    bridgeRouter = _bridgeRouter;
  }

  modifier onlyBridgeRouter() {
    require(_msgSender() == bridgeRouter, "not allowed");
    _;
  }

  function execute(
    bytes32 seqId,
    uint256 opIndex,
    uint8 opType,
    bytes calldata payload
  ) external onlyBridgeRouter returns (bool) {
    bool success = _execute(opType, payload);
    if (success) {
      emit OpSuccess(seqId, opIndex, opType, payload);
    } else {
      emit OpFailed(seqId, opIndex, opType, payload);
    }
    return success;
  }

  function _execute(uint8 opType, bytes calldata _payload)
    internal
    returns (bool)
  {
    if (opType == Constants.RemoteOP_LockFunds) {
      TokenTransferOp memory payload = abi.decode(_payload, (TokenTransferOp));
      try
        IERC20(payload.token).transferFrom(
          payload.user,
          address(this),
          payload.amount
        )
      returns (bool) {
        return true;
      } catch {
        return false;
      }
    } else if (opType == Constants.RemoteOP_ReleaseFunds) {
      TokenTransferOp memory payload = abi.decode(_payload, (TokenTransferOp));
      try IERC20(payload.token).transfer(payload.user, payload.amount) returns (
        bool
      ) {
        return true;
      } catch {
        return false;
      }
    } else {
      return false;
    }
  }
}
