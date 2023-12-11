// SPDX-License-Identifier: MIT
// Copyright (C) 2023
// vex.sol : veXXX : veTDT, veTTL, veTTS, veTTP
//
pragma solidity ^0.8.20;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Auth} from "./auth.sol";

contract VeToken is Auth, ERC721 {
  using SafeERC20 for IERC20;

  IERC20 public core;
  uint public tokenId; // current

  struct Pow {
    uint amt;
    uint start;
    Long long;
    uint pow;
    uint index;
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

  mapping(uint => Pow) public pows; // key is tokenId
  mapping(address => uint[]) public ids; // key is usr address, value is tokenIds
  mapping(Long => uint) public mults;
  mapping(Long => uint) public longs;

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

  function powerOf(uint tokenId_) public view returns (uint) {
    Long l = pows[tokenId_].long;
    uint amt = pows[tokenId_].amt;
    uint mult = mults[l];
    return (mult * amt) / POW_DIVISOR;
  }

  // user power
  function powerOf(address user) public view returns (uint) {
    uint[] memory ids_ = ids[user];
    uint p = 0;
    for (uint i = 0; i < ids_.length; i++) {
      uint id = ids_[i];
      if (ownerOf(id) != user) {
        continue;
      }
      p += powerOf(id);
    }
    return p;
  }

  function deposit(uint amt, Long long) external whenNotPaused returns (uint) {
    core.safeTransferFrom(msg.sender, address(this), amt);

    tokenId++;
    Pow memory pow = Pow(amt, block.timestamp, long, 0, 0);
    pow.pow = mults[long] * amt / POW_DIVISOR;
    totalPower += pow.pow;
    pow.index = ids[msg.sender].length;
    pows[tokenId] = pow;

    _mint(msg.sender, tokenId);

    ids[msg.sender].push(tokenId);

    emit Deposit(msg.sender, amt, block.timestamp, long);
    return tokenId;
  }

  function withdraw(uint tokenId_) external whenNotPaused {
    require(ownerOf(tokenId_) == msg.sender, "VeToken/tokenId not belong you");
    uint start = pows[tokenId_].start;
    Long long = pows[tokenId_].long;
    require(block.timestamp >= start + longs[long], "VeToken/time is't up");

    uint amt = pows[tokenId_].amt;
    uint pow = powerOf(tokenId_);
    totalPower -= pow;

    core.safeTransfer(msg.sender, amt);
    _burn(tokenId_);

    uint lastId = ids[msg.sender][ids[msg.sender].length - 1];
    ids[msg.sender][pows[tokenId_].index] = lastId;
    pows[lastId].index = pows[tokenId_].index;
    ids[msg.sender].pop();
    delete pows[tokenId_];

    emit Withdraw(msg.sender, amt, start, long);
  }

  // function transferFrom(address, address, uint) public override auth {
  //   super.transferFrom(address, address, uint);
  // }
}
