// SPDX-License-Identifier: MIT
// Copyright (C) 2023
// roles.sol: roles and permissions
//
pragma solidity ^0.8.20;

import {DSAuth, DSAuthority} from "ds-auth/auth.sol";

// set roles and permissions
// roles are bytes32, use keccak256('Role1'). permissions are bytes4, use bytes4(keccak256('functionName(arg1Type,arg2Type)'))
// permissions are set by roles, roles are set by admins or other roles
contract Roles is DSAuth, DSAuthority {
  struct Data {
    mapping(bytes32 => uint) indexs;
    bytes32[] roles;
  }

  mapping(address => bool) public admins;
  // key is user, value is data
  mapping(address => Data) roles;

  // permissions[contract][sig] = d
  mapping(address => mapping(bytes4 => Data)) permissions;

  event SetUserRole(address indexed usr, bytes32 indexed role, bool allow);
  event SetPermission(bytes32 indexed role, address indexed contr, bytes4 indexed sig, bool allow);
  event SetAdmin(address indexed usr, bool isAuth);

  constructor() {
    admins[msg.sender] = true;
  }

  function setAdmin(address usr, bool isAuth) external auth {
    admins[usr] = isAuth;
    emit SetAdmin(usr, isAuth);
  }

  function setPermission(bytes32 role, address contr, bytes4 sig, bool allow) external auth {
    require(role != bytes32(0), "Role/invalid-role");
    Data storage d = permissions[contr][sig];
    if (d.roles.length == 0) {
      if (!allow) {
        return;
      }
      d.roles.push(0x0);
      d.roles.push(role);
      d.indexs[role] = 1;
    } else {
      uint index = d.indexs[role];
      if (index == 0) {
        if (!allow) {
          return;
        }
        d.indexs[role] = d.roles.length;
        d.roles.push(role);
      } else {
        if (allow) {
          return;
        }
        uint last = d.roles.length - 1;
        bytes32 lastRole = d.roles[last];
        d.roles[index] = lastRole;
        d.roles.pop();
        d.indexs[lastRole] = index;
        d.indexs[role] = 0;
      }
    }
    emit SetPermission(role, contr, sig, allow);
  }

  function setUserRole(address usr, bytes32 role, bool allow) external auth {
    Data storage d = roles[usr];
    if (d.roles.length == 0) {
      if (!allow) {
        return;
      }
      d.roles.push(0x0);
      d.roles.push(role);
      d.indexs[role] = 1;
    } else {
      uint index = d.indexs[role];
      if (index == 0) {
        if (!allow) {
          return;
        }
        d.indexs[role] = d.roles.length;
        d.roles.push(role);
      } else {
        if (allow) {
          return;
        }
        uint last = d.roles.length - 1;
        bytes32 lastRole = d.roles[last];
        d.roles[index] = lastRole;
        d.roles.pop();
        d.indexs[lastRole] = index;
        d.indexs[role] = 0;
      }
    }
    emit SetUserRole(usr, role, allow);
  }

  function hasRole(address usr, bytes32 role) external view returns (bool) {
    Data storage d = roles[usr];
    return d.indexs[role] > 0;
  }

  function isAdministrator(address usr) external view returns (bool) {
    return admins[usr];
  }

  function canCall(address usr, address contr, bytes4 sig) external view returns (bool) {
    if (admins[usr]) {
      return true;
    }
    Data storage d = roles[usr];
    for (uint i = d.roles.length; i > 0; i--) {
      Data storage p = permissions[contr][sig];
      if (p.indexs[d.roles[i - 1]] > 0) {
        return true;
      }
    }
    return false;
  }
}
