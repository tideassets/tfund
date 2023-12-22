// SPDX-License-Identifier: MIT
// Copyright (C) 2023
// act.sol: user actions and governance actions
//
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Auth} from "./auth.sol";

contract GovActions {
  function rely(address, address) external auth {
    _exec(msg.data);
  }

  function deny(address, address) external auth {
    _exec(msg.data);
  }

  function file(address, bytes32, uint) external auth {
    _exec(msg.data);
  }

  function file(address, bytes32, bytes32, uint) external auth {
    _exec(msg.data);
  }
}

contract UserActions {}
