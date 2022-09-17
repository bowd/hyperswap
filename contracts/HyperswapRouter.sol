// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IHyperswapFactory} from "./interfaces/IHyperswapFactory.sol";
import {IHyperswapRouter} from "./interfaces/IHyperswapRouter.sol";
import {IHyperswapPair} from "./interfaces/IHyperswapPair.sol";
import {IERC20} from "./interfaces/IERC20.sol";

import {Token, HyperswapToken, HyperswapLibrary} from "./libraries/HyperswapLibrary.sol";
import {TransferHelper} from "./libraries/TransferHelper.sol";


contract HyperswapRouter is IHyperswapRouter {
    using HyperswapToken for Token;
    address public immutable factory;

    modifier ensure(uint256 deadline) {
        require(deadline >= block.timestamp, "HyperswapRouter: EXPIRED");
        _;
    }

    constructor(address _factory) {
        factory = _factory;
    }

    receive() external payable {
        revert("Native token transfer ignored");
    }

    // **** ADD LIQUIDITY ****
    function _addLiquidity(
        Token memory tokenA,
        Token memory tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin
    ) internal virtual returns (uint256 amountA, uint256 amountB) {
        // create the pair if it doesn"t exist yet
        if (IHyperswapFactory(factory).getPair(tokenA, tokenB) == address(0)) {
            IHyperswapFactory(factory).createPair(tokenA, tokenB);
        }
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
    function addLiquidity(
        Token calldata tokenA,
        Token calldata tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        (amountA, amountB) = _addLiquidity(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin);
        address pair = HyperswapLibrary.pairFor(factory, tokenA, tokenB);
        TransferHelper.safeTransferFrom(tokenA.tokenAddr, msg.sender, pair, amountA);
        TransferHelper.safeTransferFrom(tokenB.tokenAddr, msg.sender, pair, amountB);
        liquidity = IHyperswapPair(pair).mint(to);
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
    ) public virtual override ensure(deadline) returns (uint256 amountA, uint256 amountB) {
        address pair = HyperswapLibrary.pairFor(factory, tokenA, tokenB);
        IHyperswapPair(pair).transferFrom(msg.sender, pair, liquidity); // send liquidity to pair
        (uint256 amount0, uint256 amount1) = IHyperswapPair(pair).burn(to);
        (Token memory token0,) = HyperswapLibrary.sortTokens(tokenA, tokenB);
        (amountA, amountB) = tokenA.eq(token0) ? (amount0, amount1) : (amount1, amount0);
        require(amountA >= amountAMin, "HyperswapRouter: INSUFFICIENT_A_AMOUNT");
        require(amountB >= amountBMin, "HyperswapRouter: INSUFFICIENT_B_AMOUNT");
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
    ) external virtual override returns (uint256 amountA, uint256 amountB) {
        address pair = HyperswapLibrary.pairFor(factory, tokenA, tokenB);
        uint256 value = approveMax ? type(uint256).max : liquidity;
        IHyperswapPair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        (amountA, amountB) = removeLiquidity(tokenA, tokenB, liquidity, amountAMin, amountBMin, to, deadline);
    }

    // **** SWAP ****
    // requires the initial amount to have already been sent to the first pair
    function _swap(uint256[] memory amounts, Token[] memory path, address _to) internal virtual {
        for (uint256 i; i < path.length - 1; i++) {
            (Token memory input, Token memory output) = (path[i], path[i + 1]);
            (Token memory token0,) = HyperswapLibrary.sortTokens(input, output);
            uint256 amountOut = amounts[i + 1];
            (uint256 amount0Out, uint256 amount1Out) = input.eq(token0) ? (uint(0), amountOut) : (amountOut, uint(0));
            address to = i < path.length - 2 ? HyperswapLibrary.pairFor(factory, output, path[i + 2]) : _to;
            IHyperswapPair(HyperswapLibrary.pairFor(factory, input, output)).swap(
                amount0Out, amount1Out, to, new bytes(0)
            );
        }
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        Token[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) returns (uint256[] memory amounts) {
        amounts = HyperswapLibrary.getAmountsOut(factory, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, "HyperswapRouter: INSUFFICIENT_OUTPUT_AMOUNT");
        TransferHelper.safeTransferFrom(
            path[0].tokenAddr, msg.sender, HyperswapLibrary.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, to);
    }

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        Token[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) returns (uint256[] memory amounts) {
        amounts = HyperswapLibrary.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= amountInMax, "HyperswapRouter: EXCESSIVE_INPUT_AMOUNT");
        TransferHelper.safeTransferFrom(
            path[0].tokenAddr, msg.sender, HyperswapLibrary.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, to);
    }

    // **** SWAP (supporting fee-on-transfer tokens) ****
    // requires the initial amount to have already been sent to the first pair
    // function _swapSupportingFeeOnTransferTokens(Token[] memory path, address _to) internal virtual {
    //     for (uint256 i; i < path.length - 1; i++) {
    //         (Token memory input, Token memory output) = (path[i], path[i + 1]);
    //         (Token memory token0,) = HyperswapLibrary.sortTokens(input, output);
    //         IHyperswapPair pair = IHyperswapPair(HyperswapLibrary.pairFor(factory, input, output));
    //         uint256 amountInput;
    //         uint256 amountOutput;
    //         { // scope to avoid stack too deep errors
    //         (uint256 reserve0, uint256 reserve1,) = pair.getReserves();
    //         (uint256 reserveInput, uint256 reserveOutput) = input.eq(token0) ? (reserve0, reserve1) : (reserve1, reserve0);
    //         amountInput = IERC20(input.tokenAddr).balanceOf(address(pair)) - reserveInput;
    //         amountOutput = HyperswapLibrary.getAmountOut(amountInput, reserveInput, reserveOutput);
    //         }
    //         (uint256 amount0Out, uint256 amount1Out) = input.eq(token0) ? (uint(0), amountOutput) : (amountOutput, uint(0));
    //         address to = i < path.length - 2 ? HyperswapLibrary.pairFor(factory, output, path[i + 2]) : _to;
    //         pair.swap(amount0Out, amount1Out, to, new bytes(0));
    //     }
    // }
    // function swapExactTokensForTokensSupportingFeeOnTransferTokens(
    //     uint256 amountIn,
    //     uint256 amountOutMin,
    //     Token[] calldata path,
    //     address to,
    //     uint256 deadline
    // ) external virtual override ensure(deadline) {
    //     TransferHelper.safeTransferFrom(
    //         path[0].tokenAddr, msg.sender, HyperswapLibrary.pairFor(factory, path[0], path[1]), amountIn
    //     );
    //     uint256 balanceBefore = IERC20(path[path.length - 1].tokenAddr).balanceOf(to);
    //     _swapSupportingFeeOnTransferTokens(path, to);
    //     require(
    //         IERC20(path[path.length - 1].tokenAddr).balanceOf(to) - balanceBefore >= amountOutMin,
    //         "HyperswapRouter: INSUFFICIENT_OUTPUT_AMOUNT"
    //     );
    // }

    // **** LIBRARY FUNCTIONS ****
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
