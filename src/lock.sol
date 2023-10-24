// SPDX-License-Identifier: MIT
// Copyright (C) 2023
// lock.sol : lock miner

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./auth.sol";

interface Miner {
    function mint(address, uint) external;
}

contract Lock is Auth {
    Miner public miner;

    mapping(bytes32 => uint) public remains;
    mapping(bytes32 => uint) public minted;
    mapping(bytes32 => address) public addrs;
    mapping(bytes32 => uint) public cycle;
    mapping(bytes32 => uint) public cycleMinted;

    uint public constant ONE = 1e18;
    uint public start;
    uint public initTeamLockLong = 300 days;
    uint public lpNext = 0;

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
        miner = Miner(token_);

        addrs["dao"] = dao_;
        addrs["tsaDao"] = tsaDao_;
        addrs["team"] = team_;
        addrs["lpFund"] = lpFund_;

        cycle["dao"] = 30 days;
        cycle["tsaDao"] = 30 days;
        cycle["team"] = 30 days;
        cycle["lpFund"] = 7 days;

        miner.mint(dao_, 2e7 * ONE);
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

    function changeDao(address dao) external auth {
        addrs["dao"] = dao;
    }

    function changeTsaDao(address tsaDao) external auth {
        addrs["tsaDao"] = tsaDao;
    }

    function changeTeam(address team) external auth {
        addrs["team"] = team;
    }

    function changeLpFund(address lpFund) external auth {
        addrs["lpFund"] = lpFund;
    }

    function daoMint() external {
        uint amt = _mint("dao", start);
        if (amt == 0) {
            return;
        }
        emit DaoMint(addrs["dao"], amt);
    }

    function tsaDaoMint() external {
        uint amt = _mint("tsaDao", start);
        if (amt == 0) {
            return;
        }
        emit TsaDaoMint(addrs["tsaDao"], amt);
    }

    function teamMint() external {
        uint amt = _mint("team", start + initTeamLockLong);
        if (amt == 0) {
            return;
        }
        emit TeamMint(addrs["team"], amt);
    }

    function lpFundMint() external {
        uint amt = _mint("lpFund", start);
        if (amt == 0) {
            return;
        }
        emit LpFundMint(addrs["lpFund"], amt);
    }

    function setLpNext(uint amt) external auth {
        lpNext = amt;
    }

    function _mint(
        bytes32 key,
        uint start_
    ) internal returns (uint) {
        if (block.timestamp < start_) {
            return 0;
        }

        if (remains[key] == 0) {
            return 0;
        }

        uint nth = (block.timestamp - start_) / cycle[key];
        uint amt = cycleMinted[key] * nth - minted[key];

        if (remains[key] < amt) {
            amt = remains[key];
        }

        if (amt == 0) {
            return 0;
        }

        remains[key] -= amt;
        miner.mint(addrs[key], amt);
        minted[key] += amt;
        return amt;
    }
}
