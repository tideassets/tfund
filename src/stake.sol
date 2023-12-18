// SPDX-License-Identifier: MIT
// Copyright (C) 2023
// stake.sol : stake lp tokens for rewards
//
pragma solidity ^0.8.20;

import {IERC20, ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Auth} from "./auth.sol";

contract RTokens is Auth {
  address[] public rtokens;
  mapping(address => uint) public indexs;

  constructor() {
    rtokens.push(address(0));
  }

  function count() public view returns (uint) {
    return rtokens.length;
  }

  function addRtoken(address rtoken) external auth {
    _addRtoken(rtoken);
  }

  function delRtoken(address rtoken) external auth {
    _delRtoken(rtoken);
  }

  function _addRtoken(address rtoken) internal virtual {
    require(indexs[rtoken] == 0, "already added");
    indexs[rtoken] = rtokens.length;
    rtokens.push(rtoken);
  }

  function _delRtoken(address rtoken) internal virtual {
    require(indexs[rtoken] > 0, "not added");
    if (rtokens.length > 1) {
      uint index = indexs[rtoken];
      address last = rtokens[rtokens.length - 1];
      rtokens[index] = last;
      indexs[last] = index;
    }
    rtokens.pop();
    delete indexs[rtoken];
  }
}

interface RewarderLike {
  function stake(address, uint) external;
  function unstake(address, uint) external;
}

contract Stakex is ERC20, Auth {
  using SafeERC20 for IERC20;

  IERC20 public stkToken;

  RTokens public rtokens;
  mapping(address => RewarderLike) public rewarders; // key is rtoken

  constructor(string memory name_, string memory symbol_, address stkToken_) ERC20(name_, symbol_) {
    stkToken = IERC20(stkToken_);
    rtokens = new RTokens();
  }

  function addRtoken(address rtoken, address rewarder) external auth {
    rtokens.addRtoken(rtoken);
    RewarderLike rl = RewarderLike(rewarder);
    rewarders[rtoken] = rl;
  }

  function delRtoken(address rtoken) external auth {
    rtokens.delRtoken(rtoken);
    delete rewarders[rtoken];
  }

  function stake(address to, uint amt) external whenNotPaused {
    require(amt > 0, "Stake/zero-amount");

    _stake(to, amt);

    stkToken.safeTransferFrom(msg.sender, address(this), amt);
    _mint(to, amt);
  }

  function _stake(address to, uint amt) internal {
    uint rtlen = rtokens.count();
    mapping(address => RewarderLike) storage rewarders_ = rewarders;
    for (uint i = 1; i < rtlen; i++) {
      // should skip 0
      address rt = rtokens.rtokens(i);
      rewarders_[rt].stake(to, amt);
    }
  }

  function unstake(address to, uint amt) external whenNotPaused {
    require(amt > 0, "Stake/zero-amount");

    _unstake(to, amt);
    _burn(msg.sender, amt);
    stkToken.safeTransfer(to, amt);
  }

  function _unstake(address to, uint amt) internal {
    uint rtlen = rtokens.count();
    mapping(address => RewarderLike) storage rewarders_ = rewarders;
    for (uint i = 1; i < rtlen; i++) {
      // should skip 0
      address rt = rtokens.rtokens(i);
      rewarders_[rt].unstake(to, amt);
    }
  }
}
