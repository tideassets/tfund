// SPDX-License-Identifier: MIT
// Copyright (C) 2023
// act.sol: user actions and governance actions
//
pragma solidity ^0.8.20;

import {Auth} from "./auth.sol";
import {Proxy} from "@openzeppelin/contracts/proxy/Proxy.sol";

interface SetterLike {
  function file(bytes32, address) external;
  function file(bytes32, uint) external;
  function file(bytes32, bytes32, uint) external;
  function file(bytes32, bytes32, address) external;
  function rely(address) external;
  function deny(address) external;
  function init(bytes32) external;
}

contract GovActions {
  function rely(address target, address who) external {
    SetterLike(target).rely(who);
  }

  function deny(address target, address who) external {
    SetterLike(target).deny(who);
  }

  function file(address target, bytes32 what, address data) external {
    SetterLike(target).file(what, data);
  }

  function file(address target, bytes32 what, uint data) external {
    SetterLike(target).file(what, data);
  }

  function file(address target, bytes32 who, bytes32 what, uint data) external {
    SetterLike(target).file(what, who, data);
  }

  function file(address target, bytes32 who, bytes32 what, address data) external {
    SetterLike(target).file(what, who, data);
  }

  function init(address target, bytes32 who) external {
    SetterLike(target).init(who);
  }
}

contract Admin is Auth, Proxy {
  GovActions public govActons;

  constructor() {
    govActons = new GovActions();
  }

  function _implementation() internal view override returns (address) {
    return address(govActons);
  }

  function _fallback() internal override auth {
    super._fallback();
  }

  receive() external payable {}
}
