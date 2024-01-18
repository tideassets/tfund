// SPDX-License-Identifier: MIT
// Copyright (C) 2023
// stake.sol : stake lp tokens for rewards
//
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {IERC20, ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Auth} from "./auth.sol";
import {IOU20} from "./iou.sol";

interface RewarderLike {
  function updateBefore(address, int) external;
  function updateAfter(address, int) external;
}

contract Stakex is Auth, Initializable {
  using SafeERC20 for IERC20;

  IERC20 public stkToken;
  IOU20 public iou;

  // rs["TDT-A"] = address(ew RewarderCycle())
  mapping(bytes32 => address) public rs;
  bytes32[] public ra;
  mapping(bytes32 => uint) public ri;

  function initialize(address stkToken_) public initializer {
    wards[msg.sender] = 1;
    stkToken = IERC20(stkToken_);
    iou = new IOU20("stk IOU", "IOU");
    iou.file("callback", address(this));
  }

  function balanceOf(address u) public view returns (uint) {
    return iou.balanceOf(u);
  }

  function totalSupply() public view returns (uint) {
    return iou.totalSupply();
  }

  function rewarders() external view returns (bytes32[] memory) {
    return ra;
  }

  function file(bytes32 who, bytes32 what, address data) external auth {
    if (what == "add") {
      rs[who] = data;
      ra.push(who);
      ri[who] = ra.length;
    } else if (what == "rm") {
      _rmRewarder(who);
    } else {
      revert("Stakex/file-unrecognized-param");
    }
  }

  function _rmRewarder(bytes32 name) internal {
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

    stkToken.safeTransferFrom(msg.sender, address(this), amt);
    iou.mint(to, amt);
  }

  function unstake(address to, uint amt) external whenNotPaused {
    require(amt > 0, "Stake/zero-amount");

    iou.burn(msg.sender, amt);
    stkToken.safeTransfer(to, amt);
  }

  function updateBefore(address from, address to, uint amt) external {
    uint len = ra.length;
    for (uint i = 0; i < len; i++) {
      address r = rs[ra[i]];
      if (from != address(0)) {
        RewarderLike(r).updateBefore(from, -int(amt));
      }
      if (to != address(0)) {
        RewarderLike(r).updateBefore(to, int(amt));
      }
    }
  }

  function updateAfter(address from, address to, uint amt) external {
    uint len = ra.length;
    for (uint i = 0; i < len; i++) {
      address r = rs[ra[i]];
      if (from != address(0)) {
        RewarderLike(r).updateAfter(from, -int(amt));
      }
      if (to != address(0)) {
        RewarderLike(r).updateAfter(to, int(amt));
      }
    }
  }
}
