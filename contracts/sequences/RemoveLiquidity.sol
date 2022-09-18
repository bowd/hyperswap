// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IHyperswapPair} from "../interfaces/IHyperswapPair.sol";
import {IERC20} from "../interfaces/IERC20.sol";

import {SequenceLib} from "../libraries/SequenceLib.sol";
import {Token, HyperswapToken, HyperswapLibrary} from "../libraries/HyperswapLibrary.sol";
import {TransferHelper} from "../libraries/TransferHelper.sol";

import {Constants} from "../libraries/Constants.sol";

library RemoveLiquidity {
  using SequenceLib for SequenceLib.Sequence;

  struct Context {
    uint256 amountLocalMin;
    uint256 amountRemoteMin;
    uint256 amountLocal;
    uint256 amountRemote;
    uint256 lpTokens;
    address to;
  }

  struct TokenTransferOp {
    address token;
    address user;
    uint256 amount;
  }

  function createSequence(
    uint256 nonce,
    address pair,
    uint256 amountLocalMin,
    uint256 amountRemoteMin,
    uint256 lpTokens,
    address to
  ) public view returns (bytes32 seqId, SequenceLib.Sequence memory seq) {
    seq = SequenceLib.create(
      Constants.Seq_RemoveLiquidity,
      pair,
      msg.sender,
      abi.encode(Context(amountLocalMin, amountRemoteMin, 0, 0, lpTokens, to))
    );
    seqId = keccak256(abi.encode(block.number, seq.initiator, seq.pair, nonce));
  }

  function stage1(SequenceLib.Sequence memory seq)
    public
    returns (
      SequenceLib.Sequence memory,
      SequenceLib.CustodianOperation memory op
    )
  {
    Context memory context = abi.decode(seq.context, (Context));
    Token memory tokenRemote = IHyperswapPair(seq.pair).getTokenRemote();
    IERC20 tokenRemoteProxy = IERC20(
      IHyperswapPair(seq.pair).tokenRemoteProxy()
    );

    IHyperswapPair(seq.pair).transferFrom(
      seq.initiator,
      seq.pair,
      context.lpTokens
    ); // send liquidity to pair
    (uint256 amountLocal, uint256 amountRemote) = IHyperswapPair(seq.pair).burn(
      context.to
    );
    require(
      amountLocal >= context.amountLocalMin,
      "HyperswapRouter: INSUFFICIENT_A_AMOUNT"
    );
    require(
      amountRemote >= context.amountRemoteMin,
      "HyperswapRouter: INSUFFICIENT_A_AMOUNT"
    );
    // Escrow funds locally
    (seq, op) = seq.addCustodianOp(
      Constants.RemoteOP_ReleaseFunds,
      abi.encode(
        TokenTransferOp(
          tokenRemote.tokenAddr,
          seq.initiator,
          tokenRemoteProxy.balanceOf(context.to)
        )
      )
    );
    seq.queuedStage = 2;
    return (seq, op);
  }

  function stage2(
    SequenceLib.Sequence memory seq,
    SequenceLib.CustodianOperation memory op
  ) public returns (SequenceLib.Sequence memory) {
    TokenTransferOp memory payload = abi.decode(op.payload, (TokenTransferOp));
    IERC20 tokenRemoteProxy = IERC20(
      IHyperswapPair(seq.pair).tokenRemoteProxy()
    );
    tokenRemoteProxy.burn(seq.initiator, payload.amount);
    return seq;
  }
}
