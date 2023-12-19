// SPDX-License-Identifier: MIT
// Copyright (C) 2023
// stake.sol : stake lp tokens for rewards
//
pragma solidity ^0.8.20;

import {IERC20, ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Auth} from "./auth.sol";

interface RewarderLike {
  function stake(address, uint) external;
  function unstake(address, uint) external;
}

contract Stakex is ERC20, Auth {
  using SafeERC20 for IERC20;

  IERC20 public stkToken;

  // rs["TDT-A"] = naddress(ew RewarderCycle())
  mapping(bytes32 => address) public rs;
  bytes32[] public ra;
  mapping(bytes32 => uint) public ri;

  constructor(string memory name_, string memory symbol_, address stkToken_) ERC20(name_, symbol_) {
    stkToken = IERC20(stkToken_);
  }

  function setStkToken(address stkToken_) external auth {
    stkToken = IERC20(stkToken_);
  }

  function rewarders() external view returns (bytes32[] memory) {
    return ra;
  }

  function addRewarder(bytes32 name, address rewarder) external auth {
    rs[name] = rewarder;
    ra.push(name);
    ri[name] = ra.length;
  }

  function delRewarder(bytes32 name) external auth {
    bytes32 last = ra[ra.length - 1];
    if (name != last) {
      uint i = ri[name] - 1;
      ra[i] = last;
      ri[last] = i + 1;
    }
    ra.pop();
    delete ri[name];
    delete rs[name];
  }

  function stake(address to, uint amt) external whenNotPaused {
    require(amt > 0, "Stake/zero-amount");

    _stake(to, amt);

    stkToken.safeTransferFrom(msg.sender, address(this), amt);
    _mint(to, amt);
  }

  function _stake(address to, uint amt) internal {
    uint len = ra.length;
    for (uint i = 0; i < len; i++) {
      address r = rs[ra[i]];
      RewarderLike(r).stake(to, amt);
    }
  }

  function unstake(address to, uint amt) external whenNotPaused {
    require(amt > 0, "Stake/zero-amount");

    _unstake(msg.sender, amt);
    _burn(msg.sender, amt);
    stkToken.safeTransfer(to, amt);
  }

  function _unstake(address to, uint amt) internal {
    uint len = ra.length;
    for (uint i = 0; i < len; i++) {
      address r = rs[ra[i]];
      RewarderLike(r).unstake(to, amt);
    }
  }

  function transfer(address to, uint amt) public override returns (bool) {
    _unstake(msg.sender, amt);
    _stake(to, amt);

    bool ok = super.transfer(to, amt);
    require(ok, "VeToken/transfer-failed");
    return true;
  }

  function transferFrom(address from, address to, uint amt) public override returns (bool) {
    _unstake(from, amt);
    _stake(to, amt);

    bool ok = super.transferFrom(from, to, amt);
    require(ok, "VeToken/transfer-failed");
    return true;
  }
}
