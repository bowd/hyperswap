// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Context} from "@openzeppelin/contracts/utils/Context.sol";

import {IHyperswapFactory} from "./interfaces/IHyperswapFactory.sol";
import {IHyperswapRouter} from "./interfaces/IHyperswapRouter.sol";
import {IHyperswapBridgeRouter} from "./interfaces/IHyperswapBridgeRouter.sol";
import {IHyperswapPair} from "./interfaces/IHyperswapPair.sol";
import {IERC20} from "./interfaces/IERC20.sol";

import {Token, HyperswapToken, HyperswapLibrary} from "./libraries/HyperswapLibrary.sol";
import {TransferHelper} from "./libraries/TransferHelper.sol";
import {SequenceLib} from "./libraries/SequenceLib.sol";
import {Constants} from "./libraries/Constants.sol";

import {AddLiquidity} from "./sequences/AddLiquidity.sol";
import {RemoveLiquidity} from "./sequences/RemoveLiquidity.sol";
import {Swap} from "./sequences/Swap.sol";

contract HyperswapRouter is IHyperswapRouter, Context {
  using HyperswapToken for Token;
  using SequenceLib for SequenceLib.Sequence;

  event CustodianOpQueued(
    bytes32 indexed seqId,
    uint256 indexed opIndex,
    uint32 indexed targetDomain
  );
  event SequenceCreated(
    bytes32 indexed seqId,
    address indexed pair,
    address initiator
  );
  event SequenceTransitioned(bytes32 indexed seqId, uint32 indexed stage);

  address public immutable bridgeRouter;
  uint32 public immutable localDomain;
  address public factory;
  uint256 public nonce;

  mapping(bytes32 => SequenceLib.Sequence) public sequences;
  mapping(bytes32 => SequenceLib.CustodianOperation[]) public sequenceOps;

  modifier ensure(uint256 deadline) {
    require(deadline >= block.timestamp, "EXPIRED");
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
    revert("native transfer");
  }

  function handleCustodianResponse(
    uint32,
    bytes32 seqId,
    uint256 opIndex,
    bool success
  ) external onlyBridgeRouter {
    SequenceLib.Sequence memory seq = sequences[seqId];
    require(opIndex <= sequenceOps[seqId].length, "index out of bounds");
    SequenceLib.CustodianOperation memory op = sequenceOps[seqId][opIndex];
    uint32 stageBefore = seq.stage;
    (seq, op) = seq.finishCustodianOp(op, success);
    if (seq.stage != stageBefore) {
      emit SequenceTransitioned(seqId, seq.stage);
    }

    seq = _sequenceTransition(seqId, seq);
    sequences[seqId] = seq;
    sequenceOps[seqId][opIndex] = op;
  }

  function _sequenceTransition(bytes32 seqId, SequenceLib.Sequence memory seq)
    internal
    returns (SequenceLib.Sequence memory)
  {
    if (!seq.canTransition()) return seq;
    SequenceLib.CustodianOperation memory nextOp;
    if (seq.seqType == Constants.Seq_AddLiquidity) {
      if (seq.stage == 1) {
        (seq, nextOp) = AddLiquidity.stage1(seq);
      } else if (seq.stage == 2) {
        (seq, nextOp) = AddLiquidity.stage2(seq);
      } else if (seq.stage == 3) {
        seq = AddLiquidity.stage3(seq, sequenceOps[seqId][1]);
      }
    } else if (seq.seqType == Constants.Seq_RemoveLiquidity) {
      if (seq.stage == 1) {
        (seq, nextOp) = RemoveLiquidity.stage1(seq);
      } else if (seq.stage == 2) {
        seq = RemoveLiquidity.stage2(seq, sequenceOps[seqId][0]);
      }
    } else if (seq.seqType == Constants.Seq_Swap) {
      if (seq.stage == 1) {
        (seq, nextOp) = Swap.stage1(seq);
      } else if (seq.stage == 2) {
        seq = Swap.stage2(seq);
      }
    } else {
      revert("!SEQ");
    }

    if (nextOp.opType != 0) {
      uint32 remoteDomain = IHyperswapPair(seq.pair).getTokenRemote().domainID;
      sequenceOps[seqId].push(nextOp);
      uint256 opIndex = sequenceOps[seqId].length - 1;
      emit CustodianOpQueued(seqId, opIndex, remoteDomain);
      IHyperswapBridgeRouter(bridgeRouter).callCustodian(
        remoteDomain,
        seqId,
        opIndex,
        nextOp
      );
    }

    return seq;
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
      (seqId, seq) = AddLiquidity.createSequence(
        nonce++,
        pair,
        amountADesired,
        amountBDesired,
        amountAMin,
        amountBMin,
        to
      );
    } else {
      (seqId, seq) = AddLiquidity.createSequence(
        nonce++,
        pair,
        amountADesired,
        amountBDesired,
        amountAMin,
        amountBMin,
        to
      );
    }

    sequences[seqId] = _sequenceTransition(seqId, seq);
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
      (seqId, seq) = RemoveLiquidity.createSequence(
        nonce++,
        pair,
        amountAMin,
        amountBMin,
        liquidity,
        to
      );
    } else {
      (seqId, seq) = RemoveLiquidity.createSequence(
        nonce++,
        pair,
        amountAMin,
        amountBMin,
        liquidity,
        to
      );
    }

    sequences[seqId] = _sequenceTransition(seqId, seq);
  }

  function removeLiquidityWithPermit(
    Token calldata tokenA,
    Token calldata tokenB,
    uint256 liquidity,
    uint256 amountAMin,
    uint256 amountBMin,
    address to,
    uint256 deadline,
    bool approveMax,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external virtual override returns (bytes32 seqId) {
    address pair = HyperswapLibrary.pairFor(factory, tokenA, tokenB);
    uint256 value = approveMax ? type(uint256).max : liquidity;
    IHyperswapPair(pair).permit(
      msg.sender,
      address(this),
      value,
      deadline,
      v,
      r,
      s
    );
    return
      removeLiquidity(
        tokenA,
        tokenB,
        liquidity,
        amountAMin,
        amountBMin,
        to,
        deadline
      );
  }

  // **** SWAP ****
  function _swap(
    uint256[] memory amounts,
    Token[] memory path,
    address _to
  ) internal virtual returns (bytes32 seqId) {
    // XXX: Currently support only 1:1 token swaps, no routing, path.length is always 2
    address pair = IHyperswapFactory(factory).getPair(path[0], path[1]);
    SequenceLib.Sequence memory seq;
    (seqId, seq) = Swap.createSequence(
      nonce++,
      pair,
      !isLocal(path[0]),
      amounts[0],
      amounts[1],
      _to
    );

    sequences[seqId] = _sequenceTransition(seqId, seq);
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
    uint256[] memory amounts = HyperswapLibrary.getAmountsOut(
      factory,
      amountIn,
      path
    );
    require(
      amounts[amounts.length - 1] >= amountOutMin,
      "INSUFFICIENT_OUTPUT_AMOUNT"
    );
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
    require(path.length == 2, "!1:M");
    uint256[] memory amounts = HyperswapLibrary.getAmountsIn(
      factory,
      amountOut,
      path
    );
    require(amounts[0] <= amountInMax, "EXCESSIVE_INPUT_AMOUNT");
    return _swap(amounts, path, to);
  }

  // **** LIBRARY FUNCTIONS ****

  function _dispatchCustodianOp(
    uint32 remoteDomain,
    bytes32 seqId,
    SequenceLib.Sequence memory seq,
    SequenceLib.CustodianOperation memory op
  ) internal returns (SequenceLib.Sequence memory) {}

  function isLocal(Token memory token) internal view returns (bool) {
    return localDomain == token.domainID;
  }

  function quote(
    uint256 amountA,
    uint256 reserveA,
    uint256 reserveB
  ) public pure virtual override returns (uint256 amountB) {
    return HyperswapLibrary.quote(amountA, reserveA, reserveB);
  }

  function getAmountOut(
    uint256 amountIn,
    uint256 reserveIn,
    uint256 reserveOut
  ) external pure virtual override returns (uint256 amountOut) {
    return HyperswapLibrary.getAmountOut(amountIn, reserveIn, reserveOut);
  }

  function getAmountIn(
    uint256 amountOut,
    uint256 reserveIn,
    uint256 reserveOut
  ) external pure virtual override returns (uint256 amountIn) {
    return HyperswapLibrary.getAmountIn(amountOut, reserveIn, reserveOut);
  }

  function getAmountsOut(uint256 amountIn, Token[] memory path)
    external
    view
    virtual
    override
    returns (uint256[] memory amounts)
  {
    return HyperswapLibrary.getAmountsOut(factory, amountIn, path);
  }

  function getAmountsIn(uint256 amountOut, Token[] memory path)
    external
    view
    virtual
    override
    returns (uint256[] memory amounts)
  {
    return HyperswapLibrary.getAmountsIn(factory, amountOut, path);
  }
}
