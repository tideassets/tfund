// SPDX-License-Identifier: MIT
// Copyright (C) 2023
// dist.sol : distribute reward
//
pragma solidity ^0.8.20;

import "./estoken.sol";
import "./auth.sol";

interface IStaker {
  function stake(address usr, uint amt) external;
  function unstake(address usr, uint amt) external;
}

contract Distributer is Auth {
  // key is asset address
  mapping(address => IStaker) public stks;

  constructor() {}

  function addStaker(address asset, address staker) external auth {
    stks[asset] = IStaker(staker);
  }

  function delStaker(address asset) external auth {
    delete stks[asset];
  }

  function stake(address asset, address usr, uint amt) external auth {
    stks[asset].stake(usr, amt);
  }

  function unstake(address asset, address usr, uint amt) external auth {
    stks[asset].unstake(usr, amt);
  }
}
