// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {console2 as console} from "forge-std/Test.sol";
import {Router as BridgeRouter} from "@abacus-network/app/contracts/Router.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";

import {IHyperswapFactory} from "./interfaces/IHyperswapFactory.sol";
import {IHyperswapRouter} from "./interfaces/IHyperswapRouter.sol";
import {IHyperswapBridgeRouter} from "./interfaces/IHyperswapBridgeRouter.sol";
import {IHyperswapPair} from "./interfaces/IHyperswapPair.sol";
import {IERC20} from "./interfaces/IERC20.sol";

import {Token, HyperswapToken, HyperswapLibrary} from "./libraries/HyperswapLibrary.sol";
import {TransferHelper} from "./libraries/TransferHelper.sol";
import {SequenceLib} from "./libraries/SequenceLib.sol";

import {HyperswapFactory} from "./HyperswapFactory.sol";
import {HyperswapConstants} from "./HyperswapConstants.sol";

contract HyperswapRouter is IHyperswapRouter, Context, HyperswapConstants {
    using HyperswapToken for Token;
    using SequenceLib for SequenceLib.Sequence;

    event CustodianOpQueued(bytes32 indexed seqId, uint256 indexed opIndex, uint32 indexed targetDomain, uint32 opType);
    event CustodianOpFailed(bytes32 indexed seqId, uint256 indexed opIndex, uint32 indexed targetDomain);
    event CustodianOpSucceeded(bytes32 indexed seqId, uint256 indexed opIndex, uint32 indexed targetDomain);

    event SequenceCreated(bytes32 indexed seqId, address indexed pair, address initiator);
    event SequenceTransitioned(bytes32 indexed seqId, uint32 indexed stage);

    address public immutable bridgeRouter;
    uint32 public immutable localDomain;
    address public factory;
    uint256 public nonce;

    mapping(bytes32 => SequenceLib.Sequence) public sequences;
    mapping(bytes32 => SequenceLib.CustodianOperation[]) public sequenceOps;

    struct TokenTransferOp {
        address token;
        address user;
        uint256 amount;
    }

    struct AddLiquidityContext {
        uint256 amountLocalDesired;
        uint256 amountLocalMin;
        uint256 amountRemoteDesired;
        uint256 amountRemoteMin;
        uint256 lpTokensMinted;
        address to;
    }

    struct RemoveLiquidityContext {
        uint256 amountLocalMin;
        uint256 amountRemoteMin;
        uint256 amountLocal;
        uint256 amountRemote;
        uint256 lpTokens;
        address to;
    }

    struct SwapContext {
        bool tokenInRemote;
        uint256 amountIn;
        uint256 amountOut;
        address to;
    }


    modifier ensure(uint256 deadline) {
        require(deadline >= block.timestamp, "HyperswapRouter: EXPIRED");
        _;
    }

    modifier onlyBridgeRouter() {
        require(_msgSender() == bridgeRouter, "not allowed");
        _;
    }

    constructor(address _bridgeRouter, uint32 _localDomain) {
        bridgeRouter = _bridgeRouter;
        localDomain = _localDomain;
    }

    // TODO circual dependency means we can't have nive things.
    function setFactory(address _factory) external {
        factory = _factory;
    }

    receive() external payable {
        revert("Native token transfer ignored");
    }

    function handleCustodianResponse(uint32 domain, bytes32 seqId, uint256 opIndex, bool success) external onlyBridgeRouter {
        SequenceLib.Sequence memory seq = sequences[seqId];
        require(opIndex <= sequenceOps[seqId].length, "opIndex out of range");
        SequenceLib.CustodianOperation memory op = sequenceOps[seqId][opIndex];
        uint32 stageBefore = seq.stage;
        (seq, op) = seq.finishCustodianOp(op, success);
        if (success) {
            emit CustodianOpSucceeded(seqId, opIndex, domain);
        } else {
            emit CustodianOpFailed(seqId, opIndex, domain);
        }
        if (seq.stage != stageBefore) {
            emit SequenceTransitioned(seqId, seq.stage);
        }
        if (seq.seqType == Seq_AddLiquidity) {
            seq = _sequenceTransition_addLiquidity(seqId, seq);
        } else if (seq.seqType == Seq_RemoveLiquidity) {
            seq = _sequenceTransition_removeLiquidity(seqId, seq);
        } else if (seq.seqType == Seq_Swap) {
            seq = _sequenceTransition_swap(seqId, seq);
        } else {
            revert("SeqTransition not defined");
        }

        sequences[seqId] = seq;
        sequenceOps[seqId][opIndex] = op;
    }



    // **** ADD LIQUIDITY ****

    function addLiquidity(
        Token calldata tokenA,
        Token calldata tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) returns (bytes32 seqId) {
        address pair = IHyperswapFactory(factory).getPair(tokenA, tokenB);
        if (pair == address(0)) {
            pair = IHyperswapFactory(factory).createPair(tokenA, tokenB, localDomain);
        }

        SequenceLib.Sequence memory seq;
        if (isLocal(tokenA)) {
            (seqId, seq) = createSequence_addLiquidity(
                pair,
                amountADesired,
                amountBDesired,
                amountAMin,
                amountBMin,
                to
            );
        } else {
            (seqId, seq) = createSequence_addLiquidity(
                pair,
                amountADesired,
                amountBDesired,
                amountAMin,
                amountBMin,
                to
            );
        }

        seq = _sequenceTransition_addLiquidity(seqId, seq);
        sequences[seqId] = seq; 
    }


    function _sequenceTransition_addLiquidity(bytes32 seqId, SequenceLib.Sequence memory seq) internal returns (SequenceLib.Sequence memory){
        if (!seq.canTransition()) return seq;
        if (seq.stage == 1) {
            seq = addLiquidity_stage1(seqId, seq);
        } else if (seq.stage == 2) {
            seq = addLiquidity_stage2(seqId, seq);
        } else if (seq.stage == 3) {
            seq = addLiquidity_stage3(seqId, seq);
        }
        return seq;
    }

    function addLiquidity_stage1(bytes32 seqId, SequenceLib.Sequence memory seq) internal returns (SequenceLib.Sequence memory) {
        AddLiquidityContext memory context = abi.decode(seq.context, (AddLiquidityContext));
        Token memory tokenLocal =  IHyperswapPair(seq.pair).getTokenLocal();
        Token memory tokenRemote =  IHyperswapPair(seq.pair).getTokenRemote();
        // Escrow funds locally
        TransferHelper.safeTransferFrom(tokenLocal.tokenAddr, seq.initiator, address(this), context.amountLocalDesired);
        seq = _dispatchCustodianOp(
            seqId, 
            seq, 
            RemoteOP_LockFunds,
            abi.encode(TokenTransferOp(tokenRemote.tokenAddr, seq.initiator, context.amountRemoteDesired)),
            tokenRemote.domainID
        );
        seq.queuedStage = 2;
        return seq;
    }


    function addLiquidity_stage2(bytes32 seqId, SequenceLib.Sequence memory seq) internal returns (SequenceLib.Sequence memory) {
        AddLiquidityContext memory context = abi.decode(seq.context, (AddLiquidityContext));
        Token memory tokenLocal =  IHyperswapPair(seq.pair).getTokenLocal();
        Token memory tokenRemote =  IHyperswapPair(seq.pair).getTokenRemote();
        IERC20 tokenRemoteProxy = IERC20(IHyperswapPair(seq.pair).tokenRemoteProxy());

        tokenRemoteProxy.mint(context.to, context.amountRemoteDesired);

        (uint256 amountLocal, uint256 amountRemote) = _getAddLiquidityAmounts(
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
        if (tokenRemoteProxy.balanceOf(seq.initiator) > 0) {
            seq = _dispatchCustodianOp(
                seqId,
                seq,
                RemoteOP_ReleaseFunds,
                abi.encode(TokenTransferOp(tokenRemote.tokenAddr, seq.initiator, tokenRemoteProxy.balanceOf(seq.initiator))),
                tokenRemote.domainID
            );
        }

        uint256 liquidity = IHyperswapPair(seq.pair).mint(context.to);
        context.lpTokensMinted = liquidity;

        seq.context = abi.encode(context);
        seq.queuedStage = 3;
        return seq;
    }

    function addLiquidity_stage3(bytes32 seqId, SequenceLib.Sequence memory seq) internal returns (SequenceLib.Sequence memory) {
        TokenTransferOp memory op = abi.decode(sequenceOps[seqId][1].payload, (TokenTransferOp));
        IERC20 tokenRemoteProxy = IERC20(IHyperswapPair(seq.pair).tokenRemoteProxy());
        tokenRemoteProxy.burn(seq.initiator, op.amount);
        return seq;
    }

    function createSequence_addLiquidity(
        address pair,
        uint256 amountLocalDesired,
        uint256 amountRemoteDesired,
        uint256 amountLocalMin,
        uint256 amountRemoteMin,
        address to
    ) internal returns (bytes32 seqId, SequenceLib.Sequence memory seq) {
        return _createSequence(
            pair,
            Seq_AddLiquidity,
            abi.encode(
                AddLiquidityContext(
                    amountLocalDesired,
                    amountLocalMin, 
                    amountRemoteDesired, 
                    amountRemoteMin, 
                    0,
                    to
                )
            )
        );
    }

    function _getAddLiquidityAmounts(
        Token memory tokenA,
        Token memory tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin
    ) internal virtual returns (uint256 amountA, uint256 amountB) {
        // create the pair if it doesn"t exist yet
        (uint256 reserveA, uint256 reserveB) = HyperswapLibrary.getReserves(factory, tokenA, tokenB);
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

    // **** REMOVE LIQUIDITY ****
    function removeLiquidity(
        Token calldata tokenA,
        Token calldata tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) public virtual override ensure(deadline) returns (bytes32 seqId) {
        address pair = IHyperswapFactory(factory).getPair(tokenA, tokenB);
        require(pair != address(0));

        SequenceLib.Sequence memory seq;
        if (isLocal(tokenA)) {
            (seqId, seq) = createSequence_removeLiquidity(
                pair,
                amountAMin,
                amountBMin,
                liquidity,
                to
            );
        } else {
            (seqId, seq) = createSequence_removeLiquidity(
                pair,
                amountAMin,
                amountBMin,
                liquidity,
                to
            );
        }

        seq = _sequenceTransition_removeLiquidity(seqId, seq);
        sequences[seqId] = seq; 

        // address pair = HyperswapLibrary.pairFor(factory, tokenA, tokenB);
        // IHyperswapPair(pair).transferFrom(msg.sender, pair, liquidity); // send liquidity to pair
        // (uint256 amount0, uint256 amount1) = IHyperswapPair(pair).burn(to);
        // (Token memory token0,) = HyperswapLibrary.sortTokens(tokenA, tokenB);
        // (amountA, amountB) = tokenA.eq(token0) ? (amount0, amount1) : (amount1, amount0);
        // require(amountA >= amountAMin, "HyperswapRouter: INSUFFICIENT_A_AMOUNT");
        // require(amountB >= amountBMin, "HyperswapRouter: INSUFFICIENT_B_AMOUNT");
    }
    function removeLiquidityWithPermit(
        Token calldata tokenA,
        Token calldata tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external virtual override returns (bytes32 seqId) {
        address pair = HyperswapLibrary.pairFor(factory, tokenA, tokenB);
        uint256 value = approveMax ? type(uint256).max : liquidity;
        IHyperswapPair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        return removeLiquidity(tokenA, tokenB, liquidity, amountAMin, amountBMin, to, deadline);
    }

    function _sequenceTransition_removeLiquidity(bytes32 seqId, SequenceLib.Sequence memory seq) internal returns (SequenceLib.Sequence memory){
        if (!seq.canTransition()) return seq;
        if (seq.stage == 1) {
            seq = removeLiquidity_stage1(seqId, seq);
        } else if (seq.stage == 2) {
            seq = removeLiquidity_stage2(seqId, seq);
        }
        return seq;
    }

    function removeLiquidity_stage1(bytes32 seqId, SequenceLib.Sequence memory seq) internal returns (SequenceLib.Sequence memory) {
        RemoveLiquidityContext memory context = abi.decode(seq.context, (RemoveLiquidityContext));
        Token memory tokenRemote =  IHyperswapPair(seq.pair).getTokenRemote();
        IERC20 tokenRemoteProxy = IERC20(IHyperswapPair(seq.pair).tokenRemoteProxy());

        IHyperswapPair(seq.pair).transferFrom(seq.initiator, seq.pair, context.lpTokens); // send liquidity to pair
        (uint256 amountLocal, uint256 amountRemote) = IHyperswapPair(seq.pair).burn(context.to);
        // (Token memory token0,) = HyperswapLibrary.sortTokens(tokenA, tokenB);
        require(amountLocal >= context.amountLocalMin, "HyperswapRouter: INSUFFICIENT_A_AMOUNT");
        require(amountRemote >= context.amountRemoteMin, "HyperswapRouter: INSUFFICIENT_A_AMOUNT");
        // Escrow funds locally
        // TransferHelper.safeTransferFrom(tokenLocal.tokenAddr, seq.initiator, address(this), context.amountLocalDesired);
        seq = _dispatchCustodianOp(
            seqId, 
            seq, 
            RemoteOP_ReleaseFunds,
            abi.encode(TokenTransferOp(tokenRemote.tokenAddr, seq.initiator, tokenRemoteProxy.balanceOf(context.to))),
            tokenRemote.domainID
        );
        seq.queuedStage = 2;
        return seq;
    }

    function removeLiquidity_stage2(bytes32 seqId, SequenceLib.Sequence memory seq) internal returns (SequenceLib.Sequence memory) {
        TokenTransferOp memory op = abi.decode(sequenceOps[seqId][0].payload, (TokenTransferOp));
        IERC20 tokenRemoteProxy = IERC20(IHyperswapPair(seq.pair).tokenRemoteProxy());
        tokenRemoteProxy.burn(seq.initiator, op.amount);
        return seq;
    }



    function createSequence_removeLiquidity(
        address pair,
        uint256 amountLocalMin,
        uint256 amountRemoteMin,
        uint256 lpTokens,
        address to
    ) internal returns (bytes32 seqId, SequenceLib.Sequence memory seq) {
        return _createSequence(
            pair,
            Seq_RemoveLiquidity,
            abi.encode(
                RemoveLiquidityContext(
                    amountLocalMin, 
                    amountRemoteMin, 
                    0,
                    0,
                    lpTokens,
                    to
                )
            )
        );
    }

    // **** SWAP ****
    function _swap(uint256[] memory amounts, Token[] memory path, address _to) internal virtual returns (bytes32 seqId) {
        // XXX: Currently support only 1:1 token swaps, no routing, path.length is always 2
        address pair = IHyperswapFactory(factory).getPair(path[0], path[1]);
        SequenceLib.Sequence memory seq;
        (seqId, seq) = _createSequence(
            pair,
            Seq_Swap,
            abi.encode(
                SwapContext(
                    !isLocal(path[0]),
                    amounts[0],
                    amounts[1],
                    _to
                )
            )
        );

        seq = _sequenceTransition_swap(seqId, seq);
        sequences[seqId] = seq; 

        // TransferHelper.safeTransferFrom(
        //     path[0].tokenAddr, msg.sender, HyperswapLibrary.pairFor(factory, path[0], path[1]), amounts[0]
        // );
        /// (Token memory input, Token memory output) = (path[0], path[1]);
        /// (Token memory token0,) = HyperswapLibrary.sortTokens(input, output);
        /// uint256 amountOut = amounts[1];
        /// uint256 amountIn
        /// (uint256 amount0Out, uint256 amount1Out) = input.eq(token0) ? (uint(0), amountOut) : (amountOut, uint(0));
        /// IHyperswapPair(HyperswapLibrary.pairFor(factory, input, output)).swap(
        ///     amount0Out, amount1Out, _to, new bytes(0)
        /// );
    }

    function _sequenceTransition_swap(bytes32 seqId, SequenceLib.Sequence memory seq) internal returns (SequenceLib.Sequence memory){
        if (!seq.canTransition()) return seq;
        if (seq.stage == 1) {
            seq = swap_stage1(seqId, seq);
        } else if (seq.stage == 2) {
            seq = swap_stage2(seqId, seq);
        }
        return seq;
    }

    function swap_stage1(bytes32 seqId, SequenceLib.Sequence memory seq) internal returns (SequenceLib.Sequence memory) {
        SwapContext memory context = abi.decode(seq.context, (SwapContext));
        Token memory tokenLocal =  IHyperswapPair(seq.pair).getTokenLocal();
        Token memory tokenRemote =  IHyperswapPair(seq.pair).getTokenRemote();
        IERC20 tokenRemoteProxy = IERC20(IHyperswapPair(seq.pair).tokenRemoteProxy());

        if (context.tokenInRemote) {
            seq = _dispatchCustodianOp(
                seqId, 
                seq, 
                RemoteOP_LockFunds,
                abi.encode(TokenTransferOp(tokenRemote.tokenAddr, seq.initiator, context.amountIn)),
                tokenRemote.domainID
            );
        } else {
            TransferHelper.safeTransferFrom(
                tokenLocal.tokenAddr, msg.sender, seq.pair, context.amountIn
            );
            IHyperswapPair(seq.pair).swap(
                0, context.amountOut, context.to, new bytes(0)
            );
            seq = _dispatchCustodianOp(
                seqId, 
                seq, 
                RemoteOP_ReleaseFunds,
                abi.encode(TokenTransferOp(tokenRemote.tokenAddr, seq.initiator, tokenRemoteProxy.balanceOf(context.to))),
                tokenRemote.domainID
            );
        }

        seq.queuedStage = 2;
        return seq;
    }

    function swap_stage2(bytes32 seqId, SequenceLib.Sequence memory seq) internal returns (SequenceLib.Sequence memory) {
        SwapContext memory context = abi.decode(seq.context, (SwapContext));
        IERC20 tokenRemoteProxy = IERC20(IHyperswapPair(seq.pair).tokenRemoteProxy());

        if (context.tokenInRemote) {
            tokenRemoteProxy.mint(seq.pair, context.amountIn);
            IHyperswapPair(seq.pair).swap(
                context.amountOut, 0, context.to, new bytes(0)
            );
        } else {
            tokenRemoteProxy.burn(context.to, context.amountOut);
        }

        // Sequence ends here.
        return seq;
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        Token[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) returns (bytes32 seqId) {
        // XXX: Currently support only 1:1 token swaps, no routing
        require(path.length == 2, "only supports 1:1 swaps");
        uint256[] memory amounts = HyperswapLibrary.getAmountsOut(factory, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, "HyperswapRouter: INSUFFICIENT_OUTPUT_AMOUNT");
        return _swap(amounts, path, to);
    }

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        Token[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) returns (bytes32 seqId) {
        // XXX: Currently support only 1:1 token swaps, no routing
        require(path.length == 2, "only supports 1:1 swaps");
        uint256[] memory amounts = HyperswapLibrary.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= amountInMax, "HyperswapRouter: EXCESSIVE_INPUT_AMOUNT");
        return _swap(amounts, path, to);
    }

    function createSequence_swap(
        address pair,
        bool tokenInRemote,
        uint256 amountIn,
        uint256 amountOut,
        address to
    ) internal returns (bytes32 seqId, SequenceLib.Sequence memory seq) {
    }


    // **** LIBRARY FUNCTIONS ****

    function _createSequence(address pair, uint8 seqType, bytes memory context) internal returns (bytes32 seqId, SequenceLib.Sequence memory seq) {
        seq = SequenceLib.create(seqType, pair, msg.sender, context);
        seqId = keccak256(abi.encode(block.number, seq.initiator, seq.pair, nonce++));
        emit SequenceCreated(seqId, seq.pair, seq.initiator);
    }

    function _dispatchCustodianOp(bytes32 seqId, SequenceLib.Sequence memory seq, uint8 opType, bytes memory payload, uint32 targetDomain) internal returns (SequenceLib.Sequence memory) {
        SequenceLib.CustodianOperation memory op;
        (seq, op) = seq.addCustodianOp(opType, payload);
        sequenceOps[seqId].push(op);
        uint256 opIndex = sequenceOps[seqId].length - 1;
        emit CustodianOpQueued(seqId, opIndex, targetDomain, opType);
        IHyperswapBridgeRouter(bridgeRouter).callCustodian(targetDomain, seqId, opIndex, opType, payload);
        return seq;
    }


    function isLocal(Token memory token) internal view returns (bool) {
        return localDomain == token.domainID;
    }

    function quote(uint256 amountA, uint256 reserveA, uint256 reserveB) public pure virtual override returns (uint256 amountB) {
        return HyperswapLibrary.quote(amountA, reserveA, reserveB);
    }

    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        public
        pure
        virtual
        override
        returns (uint256 amountOut)
    {
        return HyperswapLibrary.getAmountOut(amountIn, reserveIn, reserveOut);
    }

    function getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut)
        public
        pure
        virtual
        override
        returns (uint256 amountIn)
    {
        return HyperswapLibrary.getAmountIn(amountOut, reserveIn, reserveOut);
    }

    function getAmountsOut(uint256 amountIn, Token[] memory path)
        public
        view
        virtual
        override
        returns (uint256[] memory amounts)
    {
        return HyperswapLibrary.getAmountsOut(factory, amountIn, path);
    }

    function getAmountsIn(uint256 amountOut, Token[] memory path)
        public
        view
        virtual
        override
        returns (uint256[] memory amounts)
    {
        return HyperswapLibrary.getAmountsIn(factory, amountOut, path);
    }
}
