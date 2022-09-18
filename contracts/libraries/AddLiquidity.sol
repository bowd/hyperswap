// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IHyperswapPair} from "../interfaces/IHyperswapPair.sol";
import {IERC20} from "../interfaces/IERC20.sol";

import {SequenceLib} from "./SequenceLib.sol";
import {Token, HyperswapToken, HyperswapLibrary} from "./HyperswapLibrary.sol";
import {TransferHelper} from "./TransferHelper.sol";

import {Shared} from "./Shared.sol";

library AddLiquidity { 
    using SequenceLib for SequenceLib.Sequence;

    struct Context {
        uint256 amountLocalDesired;
        uint256 amountLocalMin;
        uint256 amountRemoteDesired;
        uint256 amountRemoteMin;
        uint256 lpTokensMinted;
        address to;
    }

    function createSequence(
        uint256 nonce,
        address pair,
        uint256 amountLocalDesired,
        uint256 amountRemoteDesired,
        uint256 amountLocalMin,
        uint256 amountRemoteMin,
        address to
    ) external view returns (bytes32 seqId, SequenceLib.Sequence memory seq) {
        return Shared.createSequence(
            pair,
            Shared.Seq_AddLiquidity,
            abi.encode(
                Context(
                    amountLocalDesired,
                    amountLocalMin, 
                    amountRemoteDesired, 
                    amountRemoteMin, 
                    0,
                    to
                )
            ),
            nonce
        );
    }

    function getAddLiquidityAmounts(
        address pair,
        Token memory tokenA,
        Token memory tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin
    ) private view returns (uint256 amountA, uint256 amountB) {
        // create the pair if it doesn"t exist yet
        (uint256 reserveA, uint256 reserveB) = HyperswapLibrary.getReservesForPair(pair, tokenA, tokenB);
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint256 amountBOptimal = HyperswapLibrary.quote(amountADesired, reserveA, reserveB);
            if (amountBOptimal <= amountBDesired) {
                require(amountBOptimal >= amountBMin, "HyperswapRouter: INSUFFICIENT_B_AMOUNT");
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint256 amountAOptimal = HyperswapLibrary.quote(amountBDesired, reserveB, reserveA);
                assert(amountAOptimal <= amountADesired);
                require(amountAOptimal >= amountAMin, "HyperswapRouter: INSUFFICIENT_A_AMOUNT");
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }

    function stage1(SequenceLib.Sequence memory seq) external returns (SequenceLib.Sequence memory, SequenceLib.CustodianOperation memory op) {
        Context memory context = abi.decode(seq.context, (Context));
        Token memory tokenLocal =  IHyperswapPair(seq.pair).getTokenLocal();
        Token memory tokenRemote =  IHyperswapPair(seq.pair).getTokenRemote();
        // Escrow funds locally
        TransferHelper.safeTransferFrom(tokenLocal.tokenAddr, seq.initiator, address(this), context.amountLocalDesired);
        (seq, op) = seq.addCustodianOp(
            Shared.RemoteOP_LockFunds,
            abi.encode(Shared.TokenTransferOp(tokenRemote.tokenAddr, seq.initiator, context.amountRemoteDesired))
        );
        seq.queuedStage = 2;
        return (seq, op);
    }


    function stage2(SequenceLib.Sequence memory seq) external returns (SequenceLib.Sequence memory, SequenceLib.CustodianOperation memory op) {
        Context memory context = abi.decode(seq.context, (Context));
        Token memory tokenLocal =  IHyperswapPair(seq.pair).getTokenLocal();
        Token memory tokenRemote =  IHyperswapPair(seq.pair).getTokenRemote();
        IERC20 tokenRemoteProxy = IERC20(IHyperswapPair(seq.pair).tokenRemoteProxy());

        tokenRemoteProxy.mint(context.to, context.amountRemoteDesired);

        (uint256 amountLocal, uint256 amountRemote) = getAddLiquidityAmounts(
            seq.pair,
            tokenLocal, 
            tokenRemote, 
            context.amountLocalDesired, 
            context.amountRemoteDesired, 
            context.amountLocalMin, 
            context.amountRemoteMin
        );
        TransferHelper.safeTransfer(tokenLocal.tokenAddr, seq.pair, amountLocal);
        if (amountLocal < context.amountLocalDesired) {
            TransferHelper.safeTransferFrom(tokenLocal.tokenAddr, address(this), seq.initiator, context.amountLocalDesired - amountLocal);
        }

        TransferHelper.safeTransferFrom(address(tokenRemoteProxy), seq.initiator, seq.pair, amountRemote);
        uint256 remBalance = tokenRemoteProxy.balanceOf(seq.initiator);
        
        if (remBalance > 0) {
            (seq, op) = seq.addCustodianOp(
                Shared.RemoteOP_ReleaseFunds,
                abi.encode(Shared.TokenTransferOp(tokenRemote.tokenAddr, seq.initiator, remBalance))
            );
        }

        uint256 liquidity = IHyperswapPair(seq.pair).mint(context.to);
        context.lpTokensMinted = liquidity;

        seq.context = abi.encode(context);
        seq.queuedStage = 3;
        return (seq, op);
    }

    function stage3(SequenceLib.Sequence memory seq, SequenceLib.CustodianOperation memory op) external returns (SequenceLib.Sequence memory) {
        Shared.TokenTransferOp memory payload = abi.decode(op.payload, (Shared.TokenTransferOp));
        IERC20 tokenRemoteProxy = IERC20(IHyperswapPair(seq.pair).tokenRemoteProxy());
        tokenRemoteProxy.burn(seq.initiator, payload.amount);
        return seq;
    }
}