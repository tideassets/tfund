// SPDX-License-Identifier: MIT
// Copyright (C) 2023
// estoken.sol : for vesting token
//
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {IERC20, ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Auth} from "./auth.sol";

contract EsToken is ERC20, Auth, Initializable {
  using SafeERC20 for IERC20;

  struct Vest {
    uint amt;
    uint claimed;
    uint start;
  }

  string internal name_;
  string internal symbol_;
  IERC20 public token;
  uint public vestingId = 0;
  uint public VESTING_DURATION = 180 days;

  mapping(uint => Vest) public vests;
  mapping(address => uint[]) public vids;

  event Vesting(address indexed usr, uint amount, uint start);
  event Claim(address from, address indexed usr, uint amount);
  event Deposit(address indexed from, address indexed usr, uint amount);

  constructor() ERC20("", "") {}

  function initialize(address _token, string memory _name, string memory _symbol)
    public
    initializer
  {
    wards[msg.sender] = 1;
    token = IERC20(_token);
    name_ = _name;
    symbol_ = _symbol;
  }

  function name() public view override returns (string memory) {
    return name_;
  }

  function symbol() public view override returns (string memory) {
    return symbol_;
  }

  function file(bytes32 what, uint data) external auth {
    if (what == "duration") {
      VESTING_DURATION = data;
    } else {
      revert("EsToken/file-unrecognized-param");
    }
  }

  function vesting(uint amt) external whenNotPaused returns (uint) {
    require(amt > 0, "TsToken/zero-amount");
    _burn(msg.sender, amt);
    vestingId++;
    Vest memory vest = Vest(amt, 0, block.timestamp);
    vests[vestingId] = vest;
    vids[msg.sender].push(vestingId);
    emit Vesting(msg.sender, amt, block.timestamp);
    return vestingId;
  }

  function vestings(address usr) external view returns (uint[] memory) {
    return vids[usr];
  }

  function vestingInfo(uint vestingId_) external view returns (uint, uint, uint) {
    Vest memory vest = vests[vestingId_];
    return (vest.amt, vest.claimed, vest.start);
  }

  function claimable(address usr) external view returns (uint) {
    uint[] memory ids = vids[usr];
    uint amount = 0;
    for (uint i = 0; i < ids.length; i++) {
      (uint amt,) = _claimable(ids[i]);
      amount += amt;
    }
    return amount;
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

  function claim(address to) external whenNotPaused returns (uint) {
    uint[] memory ids = vids[msg.sender];
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
    token.safeTransfer(to, amount);
    emit Claim(msg.sender, to, amount);
    return amount;
  }

  function deposit(address usr, uint amt) external whenNotPaused {
    require(amt > 0, "TsToken/zero-amount");
    token.safeTransferFrom(msg.sender, address(this), amt);
    _mint(usr, amt);
    emit Deposit(msg.sender, usr, amt);
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
