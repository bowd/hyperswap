// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IHyperswapPair} from "../interfaces/IHyperswapPair.sol";
import {IERC20} from "../interfaces/IERC20.sol";

import {SequenceLib} from "./SequenceLib.sol";
import {Token, HyperswapToken, HyperswapLibrary} from "./HyperswapLibrary.sol";
import {TransferHelper} from "./TransferHelper.sol";

import {Shared} from "./Shared.sol";

library Swap { 
    using SequenceLib for SequenceLib.Sequence;

    struct Context {
        bool tokenInRemote;
        uint256 amountIn;
        uint256 amountOut;
        address to;
    }

    function stage1(SequenceLib.Sequence memory seq) public returns (SequenceLib.Sequence memory, SequenceLib.CustodianOperation memory op) {
        Context memory context = abi.decode(seq.context, (Context));
        Token memory tokenLocal =  IHyperswapPair(seq.pair).getTokenLocal();
        Token memory tokenRemote =  IHyperswapPair(seq.pair).getTokenRemote();
        IERC20 tokenRemoteProxy = IERC20(IHyperswapPair(seq.pair).tokenRemoteProxy());

        if (context.tokenInRemote) {
            (seq, op) = seq.addCustodianOp(
                Shared.RemoteOP_LockFunds,
                abi.encode(Shared.TokenTransferOp(tokenRemote.tokenAddr, seq.initiator, context.amountIn))
            );
        } else {
            TransferHelper.safeTransferFrom(
                tokenLocal.tokenAddr, msg.sender, seq.pair, context.amountIn
            );
            IHyperswapPair(seq.pair).swap(
                0, context.amountOut, context.to, new bytes(0)
            );
            (seq, op) = seq.addCustodianOp(
                Shared.RemoteOP_ReleaseFunds,
                abi.encode(Shared.TokenTransferOp(tokenRemote.tokenAddr, seq.initiator, tokenRemoteProxy.balanceOf(context.to)))

            );
        }

        seq.queuedStage = 2;
        return (seq, op);
    }

    function stage2(SequenceLib.Sequence memory seq) public returns (SequenceLib.Sequence memory) {
        Context memory context = abi.decode(seq.context, (Context));
        IERC20 tokenRemoteProxy = IERC20(IHyperswapPair(seq.pair).tokenRemoteProxy());

        if (context.tokenInRemote) {
            tokenRemoteProxy.mint(seq.pair, context.amountIn);
            IHyperswapPair(seq.pair).swap(
                context.amountOut, 0, context.to, new bytes(0)
            );
        } else {
            tokenRemoteProxy.burn(context.to, context.amountOut);
        }

        return seq;
    }
}