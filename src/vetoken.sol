// SPDX-License-Identifier: MIT
// Copyright (C) 2023
// vex.sol : veXXX : veTDT, veTTL, veTTS, veTTP
//
pragma solidity ^0.8.20;

import {
  ERC721Enumerable,
  ERC721
} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Auth} from "./auth.sol";

contract VeToken is Auth, ERC721Enumerable {
  using SafeERC20 for IERC20;

  IERC20 public core;
  uint public tokenId; // current

  struct Pow {
    uint amt;
    uint start;
    Long long;
    uint pow;
  }

  enum Long {
    ONEMON,
    SIXMON,
    ONEYEAR,
    TWOYEAR,
    FOURYEAR
  }

  uint public constant POW_DIVISOR = 1000000;
  uint public totalPower;

  mapping(Long => uint) public mults;
  mapping(Long => uint) public longs;
  mapping(uint => Pow) public pows; // key is tokenId

  event Deposit(address indexed usr, uint amt, uint start, Long long);
  event Withdraw(address indexed usr, uint amt, uint start, Long long);

  constructor(address core_, string memory name_, string memory symbol_) ERC721(name_, symbol_) {
    longs[Long.ONEMON] = 30 days;
    longs[Long.SIXMON] = 180 days;
    longs[Long.ONEYEAR] = 365 days;
    longs[Long.TWOYEAR] = longs[Long.ONEYEAR] * 2;
    longs[Long.FOURYEAR] = longs[Long.TWOYEAR] * 2;

    // base rate = 1.025
    // ONEMON = 1.025, SIXMON = 1.025 ** 6, ONEYEAR = 1.025 ** 12, 24, 48 ...
    mults[Long.ONEMON] = 1025000;
    mults[Long.SIXMON] = 1159563;
    mults[Long.ONEYEAR] = 1344889;
    mults[Long.TWOYEAR] = 1808726;
    mults[Long.FOURYEAR] = 3271490;

    core = IERC20(core_);
  }

  function powerOf(uint id) public view returns (uint) {
    Long l = pows[id].long;
    uint amt = pows[id].amt;
    uint mult = mults[l];
    return (mult * amt) / POW_DIVISOR;
  }

  // user power
  function powerOf(address usr) public view returns (uint) {
    uint p = 0;
    uint len = balanceOf(usr);
    for (uint i = 0; i < len; ++i) {
      uint id = tokenOfOwnerByIndex(usr, i);
      p += powerOf(id);
    }
    return p;
  }

  function deposit(uint amt, Long long) external whenNotPaused returns (uint) {
    core.safeTransferFrom(msg.sender, address(this), amt);

    tokenId++;
    Pow memory pow = Pow(amt, block.timestamp, long, 0);
    pow.pow = mults[long] * amt / POW_DIVISOR;
    totalPower += pow.pow;
    pows[tokenId] = pow;

    _mint(msg.sender, tokenId);

    emit Deposit(msg.sender, amt, block.timestamp, long);
    return tokenId;
  }

  function withdraw(uint id) external whenNotPaused {
    require(ownerOf(id) == msg.sender, "VeToken/tokenId not belong you");
    Pow memory pow = pows[id];
    uint start = pow.start;
    Long long = pow.long;
    require(block.timestamp >= start + longs[long], "VeToken/time is't up");

    uint amt = pow.amt;
    totalPower -= powerOf(id);
    delete pows[id];

    _burn(id);
    core.safeTransfer(msg.sender, amt);

    emit Withdraw(msg.sender, amt, start, long);
  }
}
