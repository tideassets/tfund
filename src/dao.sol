// SPDX-License-Identifier: MIT
// Copyright (C) 2023
// dao.sol : for dao governance veToken rewards voter

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Dao {
  IERC20 public token;

  constructor(address token_) {
    token = IERC20(token_);
  }
}
