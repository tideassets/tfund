// SPDX-License-Identifier: MIT
// Copyright (C) 2023
// estoken.sol : for vesting token
//
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./auth.sol";

contract EsToken is ERC20, Auth, ReentrancyGuard {
  struct Vest {
    uint persencond;
    uint claimed;
    uint start;
  }

  IERC20 public token;
  uint public vestingId = 0;
  uint public constant VESTING_DURATION = 180 days;

  mapping(uint => mapping(address => Vest)) public vests;
  mapping(address => uint[]) public vestingIds;

  event Vesting(address indexed usr, uint amount, uint start);
  event Claim(address indexed usr, uint amount);
  event Deposit(address indexed usr, uint amount);

  constructor(address token_, string memory name_, string memory symbol_) ERC20(name_, symbol_) {
    token = IERC20(token_);
  }

  function vesting(uint amt) external nonReentrant whenNotPaused returns (uint) {
    require(amt > 0, "Val/zero-amount");
    _burn(msg.sender, amt);
    vestingId++;
    uint persencond = amt / VESTING_DURATION;
    Vest memory vest = Vest(persencond, 0, block.timestamp);
    vests[vestingId][msg.sender] = vest;
    vestingIds[msg.sender].push(vestingId);
    emit Vesting(msg.sender, amt, block.timestamp);
    return vestingId;
  }

  function _claim(uint vestingId_) internal returns (uint) {
    Vest memory vest = vests[vestingId_][msg.sender];
    uint d = block.timestamp - vest.start;
    if (d > VESTING_DURATION) {
      d = VESTING_DURATION;
    }
    uint vested = vest.persencond * d;
    uint amt = vested - vest.claimed;
    if (amt == 0) {
      return 0;
    }
    vests[vestingId_][msg.sender].claimed = vested;
    return amt;
  }

  function claim() external nonReentrant whenNotPaused {
    uint[] memory ids = vestingIds[msg.sender];
    uint amount = 0;
    for (uint i = 0; i < ids.length; i++) {
      amount += _claim(ids[i]);
    }
    require(amount > 0, "Val/no-vesting");
    token.transfer(msg.sender, amount);
    emit Claim(msg.sender, amount);
  }

  function deposit(address usr, uint amt) external nonReentrant whenNotPaused {
    require(amt > 0, "Val/zero-amount");
    token.transferFrom(msg.sender, address(this), amt);
    _mint(usr, amt);
    emit Deposit(usr, amt);
  }

  function transfer(address, uint) public pure override returns (bool) {
    return false;
  }

  function transferFrom(address, address, uint) public pure override returns (bool) {
    return false;
  }

  function mint(address usr, uint amt) external auth nonReentrant whenNotPaused {
    require(amt > 0, "Val/zero-amount");
    _mint(usr, amt);
  }
}
