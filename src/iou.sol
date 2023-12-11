// SPDX-License-Identifier: MIT
// Copyright (C) 2023
// tvt.sol: tide vetoken contract
//
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Auth} from "./auth.sol";

contract IOUToken is ERC20, Auth {
  constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

  function mint(address usr, uint wad) external auth {
    _mint(usr, wad);
  }

  function burn(address usr, uint wad) external auth {
    _burn(usr, wad);
  }
}
