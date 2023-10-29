// SPDX-License-Identifier: MIT
// Copyright (C) 2023
// stake.sol : stake lp tokens for rewards
//

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./auth.sol";

contract Stake is Auth, ReentrancyGuard {
    IERC20 public lpToken;

    struct Deposit {
        uint amt;
        uint start;
    }

    uint public depositId; 
    mapping (uint => Deposit) deposits;
    mapping(address => uint[]) public uids;
    mapping(address => uint) public canWithdraw;

    uint constant MIN_STAKE_DURATION = 7 days;
    uint public totalStakes;

    event Stakee(address indexed usr, uint amt);
    event Unstake(address indexed usr, uint amt);

    constructor(
        address lpToken_
    )  {
        lpToken = IERC20(lpToken_);
    }

    function stake(uint amt) external nonReentrant whenNotPaused {
        require(amt > 0, "Stake/zero-amount");
        lpToken.transferFrom(msg.sender, address(this), amt);

        Deposit memory stake_ = Deposit(amt, block.timestamp);
        depositId++;
        uids[msg.sender].push(depositId);
        deposits[depositId] = stake_;
        totalStakes += amt;

        _update(msg.sender);
        emit Stakee(msg.sender, amt);
    }

    function unstake() external nonReentrant whenNotPaused {
        uint amt = canWithdraw[msg.sender];
        unstake(amt);
    }

    function unstake(uint amt) public nonReentrant whenNotPaused {
        _update(msg.sender);
        require(canWithdraw[msg.sender] >= amt, "Stake/no-stake");
        canWithdraw[msg.sender] -= amt;
        totalStakes -= amt;
        lpToken.transfer(msg.sender, amt);

        emit Unstake(msg.sender, amt);
    }

    function stakeAmount(address usr) public view returns (uint, uint) {
        uint amount = 0;
        uint[] memory ids = uids[usr];
        mapping(uint => Deposit) storage stakes_ = deposits;
        for (uint i = 0; i < ids.length; i++) {
            if (ids[i] == 0) {
                continue;
            }
            Deposit memory stake_ = stakes_[ids[i]];
            amount += stake_.amt;
        }
        return (canWithdraw[usr], amount);
    }

    function update(address usr) external nonReentrant whenNotPaused {
        _update(usr);
    }

    function _update(address usr) internal {
        (uint wa, uint sa) = stakeAmount(usr);
        if (wa + sa == 0) {
            return;
        }

        uint amt = 0;
        uint[] memory ids = uids[usr];
        mapping(uint => Deposit) storage stakes_ = deposits;
        for (uint i = 0; i < ids.length; i++) {
            if (ids[i] == 0) {
                continue;
            }
            Deposit memory stake_ = stakes_[ids[i]];
            if (stake_.start + MIN_STAKE_DURATION > block.timestamp) {
                continue;
            }
            amt += stake_.amt;
            ids[i] = 0;
        }
        canWithdraw[usr] += amt;
    }

}
