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

contract RTokens is Auth {
  address[] public rtokens;
  mapping(address => uint) public rtokenIndex;

  function count() public view returns (uint) {
    return rtokens.length;
  }

  function addRtoken(address rtoken) external auth {
    _addRtoken(rtoken);
  }

  function delRtoken(address rtoken) external auth {
    _delRtoken(rtoken);
  }

  function _addRtoken(address rtoken) internal virtual {
    if (rtokenIndex[rtoken] == 0) {
      rtokens.push(rtoken);
      rtokenIndex[rtoken] = rtokens.length;
    }
  }

  function _delRtoken(address rtoken) internal virtual {
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
  using SafeERC20 for IERC20;

  IERC20 public rewardToken;
  EsTokenLike public esToken;

  uint public useEs; // if use esToken for core
  uint public constant ONE = 10 ** 18; // one coin

  constructor(address rt, address est) {
    rewardToken = IERC20(rt);
    esToken = EsTokenLike(est);
  }

  function useEsToken() external auth {
    useEs = 1;
  }

  event SendReward(uint amount);
  event Claim(address indexed usr, address recv, uint amount);

  function stake(
    address usr,
    uint amt
  ) external nonReentrant whenNotPaused auth {
    _stake(usr, amt);
  }

  function unstake(
    address usr,
    uint amt
  ) external nonReentrant whenNotPaused auth {
    _unstake(usr, amt);
  }

  function _stake(address usr, uint amt) internal virtual;

  function _unstake(address usr, uint amt) internal virtual;

  function claim(
    address usr,
    address recv
  ) external nonReentrant whenNotPaused {
    uint amount = _claim(usr);
    if (useEs == 1) {
      IERC20(rewardToken).approve(address(esToken), amount);
      esToken.deposit(recv, amount);
    } else {
      IERC20(rewardToken).transfer(recv, amount);
    }
    emit Claim(usr, recv, amount);
  }

  function _claim(address usr) internal virtual returns (uint);

  function _claim(address usr, uint amt) internal virtual returns (uint);

  function claimable(address usr) public view virtual returns (uint);

  function sendReward(uint amount) external virtual;

  function _newCycle() internal virtual {}
}

contract RewarderCycle is BaseRewarder {
  using SafeERC20 for IERC20;

  uint public CYCLE = 7 days;
  uint cycleId;
  uint public totalStakes;

  mapping(address => mapping(uint => uint)) public usrStakes;
  mapping(uint => uint) public oneRewardPerCycle;
  mapping(uint => uint) public cycleRewards;
  mapping(address => uint) public notClaimed;
  mapping(address => uint) public updatedCycle;

  constructor(address rt, address est) BaseRewarder(rt, est) {}

  function sendReward(
    uint amount
  ) external override nonReentrant whenNotPaused auth {
    // IERC20(rewardToken).safeTransferFrom(msg.sender, address(this), amount);
    cycleRewards[cycleId] += amount;
    _newCycle();
    emit SendReward(amount);
  }

  function _newCycle() internal override {
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
    uint ucid = updatedCycle[usr] + 1;
    uint cid = cycleId;
    uint amount = 0;
    mapping(uint => uint) storage usrStakes_ = usrStakes[usr];
    for (uint i = ucid; i < cid; i++) {
      amount += (usrStakes_[i] * oneRewardPerCycle[i]) / ONE;
    }
    return amount;
  }

  function _claim(address usr) internal override returns (uint) {
    uint able = claimable(usr);
    require(able > 0, "Rewarder/no-reward");
    updatedCycle[usr] = cycleId;
    uint not = notClaimed[usr];
    notClaimed[usr] = 0;
    return not + able;
  }

  function _claim(address usr, uint amt) internal override returns (uint) {
    uint amount = claimable(usr);
    require(amount > amt, "Rewarder/no-reward");
    updatedCycle[usr] = cycleId;
    notClaimed[usr] += amount - amt;
    return amt;
  }
}

contract RewarderPerSecond is BaseRewarder {
  using SafeERC20 for IERC20;

  uint public totalAccumulatedReward;
  uint public rewardPerSecond;

  mapping(address => uint) public usrStakes;
  mapping(address => uint) public usrUpdateTime;
  mapping(address => uint) public usrAccumulatedReward;

  constructor(address rt, address est) BaseRewarder(rt, est) {}

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

  function _claim(address usr) internal override returns (uint) {
    _update(usr);

    uint amt = accumulatedAmount(usr);
    require(amt > 0, "Rewarder/no-reward");

    usrAccumulatedReward[usr] = 0;
    totalAccumulatedReward -= amt;

    uint rwd = (amt * rewardPerSecond) / totalAccumulatedReward;
    return rwd;
  }

  function _claim(address usr, uint amt) internal override returns (uint) {
    require(amt > 0, "Rewarder/zero amt");

    _update(usr);
    uint ca = accumulatedAmount(usr);
    require(ca > 0, "Rewarder/no-accumalated");

    uint rca = (amt * totalAccumulatedReward) / rewardPerSecond;
    require(ca > rca, "Rewarder/no-acculumated");
    usrAccumulatedReward[usr] = ca - rca;
    totalAccumulatedReward -= rca;

    return amt;
  }
}
