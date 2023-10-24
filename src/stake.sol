// SPDX-License-Identifier: MIT
// Copyright (C) 2023
// stake.sol : stake lp tokens for rewards
//

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./reward.sol";

contract Stake is ReentrancyGuard, Rewarder {
    IERC20 public lpToken;

    struct Deposit {
        uint amt;
        uint start;
    }

    mapping(address => Deposit[]) public stakes;
    mapping(address => uint) public canWithdraw;

    uint constant MIN_STAKE_DURATION = 7 days;
    uint public totalStakes;

    event Stakee(address indexed usr, uint amt);
    event Unstake(address indexed usr, uint amt);

    constructor(
        address lpToken_,
        address esToken_,
        address core_
    ) Rewarder(esToken_, core_) {
        lpToken = IERC20(lpToken_);
    }

    function stake(uint amt) external nonReentrant whenNotPaused {
        require(amt > 0, "Stake/zero-amount");
        lpToken.transferFrom(msg.sender, address(this), amt);
        Deposit memory stake_ = Deposit(amt, block.timestamp);
        stakes[msg.sender].push(stake_);
        _update(msg.sender);
        _addUser(msg.sender);
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
        for (uint i = 0; i < stakes[usr].length; i++) {
            Deposit memory stake_ = stakes[usr][i];
            amount += stake_.amt;
        }
        return (canWithdraw[usr], amount);
    }

    function update(address usr) external nonReentrant whenNotPaused {
        _update(usr);
    }

    function _update(address usr) internal override {
        (uint wa, uint sa) = stakeAmount(usr);
        if (wa + sa == 0) {
            _claimAll(usr);
            _delUser(usr);
            return;
        }

        for (uint i = 0; i < stakes[usr].length; i++) {
            Deposit memory stake_ = stakes[usr][i];
            if (stake_.start + MIN_STAKE_DURATION > block.timestamp) {
                continue;
            }
            uint amt = stake_.amt;
            canWithdraw[usr] += amt;
            totalStakes += amt;
            stakes[usr][i] = stakes[usr][stakes[usr].length - 1];
            stakes[usr].pop();
        }
    }

    function _getWeight(
        address usr
    ) internal view override returns (uint, uint) {
        return (canWithdraw[usr], totalStakes);
    }
}
