// SPDX-License-Identifier: MIT
// Copyright (C) 2023
// tvt.sol: tide vetoken contract
//
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract IOUToken is ERC20, Ownable {
  constructor(string memory name, string memory symbol) ERC20(name, symbol) Ownable(msg.sender) {}

  function mint(address usr, uint wad) external onlyOwner {
    _mint(usr, wad);
  }

  function burn(address usr, uint wad) external onlyOwner {
    _burn(usr, wad);
  }

  // override ERC20.transferFrom to add owner check
  function transferFrom(address from, address to, uint value)
    public
    override
    onlyOwner
    returns (bool)
  {
    return super.transferFrom(from, to, value);
  }

  // override ERC20.transfer to add owner check
  function transfer(address to, uint value) public override onlyOwner returns (bool) {
    return super.transfer(to, value);
  }
}
