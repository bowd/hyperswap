// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IHyperswapPair} from "../interfaces/IHyperswapPair.sol";
import {IERC20} from "../interfaces/IERC20.sol";

import {SequenceLib} from "./SequenceLib.sol";
import {Token, HyperswapToken, HyperswapLibrary} from "./HyperswapLibrary.sol";
import {TransferHelper} from "./TransferHelper.sol";

import {Shared} from "./Shared.sol";

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

    function createSequence(
        uint256 nonce,
        address pair,
        uint256 amountLocalMin,
        uint256 amountRemoteMin,
        uint256 lpTokens,
        address to
    ) internal view returns (bytes32 seqId, SequenceLib.Sequence memory seq) {
        return Shared.createSequence(
            pair,
            Shared.Seq_RemoveLiquidity,
            abi.encode(
                Context(
                    amountLocalMin, 
                    amountRemoteMin, 
                    0,
                    0,
                    lpTokens,
                    to
                )
            ),
            nonce
        );
    }

    function stage1(SequenceLib.Sequence memory seq) internal returns (SequenceLib.Sequence memory, SequenceLib.CustodianOperation memory op) {
        Context memory context = abi.decode(seq.context, (Context));
        Token memory tokenRemote =  IHyperswapPair(seq.pair).getTokenRemote();
        IERC20 tokenRemoteProxy = IERC20(IHyperswapPair(seq.pair).tokenRemoteProxy());

        IHyperswapPair(seq.pair).transferFrom(seq.initiator, seq.pair, context.lpTokens); // send liquidity to pair
        (uint256 amountLocal, uint256 amountRemote) = IHyperswapPair(seq.pair).burn(context.to);
        // (Token memory token0,) = HyperswapLibrary.sortTokens(tokenA, tokenB);
        require(amountLocal >= context.amountLocalMin, "HyperswapRouter: INSUFFICIENT_A_AMOUNT");
        require(amountRemote >= context.amountRemoteMin, "HyperswapRouter: INSUFFICIENT_A_AMOUNT");
        // Escrow funds locally
        // TransferHelper.safeTransferFrom(tokenLocal.tokenAddr, seq.initiator, address(this), context.amountLocalDesired);
        (seq, op) = seq.addCustodianOp(
            Shared.RemoteOP_ReleaseFunds,
            abi.encode(Shared.TokenTransferOp(tokenRemote.tokenAddr, seq.initiator, tokenRemoteProxy.balanceOf(context.to)))
        );
        seq.queuedStage = 2;
        return (seq, op);
    }

    function stage2(SequenceLib.Sequence memory seq, SequenceLib.CustodianOperation memory op) internal returns (SequenceLib.Sequence memory) {
        Shared.TokenTransferOp memory payload = abi.decode(op.payload, (Shared.TokenTransferOp));
        IERC20 tokenRemoteProxy = IERC20(IHyperswapPair(seq.pair).tokenRemoteProxy());
        tokenRemoteProxy.burn(seq.initiator, payload.amount);
        return seq;
    }
}