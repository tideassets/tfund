// SPDX-License-Identifier: MIT
// Copyright (C) 2023
// auth.sol : multiple auth and pause able
//

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/Pausable.sol";

abstract contract Auth is Pausable {
    mapping(address => uint) internal wards;

    modifier auth() {
        require(wards[msg.sender] == 1, "Val/not-authorized");
        _;
    }

    function rely(address usr) external auth {
        wards[usr] = 1;
        emit Rely(usr);
    }

    function deny(address usr) external auth {
        wards[usr] = 0;
        emit Deny(usr);
    }

    event Rely(address indexed usr);
    event Deny(address indexed usr);

    function pause() external auth {
        _pause();
    }

    function unpause() external auth {
        _unpause();
    }

    constructor() {
        wards[msg.sender] = 1;
    }
}
