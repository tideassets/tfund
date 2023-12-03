// SPDX-License-Identifier: MIT
// Copyright (C) 2023
// uses.sol : use estoken for rewards
//
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Auth} from "./auth.sol";

interface EsTokenLike {
  function deposit(address, uint) external;
}

interface Staker is IERC20 {}

abstract contract BaseRewarder is Auth {
  using SafeERC20 for IERC20;

  IERC20 public rewardToken;
  Staker public staker;
  address public rewardValut;
  EsTokenLike public esToken;

  uint public constant ONE = 10 ** 18; // one coin

  constructor(address rt, address staker_, address rv) {
    rewardToken = IERC20(rt);
    staker = Staker(staker_);
    rewardValut = rv;
  }

  modifier onlyStaker() {
    require(msg.sender == address(staker), "Rewarder/not-staker");
    _;
  }

  event SendReward(uint amount);
  event Claim(address indexed usr, address recv, uint amount);

  function stake(address usr, uint amt) external onlyStaker {
    _stake(usr, amt);
  }

  function unstake(address usr, uint amt) external onlyStaker {
    _unstake(usr, amt);
  }

  function setEstoken(address est) external auth {
    esToken = EsTokenLike(est);
  }

  function _stake(address usr, uint amt) internal virtual;

  function _unstake(address usr, uint amt) internal virtual;

  function claim(address usr, address recv) external {
    uint amount = _claim(usr);
    if (address(esToken) != address(0)) {
      IERC20(rewardToken).approve(address(esToken), amount);
      esToken.deposit(recv, amount);
    } else {
      IERC20(rewardToken).safeTransferFrom(rewardValut, recv, amount);
    }
    emit Claim(usr, recv, amount);
  }

  function _claim(address usr) internal virtual returns (uint);

  function claimable(address usr) public view virtual returns (uint);
}

contract RewarderCycle is BaseRewarder {
  using SafeERC20 for IERC20;

  uint public CYCLE = 7 days;
  uint cycleId;
  uint public totalStakes;

  // key is cycle id, value is reward per stake one
  mapping(uint => uint) public osr;
  // key1 is user, key2 is cycle id,  value is  stake
  mapping(address => mapping(uint => uint)) public us;
  // key is user, value is claimeded cycle id
  mapping(address => uint) public uccid;

  uint public constant MIN = 1;

  constructor(address rt, address stk, address rv) BaseRewarder(rt, stk, rv) {}

  function _newCycle(uint rps) internal {
    // uint ramt = rewardValut.getReward(address(rewardToken), cycleId);
    cycleId++;
    osr[cycleId] = rps; //(ramt * ONE) / totalStakes;
    totalStakes = staker.totalSupply();
  }

  function newCycle(uint rps) external {
    _newCycle(rps);
  }

  // _stake add stake amount to next cycle
  function _stake(address usr, uint amt) internal override {
    us[usr][cycleId + 1] = amt;
    uccid[usr] = cycleId;
  }

  // _unstake reduce stake amount from current cycle
  function _unstake(address usr, uint amt) internal override {
    totalStakes -= amt;
    uint s = us[usr][cycleId];
    if (s == 0) {
      s = staker.balanceOf(usr);
      us[usr][cycleId] = s;
    }
    if (s == 0) {
      return;
    }
    s -= amt;
    if (s == 0) {
      s = MIN;
    }
    us[usr][cycleId] = s;
  }

  function claimable(address usr) public view override returns (uint) {
    uint ucid = uccid[usr];
    uint cid = cycleId;
    uint amount = 0;
    uint last = 0;
    mapping(uint => uint) storage us_ = us[usr];
    for (uint i = ucid; i < cid; i++) {
      uint s = us_[i];
      if (s == 0) {
        s = us_[i - 1];
      }
      if (s == 0) {
        s = last;
      }
      if (s == MIN) {
        s = 0;
      }
      if (s > 0) {
        last = s;
      }
      amount += (s * osr[i]) / ONE;
    }
    return amount;
  }

  function _clear(address usr) internal {
    uint ucid = uccid[usr];
    uint cid = cycleId;
    mapping(uint => uint) storage us_ = us[usr];
    for (uint i = ucid; i < cid; i++) {
      delete us_[i];
    }
    us_[cid] = staker.balanceOf(usr);
    uccid[usr] = cid;
  }

  function _claim(address usr) internal override returns (uint) {
    uint amount = claimable(usr);
    _clear(usr);
    return amount;
  }
}

contract RewarderPerSecond is BaseRewarder {
  using SafeERC20 for IERC20;

  uint public rewardPerSecond;

  mapping(address => uint) public usrUpdateTime;
  mapping(address => uint) public usrAccumulatedReward;

  constructor(address rt, address stk, address rv) BaseRewarder(rt, stk, rv) {}

  function setRewardPerSecond(uint amount) external auth {
    rewardPerSecond = amount;
  }

  function _stake(address usr, uint) internal override {
    _update(usr);
  }

  function _unstake(address usr, uint) internal override {
    _update(usr);
  }

  function _update(address usr) internal {
    uint u = block.timestamp - usrUpdateTime[usr];
    uint amt = accumulatedAmount(usr, u);
    usrAccumulatedReward[usr] = amt;
    usrUpdateTime[usr] = block.timestamp;
  }

  function claimable(address usr) public view override returns (uint) {
    uint u = block.timestamp - usrUpdateTime[usr];
    uint amt = accumulatedAmount(usr, u);
    uint reward = amt * rewardPerSecond / ONE;
    return reward;
  }

  function accumulatedAmount(address usr, uint duration) public view returns (uint) {
    uint amt = usrAccumulatedReward[usr];
    amt += duration * staker.balanceOf(usr);
    return amt;
  }

  function _claim(address usr) internal override returns (uint) {
    _update(usr);

    uint reward = claimable(usr);
    usrAccumulatedReward[usr] = 0;
    return reward;
  }
}

// 抵押资产,获取排放奖励
// 抵押方式: 1. 周期性抵押; 2. 持续抵押
// 周期性抵押: 每个周期结束时,计算每个周期的奖励,并将奖励存入下个周期
// 持续抵押: 每次抵押或解押时,计算奖励,并将奖励存入下个周期
// 周期性抵押的奖励计算方式: 周期奖励 = 周期奖励总量 / 总抵押量 * 用户抵押量
// 持续抵押的奖励计算方式: 奖励 = OATP(one asset token one second)每秒奖励 / 总抵押累积量 * 用户抵押累积量
// 抵押累积量就是多少个OATP累积的量. 比如, OATP是1, 如果100个币抵押100秒, 则抵押累积量是10000
// 奖励代币可以是任意ERC20代币或者ES代币, 如果奖励代币是ES代币,则奖励代币会自动存入ES代币合约
// 奖励代币和抵押代币可以是同一个代币, 也可以是不同的代币. 但是抵押代币必须是ERC20代币, 如果是NFT代币, 则需要先转换成ERC20代币
// 奖励代币需要从奖励金库地址中获取, 奖励金库地址可以是任意地址, 但是需要先将奖励代币存入奖励金库地址
// 一种抵押代币可以有多个奖励代币
