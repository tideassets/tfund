// SPDX-License-Identifier: MIT
// Copyright (C) 2023
// roles.sol: roles and permissions
//
pragma solidity ^0.8.20;

import {DSAuth, DSAuthority} from "ds-auth/auth.sol";
import {DSRoles} from "ds-roles/roles.sol";

// set roles and permissions
// roles are bytes32, use keccak256('Role1'). permissions are bytes4, use bytes4(keccak256('functionName(arg1Type,arg2Type)'))
// permissions are set by roles, roles are set by admins or other roles
contract Roles is DSAuth, DSAuthority {
  mapping(address => bool) public admins;
  mapping(address => bytes32[]) users;
  mapping(bytes32 => mapping(address => uint)) roles;
  mapping(bytes32 => mapping(address => mapping(bytes4 => bool))) permissions;

  event SetUserRole(address indexed usr, bytes32 indexed role, bool allow);
  event SetPermission(bytes32 indexed role, address indexed code, bytes4 indexed sig, bool allow);
  event SetAdmin(address indexed usr, bool isAuth);

  constructor() {
    admins[msg.sender] = true;
  }

  function setAdmin(address usr, bool isAuth) external auth {
    admins[usr] = isAuth;
    emit SetAdmin(usr, isAuth);
  }

  function setPermission(bytes32 role, address code, bytes4 sig, bool allow) external auth {
    require(role != bytes32(0), "Role/invalid-role");
    permissions[role][code][sig] = allow;
    emit SetPermission(role, code, sig, allow);
  }

  function setUserRole(address usr, bytes32 role, bool allow) external auth {
    uint index = roles[role][usr];
    bytes32[] storage urs = users[usr];
    if (allow) {
      if (urs.length == 0) {
        urs.push(0x0); // index must > 0
      }
      if (index == 0) {
        roles[role][usr] = urs.length;
        urs.push(role);
      }
    } else {
      if (index > 0) {
        bytes32 last = urs[urs.length - 1];
        urs[index] = last;
        urs.pop();
        delete roles[role][usr];
      }
    }
    emit SetUserRole(usr, role, allow);
  }

  function hasRole(address usr, bytes32 role) external view returns (bool) {
    return roles[role][usr] > 0;
  }

  function isAdministrator(address usr) external view returns (bool) {
    return admins[usr];
  }

  function canCall(address usr, address code, bytes4 sig) external view returns (bool) {
    if (admins[usr]) {
      return true;
    }
    bytes32[] memory urs = users[usr];
    for (uint i = 1; i < urs.length; i++) {
      // skip 0
      if (permissions[urs[i]][code][sig]) {
        return true;
      }
    }
    return false;
  }
}

contract TRoles is DSRoles {
  mapping(bytes32 => uint8) types;
  mapping(uint8 => bytes32) names;
  uint8 public typeCount;

  function addType(bytes32 name) external auth {
    require(types[name] == 0, "Roles/type-exists");
    types[name] = ++typeCount;
    names[typeCount] = name;
  }

  function getUsrRoles(address usr) external view returns (bytes32[] memory roles) {
    bytes32 rs = getUserRoles(usr);
    uint8 count = typeCount;
    roles = new bytes32[](count);
    for (uint8 i = 0; i < count; i++) {
      bytes32 shifted = bytes32(uint(uint(2) ** uint(i)));
      if (rs & shifted > 0) {
        roles[i] = names[i];
      }
    }
  }

  function hasUsrRole(address usr, bytes32 role) external view returns (bool) {
    require(types[role] > 0, "Roles/invalid-role");
    return hasUserRole(usr, types[role]);
  }

  function setUsrRole(address usr, bytes32 role, bool allow) external auth {
    require(types[role] > 0, "Roles/invalid-role");
    return setUserRole(usr, types[role], allow);
  }

  function setPermission(bytes32 role, address code, bytes4 sig, bool allow) external auth {
    require(types[role] > 0, "Roles/invalid-role");
    setRoleCapability(types[role], code, sig, allow);
  }
}
