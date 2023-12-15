// SPDX-License-Identifier: MIT
// Copyright (C) 2023
// roles.sol: roles and permissions
//
pragma solidity ^0.8.20;

import {DSRoles} from "ds-roles/roles.sol";

// A single user can be assigned multiple roles, and a single role can include multiple users.
// Supports a maximum of 256 role types. New types can be added using the addType function.
// For example, addType("ROOT").
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
