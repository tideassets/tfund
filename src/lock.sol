// SPDX-License-Identifier: MIT
// Copyright (C) 2023
// lock.sol : lock miner

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./auth.sol";

interface IToken is IERC20 {
  function mint(address, uint) external;
}

contract Locker is Auth {
  IToken public token;

  using SafeERC20 for IToken;

  mapping(bytes32 => uint) public remains;
  mapping(bytes32 => uint) public minted;
  mapping(bytes32 => address) public addrs;
  mapping(bytes32 => uint) public cycle;
  mapping(bytes32 => uint) public cycleMinted;

  uint public constant ONE = 1e18;
  uint public start;
  uint public initTeamLockLong = 300 days;
  uint public lpNext = 0;

  event Unlock(bytes32 indexed role, address indexed usr, uint amt);

  modifier OnlyRole(bytes32 role) {
    require(msg.sender == addrs[role] || wards[msg.sender] == 1, "Lock: OnlyRole");
    _;
  }

  constructor(address token_, address dao_, address tsaDao_, address team_, address lpFund_) {
    token = IToken(token_);

    addrs["dao"] = dao_;
    addrs["tsaDao"] = tsaDao_;
    addrs["team"] = team_;
    addrs["lpFund"] = lpFund_;

    cycle["dao"] = 30 days;
    cycle["tsaDao"] = 30 days;
    cycle["team"] = 30 days;
    cycle["lpFund"] = 7 days;

    token.mint(address(this), 1e8 * ONE);
    token.safeTransfer(dao_, 2e6 * ONE);

    remains["tsaDao"] = 1e7 * ONE;
    remains["team"] = 1e7 * ONE;
    remains["dao"] = 8e6 * ONE;
    remains["lpFund"] = 7e7 * ONE;
    start = block.timestamp;

    cycleMinted["dao"] = remains["dao"] / 80;
    cycleMinted["tsaDao"] = remains["tsaDao"] / 50;
    cycleMinted["team"] = remains["team"] / 80;
    lpNext = remains["lpFund"] / 52 / 5;
  }

  function changeDao(address dao) external auth {
    addrs["dao"] = dao;
  }

  function changeTsaDao(address tsaDao) external auth {
    addrs["tsaDao"] = tsaDao;
  }

  function changeTeam(address team) external auth {
    addrs["team"] = team;
  }

  function changeLpFund(address lpFund) external auth {
    addrs["lpFund"] = lpFund;
  }

  function daoUnlock() external {
    _unlock("dao", start);
  }

  function tsaUnlock() external {
    _unlock("tsaDao", start);
  }

  function teamUnlock() external {
    _unlock("team", start + initTeamLockLong);
  }

  function lpFundUnlock() external {
    _unlock("lpFund", start);
  }

  function setLpNext(uint amt) external auth {
    lpNext = amt;
  }

  function _unlock(bytes32 role, uint start_) internal OnlyRole(role) returns (uint) {
    if (block.timestamp < start_) {
      return 0;
    }

    if (remains[role] == 0) {
      return 0;
    }

    uint nth = (block.timestamp - start_) / cycle[role];
    uint amt = cycleMinted[role] * nth - minted[role];

    if (remains[role] < amt) {
      amt = remains[role];
    }

    if (amt == 0) {
      return 0;
    }

    remains[role] -= amt;
    token.safeTransfer(addrs[role], amt);
    minted[role] += amt;

    emit Unlock(role, addrs["lpFund"], amt);
    return amt;
  }
}
