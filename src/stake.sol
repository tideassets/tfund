// SPDX-License-Identifier: MIT
// Copyright (C) 2023
// stake.sol : stake lp tokens for rewards
//
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC20, ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Auth} from "./auth.sol";
import {IOU20} from "./iou.sol";

interface RewarderLike {
  function stake(address, uint) external;
  function unstake(address, uint) external;
}

contract Stakex is Auth, Initializable {
  using SafeERC20 for IERC20;

  IERC20 public stkToken;
  IOU20 public iou;

  // rs["TDT-A"] = naddress(ew RewarderCycle())
  mapping(bytes32 => address) public rs;
  bytes32[] public ra;
  mapping(bytes32 => uint) public ri;

  function initialize(address stkToken_) public initializer {
    stkToken = IERC20(stkToken_);
    iou = new IOU20("stk IOU", "IOU");
    iou.file("callback", address(this));
  }

  function balanceOf(address u) public view returns (uint) {
    return iou.balanceOf(u);
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
    stkToken.safeTransferFrom(msg.sender, address(this), amt);

    // _stake(to, amt);
    iou.mint(to, amt);
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

    // _unstake(msg.sender, amt);
    iou.burn(msg.sender, amt);
    stkToken.safeTransfer(to, amt);
  }

  function _unstake(address to, uint amt) internal {
    uint len = ra.length;
    for (uint i = 0; i < len; i++) {
      address r = rs[ra[i]];
      RewarderLike(r).unstake(to, amt);
    }
  }

  function callback(address from, address to, uint val) external {
    if (from == address(0)) {
      _stake(to, val);
    } else if (to == address(0)) {
      _unstake(from, val);
    } else {
      _unstake(from, val);
      _stake(to, val);
    }
  }
}
