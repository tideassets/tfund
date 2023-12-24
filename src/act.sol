// SPDX-License-Identifier: MIT
// Copyright (C) 2023
// act.sol: user actions and governance actions
//
pragma solidity ^0.8.20;

import {Auth} from "./auth.sol";
import {DSProxy, DSProxyCache} from "ds-proxy/proxy.sol";

interface SetterLick {
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
    SetterLick(target).rely(who);
  }

  function deny(address target, address who) external {
    SetterLick(target).deny(who);
  }

  function file(address target, bytes32 what, address data) external {
    SetterLick(target).file(what, data);
  }

  function file(address target, bytes32 what, uint data) external {
    SetterLick(target).file(what, data);
  }

  function file(address target, bytes32 who, bytes32 what, uint data) external {
    SetterLick(target).file(what, who, data);
  }

  function file(address target, bytes32 who, bytes32 what, address data) external {
    SetterLick(target).file(what, who, data);
  }
}

contract Admin is Auth {
  DSProxy public proxy;
  GovActions public govActons;

  constructor(address _proxy) {
    proxy = DSProxy(payable(_proxy));
    govActons = new GovActions();
  }

  function _exec(bytes memory data) internal auth {
    proxy.execute(address(govActons), data);
  }

  fallback() external payable {
    _exec(msg.data);
  }

  receive() external payable {}
}
