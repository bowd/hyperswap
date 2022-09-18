// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import {IProxyTokenFactory} from "./interfaces/IProxyTokenFactory.sol";
import {AccountingERC20} from "./AccountingERC20.sol";

contract ProxyTokenFactory is IProxyTokenFactory {
  function deployProxyToken(
    address owner,
    uint32 domain,
    address remoteToken,
    address pair
  ) external returns (address) {
    AccountingERC20 accountingToken = new AccountingERC20(
      domain,
      remoteToken,
      pair
    );
    accountingToken.transferOwnership(owner);
    return address(accountingToken);
  }
}
