// SPDX-License-Identifier: MIT
// Copyright (C) 2023
// router.sol : user operation interface
//
pragma solidity ^0.8.20;

import "./auth.sol";
import "./vault.sol";
import "./reward.sol";
import "./stake.sol";
import "./dist.sol";
import "./estoken.sol";
import "./lock.sol";
import "./dao.sol";

// manage all contracts
contract Router is Auth {
  // tdtVault = vaults[tdt]
  mapping(address => Vault) vaults;

  // teamDao = daos["team"]
  mapping(bytes32 => Dao) daos;

  // tdtRewarder = rewarders[tdt], key is reward token
  mapping(address => RewarderCycle) cycle_rewarders;
  mapping(address => RewarderAccum) accum_rewarders;

  // tdtStakex = stakexs[tdt], key is stakeed token
  mapping(address => Stakex) stakexs;

  constructor() {}
  function createVault() public auth {}
  function createRewarder() public auth {}
  function createVeToken() public auth {}
  function createStakex() public auth {}

  function setUp() external auth {}
}
