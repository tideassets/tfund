// SPDX-License-Identifier: MIT
// Copyright (C) 2023
// vex.sol : veXXX : veTDT, veTTL, veTTS, veTTP
//
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {
  ERC721Enumerable,
  ERC721
} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Auth} from "./auth.sol";

contract VeToken is Auth, ERC721Enumerable, Initializable {
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

  uint public constant ONE = 1e18;
  uint public totalPower;
  string internal name_;
  string internal symbol_;

  mapping(Long => uint) public mults;
  mapping(Long => uint) public longs;
  mapping(uint => Pow) public pows; // key is tokenId

  event Deposit(address indexed usr, uint amt, uint start, Long long);
  event Withdraw(address indexed usr, uint amt, uint start, Long long);

  constructor() ERC721("", "") {}

  function initialize(address core_, string memory _name, string memory _symbol) public initializer {
    name_ = _name;
    symbol_ = _symbol;

    longs[Long.ONEMON] = 30 days;
    longs[Long.SIXMON] = 180 days;
    longs[Long.ONEYEAR] = 365 days;
    longs[Long.TWOYEAR] = longs[Long.ONEYEAR] * 2;
    longs[Long.FOURYEAR] = longs[Long.TWOYEAR] * 2;

    uint base = ONE + (ONE / 40);
    file("base", base);

    core = IERC20(core_);
  }

  function name() public view override returns (string memory) {
    return name_;
  }

  function symbol() public view override returns (string memory) {
    return symbol_;
  }

  function _power(uint a, uint e) internal pure returns (uint) {
    uint p = ONE;
    for (uint i = 0; i < e; ++i) {
      p *= a;
      p /= ONE;
    }
    return p;
  }

  function file(bytes32 what, uint data) public auth {
    uint base;
    if (what == "base") {
      base = data;
    } else {
      revert("VeToken/file-unrecognized-param");
    }
    // base rate = 1.025
    // ONEMON = 1.025, SIXMON = 1.025 ** 6, ONEYEAR = 1.025 ** 12, 24, 48 ...
    mults[Long.ONEMON] = base;
    mults[Long.SIXMON] = _power(base, 6); //1159563;
    mults[Long.ONEYEAR] = _power(base, 12); // 1344889;
    mults[Long.TWOYEAR] = _power(base, 24); //1808726;
    mults[Long.FOURYEAR] = _power(base, 48); // 3077057;
  }

  function powerOf(uint id) public view returns (uint) {
    Long l = pows[id].long;
    uint amt = pows[id].amt;
    uint mult = mults[l];
    return (mult * amt) / ONE;
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
    pow.pow = mults[long] * amt / ONE;
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
