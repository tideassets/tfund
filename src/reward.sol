// SPDX-License-Identifier: MIT
// Copyright (C) 2023
// uses.sol : use estoken for rewards
//

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./auth.sol";

interface EsTokenLike {
    function deposit(address, uint) external;
}

// Rewarder: calculate reward and send reward
abstract contract RTokens is Auth {
    // rtokens: all reward token
    IERC20[] public rtokens;
    // rtokenIndex: rtoken index in rtokens
    mapping(address => uint) public rtokenIndex;

    function addRtoken(address rtoken) external auth {
        _addRtoken(rtoken);
    }

    function delRtoken(address rtoken) external auth {
        _delRtoken(rtoken);
    }

    function _addRtoken(address rtoken) internal {
        if (rtokenIndex[rtoken] == 0) {
            rtokens.push(IERC20(rtoken));
            rtokenIndex[rtoken] = rtokens.length;
        }
    }

    function _delRtoken(address rtoken) internal {
        if (rtokenIndex[rtoken] > 0) {
            uint index = rtokenIndex[rtoken] - 1;
            rtokens[index] = rtokens[rtokens.length - 1];
            rtokenIndex[address(rtokens[index])] = index + 1;
            rtokens.pop();
            rtokenIndex[rtoken] = 0;
        }
    }
}

abstract contract BaseRewarder is Auth, ReentrancyGuard {
    EsTokenLike public esToken;
    IERC20 public rewardToken;
    uint public useEs; // if use esToken for core
    uint public constant ONE = 10 ** 18; // one coin

    constructor(address esToken_, address rewardToken_) {
        esToken = EsTokenLike(esToken_);
        rewardToken = IERC20(rewardToken_);
    }

    function useEsToken() external auth {
        useEs = 1;
    }

    event SendReward(uint amount);
    event Claim(address indexed usr, uint amount);

    function _stake(address usr, uint amt) internal virtual;

    function _unstake(address usr, uint amt) internal virtual;

    function claim(address usr) public virtual;

    function claimable(address usr) public view virtual returns (uint);

    function sendReward(uint amount) external virtual;
}

abstract contract RewarderCycle is BaseRewarder {
    using SafeERC20 for IERC20;

    uint public CYCLE = 7 days;
    uint cycleId;
    uint public totalStakes;

    mapping(address => mapping(uint => uint)) public usrStakes;
    mapping(uint => uint) public oneRewardPerCycle;
    mapping(uint => uint) public cycleRewards;
    mapping(address => uint) public notClaimed;
    mapping(address => uint) public claimCycleId;

    constructor(
        address esToken_,
        address core_
    ) BaseRewarder(esToken_, core_) {}

    function sendReward(
        uint amount
    ) external override nonReentrant whenNotPaused {
        IERC20(rewardToken).safeTransferFrom(msg.sender, address(this), amount);
        cycleRewards[cycleId] += amount;
        emit SendReward(amount);
    }

    function newCycle() external auth {
        uint amount = cycleRewards[cycleId];
        oneRewardPerCycle[cycleId] = (amount * ONE) / totalStakes;
        cycleId++;
    }

    function _stake(address usr, uint amt) internal override {
        totalStakes += amt;
        uint cid = cycleId;
        usrStakes[usr][cid + 1] += amt;
    }

    function _unstake(address usr, uint amt) internal override {
        totalStakes += amt;
        uint cid = cycleId;
        usrStakes[usr][cid] -= amt;
    }

    function claimable(address usr) public view override returns (uint) {
        uint ucid = claimCycleId[usr] + 1;
        uint cid = cycleId;
        uint amount = 0;
        mapping(uint => uint) storage usrStakes_ = usrStakes[usr];
        for (uint i = ucid; i < cid; i++) {
            amount += (usrStakes_[i] * oneRewardPerCycle[i]) / ONE;
        }
        return amount;
    }

    function claim(address usr) public override nonReentrant whenNotPaused {
        uint amount = claimable(usr);
        require(amount > 0, "Rewarder/no-reward");
        claimCycleId[usr] = cycleId;
        if (useEs == 1) {
            IERC20(rewardToken).approve(address(esToken), amount);
            esToken.deposit(usr, amount);
        } else {
            IERC20(rewardToken).transfer(usr, amount);
        }
        emit Claim(usr, amount);
    }
}

abstract contract RewarderPerSecond is BaseRewarder {
    using SafeERC20 for IERC20;

    uint public totalAccumulatedReward;
    uint public rewardPerSecond;

    mapping(address => uint) public usrAccumulatedReward;
    mapping(address => uint) public usrStakes;
    mapping(address => uint) public usrUpdateTime;

    constructor(
        address esToken_,
        address core_
    ) BaseRewarder(esToken_, core_) {}

    function setRewardPerSecond(uint amount) external auth {
        rewardPerSecond = amount;
    }

    function _stake(address usr, uint amt) internal override {
        _update(usr);
        usrStakes[usr] += amt;
    }

    function _unstake(address usr, uint amt) internal override {
        _update(usr);
        usrStakes[usr] -= amt;
    }

    function sendReward(
        uint amount
    ) external override nonReentrant whenNotPaused {
        IERC20(rewardToken).safeTransferFrom(msg.sender, address(this), amount);
        emit SendReward(amount);
    }

    function _update(address usr) internal {
        uint amt = accumulatedAmount(usr);
        usrAccumulatedReward[usr] += amt;
        usrUpdateTime[usr] = block.timestamp;
        totalAccumulatedReward += amt;
    }

    function claimable(address usr) public view override returns (uint) {
        uint amt = accumulatedAmount(usr);
        uint reward = (amt * rewardPerSecond) / totalAccumulatedReward;
        return reward;
    }

    function accumulatedAmount(address usr) public view returns (uint) {
        uint ut = usrUpdateTime[usr];
        uint amt = usrAccumulatedReward[usr];
        amt += (block.timestamp - ut) * usrStakes[usr];
        return amt;
    }

    function claim(address usr) public override nonReentrant whenNotPaused {
        _update(usr);

        uint amt = accumulatedAmount(usr);
        require(amt > 0, "Rewarder/no-reward");

        usrAccumulatedReward[usr] = 0;
        totalAccumulatedReward -= amt;

        uint rwd = (amt * rewardPerSecond) / totalAccumulatedReward;
        if (useEs == 1) {
            IERC20(rewardToken).approve(address(esToken), rwd);
            esToken.deposit(usr, rwd);
        } else {
            IERC20(rewardToken).transfer(usr, rwd);
        }
        emit Claim(usr, rwd);
    }
}
