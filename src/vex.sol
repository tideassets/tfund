// SPDX-License-Identifier: MIT
// Copyright (C) 2023
// vex.sol : veXXX : veTDT, veTTL, veTTS, veTTP
//

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

interface ERC20Like is IERC20 {
  function mint(address, uint) external;

  function burn(address, uint) external;
}

contract Vex is ReentrancyGuard, Pausable, ERC721 {
  using SafeERC20 for ERC20Like;
  using SafeERC20 for IERC20;
  using SafeMath for uint;

  // ---- Auth ----
  mapping(address => uint) wards;

  modifier auth() {
    require(wards[msg.sender] == 1, "Val/not-authorized");
    _;
  }

  function rely(address usr) external auth whenNotPaused {
    wards[usr] = 1;
    emit Rely(usr);
  }

  function deny(address usr) external auth whenNotPaused {
    wards[usr] = 0;
    emit Deny(usr);
  }

  event Rely(address indexed usr);
  event Deny(address indexed usr);

  ERC20Like public token;
  uint public tokenId; // current

  struct Pow {
    uint balance;
    uint start;
    uint long;
  }

  enum Long {
    ONEMON,
    SIXMON,
    ONEYEAR,
    TWOYEAR,
    FOURYEAR
  }

  uint public constant POW_DIVISOR = 1000000;

  mapping(uint => Pow) public pows; // key is tokenId
  mapping(address => uint[]) public votes; // key is voter, value is tokenIds
  mapping(uint => uint) public mults;
  mapping(uint => uint) public longs;

  constructor(
    string memory name_,
    string memory symbol_,
    address token_
  ) ERC721(name_, symbol_) {
    token = ERC20Like(token_);
    wards[msg.sender] = 1;

    longs[uint(Long.ONEMON)] = 30 days;
    longs[uint(Long.SIXMON)] = 180 days;
    longs[uint(Long.ONEYEAR)] = 365 days;
    longs[uint(Long.TWOYEAR)] = longs[uint(Long.ONEYEAR)] * 2;
    longs[uint(Long.FOURYEAR)] = longs[uint(Long.TWOYEAR)] * 2;

    // base rate = 1.025
    // ONEMON = 1.025, SIXMON = 1.025 ** 6, ONEYEAR = 1.025 ** 12, 24, 48 ...
    mults[uint(Long.ONEMON)] = 1025000;
    mults[uint(Long.SIXMON)] = 1159563;
    mults[uint(Long.ONEYEAR)] = 1344889;
    mults[uint(Long.TWOYEAR)] = 1808726;
    mults[uint(Long.FOURYEAR)] = 3271490;
  }

  function pause() external auth {
    _pause();
  }

  function unpause() external auth {
    _unpause();
  }

  function setMults(uint[] memory mults_) public auth whenNotPaused {
    for (uint i = 0; i < mults_.length; i++) {
      mults[i] = mults_[i];
    }
  }

  function setLongs(uint[] memory longs_) public auth whenNotPaused {
    for (uint i = 0; i < longs_.length; i++) {
      longs[i] = longs_[i];
    }
  }

  function power(uint tokenId_) public view returns (uint) {
    uint l = pows[tokenId_].long;
    uint balance = pows[tokenId_].balance;
    uint mult = mults[l];
    return mult.mul(balance).div(POW_DIVISOR);
  }

  // for snapshot, vote use address of voter, all vote power
  function power(address user) external view returns (uint) {
    uint[] memory ids = votes[user];
    uint p = 0;
    for (uint i = 0; i < ids.length; i++) {
      uint id = ids[i];
      if (ownerOf(id) != user) {
        continue;
      }
      p += power(id);
    }
    return p;
  }

  function deposit(
    uint amt,
    uint long
  ) external nonReentrant whenNotPaused returns (uint) {
    SafeERC20.safeTransferFrom(token, msg.sender, address(this), amt);
    tokenId++;
    pows[tokenId] = Pow(amt, block.timestamp, long);
    _mint(msg.sender, tokenId);
    votes[msg.sender].push(tokenId);
    return tokenId;
  }

  function withdraw(uint tokenId_) external nonReentrant whenNotPaused {
    require(ownerOf(tokenId_) == msg.sender, "Vex/tokenId not belong you");
    uint start = pows[tokenId_].start;
    uint long = pows[tokenId_].long;
    require(block.timestamp >= start + longs[long], "Vex/time is't up");

    uint amt = pows[tokenId_].balance;
    uint reward = power(tokenId_).sub(amt);

    _burn(tokenId_);
    token.safeTransfer(msg.sender, amt);
    token.mint(msg.sender, reward);
    delete pows[tokenId_];
  }

  // usr
  function vesting(uint tokenId_) external returns (uint) {
    require(ownerOf(tokenId_) == msg.sender, "Vex/tokenId not belong you");

    return 0;
  }
}
