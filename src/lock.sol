// SPDX-License-Identifier: MIT
// Copyright (C) 2023
// lock.sol : lock token

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

interface ERC20Like is IERC20 {
  function mint(address account, uint amt) external;

  function burn(address account, uint amt) external;
}

contract Lock is ReentrancyGuard, Pausable {
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

  mapping(bytes32 => uint) public remains;
  mapping(bytes32 => uint) public minted;
  mapping(bytes32 => address) public addrs;
  mapping(bytes32 => uint) public cycle;
  mapping(bytes32 => uint) public cycleMinted;

  uint public constant ONE = 1e18;
  uint public start;
  uint public initTeamLockLong = 300 days;
  uint public lpNext = 0;

  modifier onlyDao() {
    require(msg.sender == addrs["dao"], "Val/not-authorized");
    _;
  }
  modifier onlytsaDao() {
    require(msg.sender == addrs["tsaDao"], "Val/not-authorized");
    _;
  }
  modifier onlyteam() {
    require(msg.sender == addrs["team"], "Val/not-authorized");
    _;
  }
  modifier onlylpFund() {
    require(msg.sender == addrs["lpFund"], "Val/not-authorized");
    _;
  }

  event DaoMint(address indexed usr, uint amt);
  event TsaDaoMint(address indexed usr, uint amt);
  event TeamMint(address indexed usr, uint amt);
  event LpFundMint(address indexed usr, uint amt);

  constructor(
    address token_,
    address dao_,
    address tsaDao_,
    address team_,
    address lpFund_
  ) {
    wards[msg.sender] = 1;
    token = ERC20Like(token_);
    addrs["dao"] = dao_;
    addrs["tsaDao"] = tsaDao_;
    addrs["team"] = team_;
    addrs["lpFund"] = lpFund_;

    cycle["dao"] = 30 days;
    cycle["tsaDao"] = 30 days;
    cycle["team"] = 30 days;
    cycle["lpFund"] = 7 days;

    token.mint(dao_, 2e7 * ONE);
    remains["tsaDao"] = 1e8 * ONE;
    remains["team"] = 1e8 * ONE;
    remains["dao"] = 8e7 * ONE;
    remains["lpFund"] = 7e8 * ONE;
    start = block.timestamp;

    cycleMinted["dao"] = remains["dao"] / 80;
    cycleMinted["tsaDao"] = remains["tsaDao"] / 50;
    cycleMinted["team"] = remains["team"] / 80;
    lpNext = remains["lpFund"] / 52 / 5;
  }

  function pause() external auth {
    _pause();
  }

  function unpause() external auth {
    _unpause();
  }

  function daoMint() external onlyDao nonReentrant {
    uint amt = _mint("dao", start);
    emit DaoMint(addrs["dao"], amt);
  }

  function tsaDaoMint() external onlytsaDao nonReentrant {
    uint amt = _mint("tsaDao", start);
    emit TsaDaoMint(addrs["tsaDao"], amt);
  }

  function teamMint() external onlyteam nonReentrant {
    uint amt = _mint("team", start + initTeamLockLong);
    emit TeamMint(addrs["team"], amt);
  }

  function lpFundMint() external onlylpFund nonReentrant {
    uint amt = _mint("lpFund", start);
    emit LpFundMint(addrs["lpFund"], amt);
  }

  function setLpNext(uint amt) external auth {
    lpNext = amt;
  }

  function _mint(
    bytes32 key,
    uint start_
  ) internal whenNotPaused returns (uint) {
    if (block.timestamp < start_) {
      return 0;
    }
    require(remains[key] > 0, "Val/no-remain");
    uint nth = block.timestamp.sub(start_).div(cycle[key]);
    uint amt = cycleMinted[key].mul(nth).sub(minted[key]);

    if (remains[key] < amt) {
      amt = remains[key];
    }

    remains[key] -= amt;
    token.mint(addrs[key], amt);
    minted[key] += amt;
    return amt;
  }
}
