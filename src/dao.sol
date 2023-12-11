// SPDX-License-Identifier: MIT
// Copyright (C) 2023
// dao.sol : for dao governance veToken rewards voter

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./auth.sol";

contract Dao is Auth {
  using SafeERC20 for IERC20;

  function withdraw(address token, uint amt) external auth whenNotPaused {
    IERC20(token).safeTransfer(msg.sender, amt);
  }

  function approve(address token, address to, uint amt) external auth whenNotPaused {
    IERC20(token).approve(to, amt);
  }

  receive() external payable {}
  fallback() external payable {}
}
