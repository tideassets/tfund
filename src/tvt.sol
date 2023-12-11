// SPDX-License-Identifier: MIT
// Copyright (C) 2023
// tvt.sol: tide vetoken contract
//
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Auth} from "./auth.sol";
import {IOUToken} from "./IOU.sol";

interface IToken {
  function mint(address, uint) external;
  function burn(address, uint) external;
  function transfer(address, uint) external returns (bool);
  function transferFrom(address, address, uint) external returns (bool);
}

contract Approvals {
  mapping(bytes32 => address[]) public slates;
  mapping(address => bytes32) public votes;
  mapping(address => uint) public approvals;
  mapping(address => uint) public deposits;
  IToken public GOV; // voting token that gets locked up
  IToken public IOU; // non-voting representation of a token, for e.g. secondary voting mechanisms
  address public hat; // the chieftain's hat

  uint public MAX_YAYS;

  event Etch(bytes32 indexed slate);

  // IOU constructed outside this contract reduces deployment costs significantly
  // lock/free/vote are quite sensitive to token invariants. Caution is advised.
  constructor(address GOV_, uint MAX_YAYS_) {
    GOV = IToken(GOV_);
    // IOU = IToken(IOU_);
    MAX_YAYS = MAX_YAYS_;
  }

  function lock(uint wad) public {
    bool ok = GOV.transferFrom(msg.sender, address(this), wad);
    require(ok, "Approvals/failed-transfer");
    IOU.mint(msg.sender, wad);
    deposits[msg.sender] = deposits[msg.sender] + wad;
    addWeight(wad, votes[msg.sender]);
  }

  function free(uint wad) public {
    deposits[msg.sender] = deposits[msg.sender] - wad;
    subWeight(wad, votes[msg.sender]);
    GOV.burn(msg.sender, wad);
    bool ok = IOU.transfer(msg.sender, wad);
    require(ok, "Approvals/failed-transfer");
  }

  function etch(address[] memory yays) public returns (bytes32 slate) {
    require(yays.length <= MAX_YAYS);
    requireByteOrderedSet(yays);

    bytes32 hash = keccak256(abi.encodePacked(yays));
    slates[hash] = yays;
    emit Etch(hash);
    return hash;
  }

  function vote(address[] memory yays) public returns (bytes32) 
  // note  both sub-calls note
  {
    bytes32 slate = etch(yays);
    vote(slate);
    return slate;
  }

  function vote(bytes32 slate) public {
    require(slates[slate].length > 0, "ds-chief-invalid-slate");
    uint weight = deposits[msg.sender];
    subWeight(weight, votes[msg.sender]);
    votes[msg.sender] = slate;
    addWeight(weight, votes[msg.sender]);
  }

  // like `drop`/`swap` except simply "elect this address if it is higher than current hat"
  function lift(address whom) public {
    require(approvals[whom] > approvals[hat]);
    hat = whom;
  }

  function addWeight(uint weight, bytes32 slate) internal {
    address[] storage yays = slates[slate];
    for (uint i = 0; i < yays.length; i++) {
      approvals[yays[i]] = approvals[yays[i]] + weight;
    }
  }

  function subWeight(uint weight, bytes32 slate) internal {
    address[] storage yays = slates[slate];
    for (uint i = 0; i < yays.length; i++) {
      approvals[yays[i]] = approvals[yays[i]] - weight;
    }
  }

  // Throws unless the array of addresses is a ordered set.
  function requireByteOrderedSet(address[] memory yays) internal pure {
    if (yays.length == 0 || yays.length == 1) {
      return;
    }
    for (uint i = 0; i < yays.length - 1; i++) {
      // strict inequality ensures both ordering and uniqueness
      require((yays[i]) < (yays[i + 1]));
    }
  }
}

// `hat` address is unique root user (has every role) and the
// unique owner of role 0 (typically 'sys' or 'internal')
contract Chief is Approvals, Auth {
  constructor(address GOV, uint MAX_YAYS) Approvals(GOV, MAX_YAYS) {
    IOU = IToken(address(new IOUToken('IOU', "IOU token")));
  }
}

interface IRoleAuth {
  function canCall(address, address, bytes4) external view returns (bool);
}

abstract contract RoleAuth is Ownable, IRoleAuth {
  IRoleAuth public roleAuth;

  modifier auth() {
    require(isAuthorized_(msg.sender, msg.sig), "RoleAuth/not-authorized");
    _;
  }

  constructor() Ownable(msg.sender) {}

  function isAuthorized_(address src, bytes4 sig) internal view returns (bool) {
    if (src == address(this)) {
      return true;
    }
    if (src == owner()) {
      return true;
    }
    if (roleAuth == IRoleAuth(address(0))) {
      return false;
    }
    return roleAuth.canCall(src, address(this), sig);
  }

  function setRoles(IRoleAuth roleAuth_) external auth {
    roleAuth = roleAuth_;
  }
}

contract Roles is RoleAuth {
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

  function setAdmin(address usr, bool isAuth) external isAuthorized {
    admins[usr] = isAuth;
    emit SetAdmin(usr, isAuth);
  }

  function setPermission(bytes32 role, address contr, bytes4 sig, bool allow) external isAuthorized {
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
        d.roles.push(role);
        d.indexs[role] = d.roles.length;
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

  function setUserRole(address usr, bytes32 role, bool allow) external isAuthorized {
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
        d.roles.push(role);
        d.indexs[role] = d.roles.length;
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
