// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {console2 as console} from "forge-std/Test.sol";

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
  bytes4 private constant SELECTOR =
    bytes4(keccak256(bytes("transfer(address,uint256)")));

  address public factory;
  Token public tokenLocal;
  Token public tokenRemote;
  address public tokenRemoteProxy; // A proxy dummy ERC20 token used to track balances

  uint112 private reserveLocal; // uses single storage slot, accessible via getReserves
  uint112 private reserveRemote; // uses single storage slot, accessible via getReserves
  uint32 private blockTimestampLast; // uses single storage slot, accessible via getReserves

  uint256 public priceLocalCumulativeLast;
  uint256 public priceRemoteCumulativeLast;
  uint256 public kLast; // reserveLocal * reserveRemote, as of immediately after the most recent liquidity event

  uint256 private unlocked = 1;
  modifier lock() {
    require(unlocked == 1, "Hyperswap: LOCKED");
    unlocked = 0;
    _;
    unlocked = 1;
  }

  function getReserves()
    public
    view
    returns (
      uint112 _reserveLocal,
      uint112 _reserveRemote,
      uint32 _blockTimestampLast
    )
  {
    _reserveLocal = reserveLocal;
    _reserveRemote = reserveRemote;
    _blockTimestampLast = blockTimestampLast;
  }

  function getTokenLocal() external view returns (Token memory) {
    return tokenLocal;
  }

  function getTokenRemote() external view returns (Token memory) {
    return tokenRemote;
  }

  function _safeTransfer(
    address token,
    address to,
    uint256 value
  ) private {
    (bool success, bytes memory data) = token.call(
      abi.encodeWithSelector(SELECTOR, to, value)
    );
    require(
      success && (data.length == 0 || abi.decode(data, (bool))),
      "Hyperswap: TRANSFER_FAILED"
    );
  }

  constructor() {
    factory = msg.sender;
  }

  // called once by the factory at time of deployment
  function initialize(
    Token calldata _tokenLocal,
    Token calldata _tokenRemote,
    address _tokenRemoteProxy
  ) external {
    require(msg.sender == factory, "Hyperswap: FORBIDDEN"); // sufficient check
    tokenLocal = _tokenLocal;
    tokenRemote = _tokenRemote;
    tokenRemoteProxy = _tokenRemoteProxy;
  }

  // update reserves and, on the first call per block, price accumulators
  function _update(
    uint256 balanceLocal,
    uint256 balanceRemote,
    uint112 _reserveLocal,
    uint112 _reserveRemote
  ) private {
    require(
      balanceLocal <= type(uint112).max && balanceRemote <= type(uint112).max,
      "Hyperswap: OVERFLOW"
    );
    uint32 blockTimestamp = uint32(block.timestamp % 2**32);
    uint32 timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired
    if (timeElapsed > 0 && _reserveLocal != 0 && _reserveRemote != 0) {
      // * never overflows, and + overflow is desired
      priceLocalCumulativeLast +=
        uint256(UQ112x112.encode(_reserveRemote).uqdiv(_reserveLocal)) *
        timeElapsed;
      priceRemoteCumulativeLast +=
        uint256(UQ112x112.encode(_reserveLocal).uqdiv(_reserveRemote)) *
        timeElapsed;
    }
    reserveLocal = uint112(balanceLocal);
    reserveRemote = uint112(balanceRemote);
    blockTimestampLast = blockTimestamp;
    emit Sync(reserveLocal, reserveRemote);
  }

  // if fee is on, mint liquidity equivalent to 1/6th of the growth in sqrt(k)
  function _mintFee(uint112 _reserveLocal, uint112 _reserveRemote)
    private
    returns (bool feeOn)
  {
    address feeTo = IHyperswapFactory(factory).feeTo();
    feeOn = feeTo != address(0);
    uint256 _kLast = kLast; // gas savings
    if (feeOn) {
      if (_kLast != 0) {
        uint256 rootK = Math.sqrt(uint256(_reserveLocal) * _reserveRemote);
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
    (uint112 _reserveLocal, uint112 _reserveRemote, ) = getReserves(); // gas savings
    uint256 balanceLocal = IERC20(tokenLocal.tokenAddr).balanceOf(
      address(this)
    );
    uint256 balanceRemote = IERC20(tokenRemoteProxy).balanceOf(address(this));
    uint256 amount0 = balanceLocal - _reserveLocal;
    uint256 amount1 = balanceRemote - _reserveRemote;

    console.log(amount0);
    console.log(amount1);

    bool feeOn = _mintFee(_reserveLocal, _reserveRemote);
    uint256 _totalSupply = totalSupply; // gas savings, must be defined here since totalSupply can update in _mintFee
    if (_totalSupply == 0) {
      liquidity = Math.sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY;
      _mint(address(0), MINIMUM_LIQUIDITY); // permanently lock the first MINIMUM_LIQUIDITY tokens
    } else {
      liquidity = Math.min(
        (amount0 * _totalSupply) / _reserveLocal,
        (amount1 * _totalSupply) / _reserveRemote
      );
    }
    require(liquidity > 0, "Hyperswap: INSUFFICIENT_LIQUIDITY_MINTED");
    _mint(to, liquidity);

    _update(balanceLocal, balanceRemote, _reserveLocal, _reserveRemote);
    if (feeOn) kLast = uint256(reserveLocal) * reserveRemote; // reserveLocal and reserveRemote are up-to-date
    emit Mint(msg.sender, amount0, amount1);
  }

  // this low-level function should be called from a contract which performs important safety checks
  function burn(address to)
    external
    lock
    returns (uint256 amountRemote, uint256 amountLocal)
  {
    (uint112 _reserveLocal, uint112 _reserveRemote, ) = getReserves(); // gas savings
    address _tokenLocal = tokenLocal.tokenAddr; // gas savings
    address _tokenRemote = tokenRemoteProxy;
    uint256 balanceLocal = IERC20(_tokenLocal).balanceOf(address(this));
    uint256 balanceRemote = IERC20(_tokenRemote).balanceOf(address(this));
    uint256 liquidity = balanceOf[address(this)];

    bool feeOn = _mintFee(_reserveLocal, _reserveRemote);
    uint256 _totalSupply = totalSupply; // gas savings, must be defined here since totalSupply can update in _mintFee
    amountLocal = (liquidity * balanceLocal) / _totalSupply; // using balances ensures pro-rata distribution
    amountRemote = (liquidity * balanceRemote) / _totalSupply; // using balances ensures pro-rata distribution
    require(
      amountLocal > 0 && amountRemote > 0,
      "Hyperswap: INSUFFICIENT_LIQUIDITY_BURNED"
    );
    _burn(address(this), liquidity);
    _safeTransfer(_tokenLocal, to, amountLocal);
    _safeTransfer(_tokenRemote, to, amountRemote);
    balanceLocal = IERC20(_tokenLocal).balanceOf(address(this));
    balanceRemote = IERC20(_tokenRemote).balanceOf(address(this));

    _update(balanceLocal, balanceRemote, _reserveLocal, _reserveRemote);
    if (feeOn) kLast = uint256(reserveLocal) * reserveRemote; // reserveLocal and reserveRemote are up-to-date
    emit Burn(msg.sender, amountLocal, amountRemote, to);
  }

  // this low-level function should be called from a contract which performs important safety checks
  function swap(
    uint256 amount0Out,
    uint256 amount1Out,
    address to,
    bytes calldata data
  ) external lock {
    require(
      amount0Out > 0 || amount1Out > 0,
      "Hyperswap: INSUFFICIENT_OUTPUT_AMOUNT"
    );
    (uint112 _reserveLocal, uint112 _reserveRemote, ) = getReserves(); // gas savings
    require(
      amount0Out < _reserveLocal && amount1Out < _reserveRemote,
      "Hyperswap: INSUFFICIENT_LIQUIDITY"
    );

    uint256 balanceLocal;
    uint256 balanceRemote;
    {
      // scope for _token{0,1}, avoids stack too deep errors
      address _tokenLocal = tokenLocal.tokenAddr;
      address _tokenRemote = tokenRemoteProxy;
      require(to != _tokenLocal && to != _tokenRemote, "Hyperswap: INVALID_TO");
      if (amount0Out > 0) _safeTransfer(_tokenLocal, to, amount0Out); // optimistically transfer tokens
      if (amount1Out > 0) _safeTransfer(_tokenRemote, to, amount1Out); // optimistically transfer tokens
      if (data.length > 0)
        IHyperswapCallee(to).hyperswapCall(
          msg.sender,
          amount0Out,
          amount1Out,
          data
        );
      balanceLocal = IERC20(_tokenLocal).balanceOf(address(this));
      balanceRemote = IERC20(_tokenRemote).balanceOf(address(this));
    }
    uint256 amount0In = balanceLocal > _reserveLocal - amount0Out
      ? balanceLocal - (_reserveLocal - amount0Out)
      : 0;
    uint256 amount1In = balanceRemote > _reserveRemote - amount1Out
      ? balanceRemote - (_reserveRemote - amount1Out)
      : 0;
    require(
      amount0In > 0 || amount1In > 0,
      "Hyperswap: INSUFFICIENT_INPUT_AMOUNT"
    );
    {
      // scope for reserve{0,1}Adjusted, avoids stack too deep errors
      uint256 balanceLocalAdjusted = (balanceLocal * 1000) - (amount0In * 3);
      uint256 balanceRemoteAdjusted = (balanceRemote * 1000) - (amount1In * 3);
      require(
        balanceLocalAdjusted * balanceRemoteAdjusted >=
          uint256(_reserveLocal) * _reserveRemote * 1000**2,
        "Hyperswap: K"
      );
    }

    _update(balanceLocal, balanceRemote, _reserveLocal, _reserveRemote);
    emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
  }

  // force balances to match reserves
  function skim(address to) external lock {
    address _tokenLocal = tokenLocal.tokenAddr; // gas savings
    address _tokenRemote = tokenRemote.tokenAddr; // gas savings
    _safeTransfer(
      _tokenLocal,
      to,
      IERC20(_tokenLocal).balanceOf(address(this)) - reserveLocal
    );
    _safeTransfer(
      _tokenRemote,
      to,
      IERC20(_tokenRemote).balanceOf(address(this)) - reserveRemote
    );
  }

  // force reserves to match balances
  function sync() external lock {
    _update(
      IERC20(tokenLocal.tokenAddr).balanceOf(address(this)),
      IERC20(tokenRemote.tokenAddr).balanceOf(address(this)),
      reserveLocal,
      reserveRemote
    );
  }
}
