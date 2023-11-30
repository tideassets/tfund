// SPDX-License-Identifier: MIT
// Copyright (C) 2023
// estoken.sol : for vesting token
//
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./auth.sol";

contract EsToken is ERC20, Auth {
  struct Vest {
    uint amt;
    uint claimed;
    uint start;
  }

  IERC20 public token;
  uint public vestingId = 0;
  uint public VESTING_DURATION = 180 days;

  mapping(uint => Vest) public vests;
  mapping(address => uint[]) public vestingIds;

  event Vesting(address indexed usr, uint amount, uint start);
  event Claim(address indexed usr, uint amount);
  event Deposit(address indexed usr, uint amount);

  constructor(address token_, string memory name_, string memory symbol_) ERC20(name_, symbol_) {
    token = IERC20(token_);
  }

  function setVestingDuration(uint duration) external auth {
    VESTING_DURATION = duration;
  }

  function vesting(uint amt) external whenNotPaused returns (uint) {
    require(amt > 0, "TsToken/zero-amount");
    _burn(msg.sender, amt);
    vestingId++;
    Vest memory vest = Vest(amt, 0, block.timestamp);
    vests[vestingId] = vest;
    vestingIds[msg.sender].push(vestingId);
    emit Vesting(msg.sender, amt, block.timestamp);
    return vestingId;
  }

  function claimable(uint vestingId_) public view returns (uint) {
    (uint amt,) = _claimable(vestingId_);
    return amt;
  }

  function _claimable(uint vestingId_) internal view returns (uint, bool) {
    Vest memory vest = vests[vestingId_];
    if (vest.amt == 0) {
      return (0, true);
    }
    uint d = block.timestamp - vest.start;
    if (d > VESTING_DURATION) {
      d = VESTING_DURATION;
    }
    uint vested = vest.amt * d / VESTING_DURATION;
    uint amt = vested - vest.claimed;
    return (amt, d == VESTING_DURATION);
  }

  function claim() external whenNotPaused returns (uint) {
    uint[] memory ids = vestingIds[msg.sender];
    uint amount = 0;
    for (uint i = 0; i < ids.length; i++) {
      (uint amt, bool clear) = _claimable(ids[i]);
      if (amt == 0) {
        continue;
      }
      vests[ids[i]].claimed += amt;
      if (clear) {
        delete vests[ids[i]];
      }
      amount += amt;
    }
    if (amount == 0) {
      return 0;
    }
    token.transfer(msg.sender, amount);
    emit Claim(msg.sender, amount);
    return amount;
  }

  function deposit(address usr, uint amt) external whenNotPaused {
    require(amt > 0, "TsToken/zero-amount");
    token.transferFrom(msg.sender, address(this), amt);
    _mint(usr, amt);
    emit Deposit(usr, amt);
  }

  error NoTransfer();
  error NoTransferFrom();

  function transfer(address, uint) public pure override returns (bool) {
    revert NoTransfer();
  }

  function transferFrom(address, address, uint) public pure override returns (bool) {
    revert NoTransferFrom();
  }

  function mint(address usr, uint amt) external auth whenNotPaused {
    _mint(usr, amt);
  }
}
