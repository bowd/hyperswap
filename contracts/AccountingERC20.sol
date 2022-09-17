// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract AccountingERC20 is ERC20, Ownable {
    uint32 public tokenDomainID;
    address public tokenAddress;

    constructor(uint32 _tokenDomainID, address _tokenAddress) ERC20("ProxyToken", "PT") Ownable() {
        _tokenDomainID = _tokenDomainID;
        _tokenAddress = _tokenAddress;
    }

    function transfer(address to, uint256 amount) public virtual override onlyOwner returns (bool) {
        return super.transfer(to, amount);
    }

    function mint(address account, uint256 amount) external onlyOwner {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) external onlyOwner {
        _burn(account, amount);
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public virtual override onlyOwner returns (bool) {
        _transfer(from, to, amount);
        return true;
    }
}