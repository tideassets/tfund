// SPDX-License-Identifier: MIT
// Copyright (C) 2023
// tvt.sol: tide vetoken contract
//
pragma solidity ^0.8.20;

import {
  ERC721Enumerable,
  ERC721
} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract IOU20 is ERC20, Ownable {
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

contract IOU721 is ERC721Enumerable, Ownable {

  constructor(string memory name, string memory symbol) ERC721(name, symbol) Ownable(msg.sender) {}

  function mint(address usr, uint id) external onlyOwner {
    _safeMint(usr, id);
  }

  function burn(uint id) external onlyOwner {
    _burn(id);
  }
}
