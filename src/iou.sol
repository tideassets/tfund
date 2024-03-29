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

interface CallbackLike {
  function updateBefore(address, address, uint) external;
  function updateAfter(address, address, uint) external;
}

contract IOU20 is ERC20, Ownable {
  CallbackLike u;

  constructor(string memory name, string memory symbol) ERC20(name, symbol) Ownable(msg.sender) {}

  function file(bytes32 what, address u_) external onlyOwner {
    if (what == "callback") {
      u = CallbackLike(u_);
    } else if (what == "owner") {
      transferOwnership(u_);
    } else {
      revert("IOU20/file-unrecognized-param");
    }
  }

  function mint(address usr, uint wad) external onlyOwner {
    _mint(usr, wad);
  }

  function burn(address usr, uint wad) external onlyOwner {
    _burn(usr, wad);
  }

  function _update(address from, address to, uint value) internal virtual override {
    if (address(u) != address(0)) {
      u.updateBefore(from, to, value);
    }

    super._update(from, to, value);

    if (address(u) != address(0)) {
      u.updateAfter(from, to, value);
    }
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
