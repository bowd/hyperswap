// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IHyperswapPair} from "./interfaces/IHyperswapPair.sol";
import {IHyperswapFactory} from "./interfaces/IHyperswapFactory.sol";
import {IHyperswapCallee} from "./interfaces/IHyperswapCallee.sol";
import {IERC20} from "./interfaces/IERC20.sol";

import {HyperswapERC20} from "./HyperswapERC20.sol";

import {Math} from "./libraries/Math.sol";
import {UQ112x112} from "./libraries/UQ112x112.sol";
import {Token} from "./libraries/HyperswapLibrary.sol";

contract HyperswapPair is IHyperswapPair, HyperswapERC20 {
    using UQ112x112 for uint224;

    uint256 public constant MINIMUM_LIQUIDITY = 10**3;
    bytes4 private constant SELECTOR = bytes4(keccak256(bytes("transfer(address,uint256)")));

    address public factory;
    Token public token0;
    Token public token1;

    uint112 private reserve0;           // uses single storage slot, accessible via getReserves
    uint112 private reserve1;          // uses single storage slot, accessible via getReserves
    uint32  private blockTimestampLast;     // uses single storage slot, accessible via getReserves

    uint256 public price0CumulativeLast;
    uint256 public price1CumulativeLast;
    uint256 public kLast; // reserve0 * reserve1, as of immediately after the most recent liquidity event

    uint256 private unlocked = 1;
    modifier lock() {
        require(unlocked == 1, "Hyperswap: LOCKED");
        unlocked = 0;
        _;
        unlocked = 1;
    }

    function getReserves() public view returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }

    function getToken0() external view returns(Token memory) {
        return token0;
    }

    function getToken1() external view returns(Token memory) {
        return token1;
    }

    function _safeTransfer(address token, address to, uint256 value) private {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(SELECTOR, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "Hyperswap: TRANSFER_FAILED");
    }

    constructor() {
        factory = msg.sender;
    }

    // called once by the factory at time of deployment
    function initialize(Token calldata _token0, Token calldata _token1) external {
        require(msg.sender == factory, "Hyperswap: FORBIDDEN"); // sufficient check
        token0 = _token0;
        token1 = _token1;
    }

    // update reserves and, on the first call per block, price accumulators
    function _update(uint256 balanceLocal, uint256 balanceRemote, uint112 _reserve0, uint112 _reserve1) private {
        require(balanceLocal <= type(uint112).max && balanceRemote <= type(uint112).max, "Hyperswap: OVERFLOW");
        uint32 blockTimestamp = uint32(block.timestamp % 2**32);
        uint32 timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired
        if (timeElapsed > 0 && _reserve0 != 0 && _reserve1 != 0) {
            // * never overflows, and + overflow is desired
            price0CumulativeLast += uint(UQ112x112.encode(_reserve1).uqdiv(_reserve0)) * timeElapsed;
            price1CumulativeLast += uint(UQ112x112.encode(_reserve0).uqdiv(_reserve1)) * timeElapsed;
        }
        reserve0 = uint112(balanceLocal);
        reserve1 = uint112(balanceRemote);
        blockTimestampLast = blockTimestamp;
        emit Sync(reserve0, reserve1);
    }

    // if fee is on, mint liquidity equivalent to 1/6th of the growth in sqrt(k)
    function _mintFee(uint112 _reserve0, uint112 _reserve1) private returns (bool feeOn) {
        address feeTo = IHyperswapFactory(factory).feeTo();
        feeOn = feeTo != address(0);
        uint256 _kLast = kLast; // gas savings
        if (feeOn) {
            if (_kLast != 0) {
                uint256 rootK = Math.sqrt(uint(_reserve0) * _reserve1);
                uint256 rootKLast = Math.sqrt(_kLast);
                if (rootK > rootKLast) {
                    uint256 numerator = totalSupply * (rootK - rootKLast);
                    uint256 denominator = (rootK * 5) + rootKLast;
                    uint256 liquidity = numerator / denominator;
                    if (liquidity > 0) _mint(feeTo, liquidity);
                }
            }
        } else if (_kLast != 0) {
            kLast = 0;
        }
    }

    // this low-level function should be called from a contract which performs important safety checks
    function mint(address to) external lock returns (uint256 liquidity) {
        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings
        uint256 balanceLocal = IERC20(token0.tokenAddr).balanceOf(address(this));
        uint256 balanceRemote = IERC20(token1.tokenAddr).balanceOf(address(this));
        uint256 amount0 = balanceLocal - _reserve0;
        uint256 amount1 = balanceRemote - _reserve1;

        bool feeOn = _mintFee(_reserve0, _reserve1);
        uint256 _totalSupply = totalSupply; // gas savings, must be defined here since totalSupply can update in _mintFee
        if (_totalSupply == 0) {
            liquidity = Math.sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY;
           _mint(address(0), MINIMUM_LIQUIDITY); // permanently lock the first MINIMUM_LIQUIDITY tokens
        } else {
            liquidity = Math.min((amount0 * _totalSupply) / _reserve0, (amount1 * _totalSupply) / _reserve1);
        }
        require(liquidity > 0, "Hyperswap: INSUFFICIENT_LIQUIDITY_MINTED");
        _mint(to, liquidity);

        _update(balanceLocal, balanceRemote, _reserve0, _reserve1);
        if (feeOn) kLast = uint(reserve0) * reserve1; // reserve0 and reserve1 are up-to-date
        emit Mint(msg.sender, amount0, amount1);
    }

    // this low-level function should be called from a contract which performs important safety checks
    function burn(address to) external lock returns (uint256 amount0, uint256 amount1) {
        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings
        address _token0 = token0.tokenAddr;                      // gas savings
        address _token1 = token1.tokenAddr;                      // gas savings
        uint256 balanceLocal = IERC20(_token0).balanceOf(address(this));
        uint256 balanceRemote = IERC20(_token1).balanceOf(address(this));
        uint256 liquidity = balanceOf[address(this)];

        bool feeOn = _mintFee(_reserve0, _reserve1);
        uint256 _totalSupply = totalSupply; // gas savings, must be defined here since totalSupply can update in _mintFee
        amount0 = (liquidity * balanceLocal) / _totalSupply; // using balances ensures pro-rata distribution
        amount1 = (liquidity * balanceRemote) / _totalSupply; // using balances ensures pro-rata distribution
        require(amount0 > 0 && amount1 > 0, "Hyperswap: INSUFFICIENT_LIQUIDITY_BURNED");
        _burn(address(this), liquidity);
        _safeTransfer(_token0, to, amount0);
        _safeTransfer(_token1, to, amount1);
        balanceLocal = IERC20(_token0).balanceOf(address(this));
        balanceRemote = IERC20(_token1).balanceOf(address(this));

        _update(balanceLocal, balanceRemote, _reserve0, _reserve1);
        if (feeOn) kLast = uint(reserve0) * reserve1; // reserve0 and reserve1 are up-to-date
        emit Burn(msg.sender, amount0, amount1, to);
    }

    // this low-level function should be called from a contract which performs important safety checks
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external lock {
        require(amount0Out > 0 || amount1Out > 0, "Hyperswap: INSUFFICIENT_OUTPUT_AMOUNT");
        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings
        require(amount0Out < _reserve0 && amount1Out < _reserve1, "Hyperswap: INSUFFICIENT_LIQUIDITY");

        uint256 balanceLocal;
        uint256 balanceRemote;
        { // scope for _token{0,1}, avoids stack too deep errors
        address _token0 = token0.tokenAddr;
        address _token1 = token1.tokenAddr;
        require(to != _token0 && to != _token1, "Hyperswap: INVALID_TO");
        if (amount0Out > 0) _safeTransfer(_token0, to, amount0Out); // optimistically transfer tokens
        if (amount1Out > 0) _safeTransfer(_token1, to, amount1Out); // optimistically transfer tokens
        if (data.length > 0) IHyperswapCallee(to).hyperswapCall(msg.sender, amount0Out, amount1Out, data);
        balanceLocal = IERC20(_token0).balanceOf(address(this));
        balanceRemote = IERC20(_token1).balanceOf(address(this));
        }
        uint256 amount0In = balanceLocal > _reserve0 - amount0Out ? balanceLocal - (_reserve0 - amount0Out) : 0;
        uint256 amount1In = balanceRemote > _reserve1 - amount1Out ? balanceRemote - (_reserve1 - amount1Out) : 0;
        require(amount0In > 0 || amount1In > 0, "Hyperswap: INSUFFICIENT_INPUT_AMOUNT");
        { // scope for reserve{0,1}Adjusted, avoids stack too deep errors
        uint256 balanceLocalAdjusted = (balanceLocal * 1000) - (amount0In * 3);
        uint256 balanceRemoteAdjusted = (balanceRemote * 1000) - (amount1In * 3);
        require(balanceLocalAdjusted * balanceRemoteAdjusted >= uint(_reserve0) * _reserve1 * 1000**2, "Hyperswap: K");
        }

        _update(balanceLocal, balanceRemote, _reserve0, _reserve1);
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }

    // force balances to match reserves
    function skim(address to) external lock {
        address _token0 = token0.tokenAddr; // gas savings
        address _token1 = token1.tokenAddr; // gas savings
        _safeTransfer(_token0, to, IERC20(_token0).balanceOf(address(this)) - reserve0);
        _safeTransfer(_token1, to, IERC20(_token1).balanceOf(address(this)) - reserve1);
    }

    // force reserves to match balances
    function sync() external lock {
        _update(
            IERC20(token0.tokenAddr).balanceOf(address(this)), 
            IERC20(token1.tokenAddr).balanceOf(address(this)), 
            reserve0, 
            reserve1
        );
    }
}
