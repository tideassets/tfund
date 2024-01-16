// SPDX-License-Identifier: MIT
// Copyright (C) 2023
// uses.sol : use estoken for rewards
//
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Auth} from "./auth.sol";

interface EsTokenLike {
  function deposit(address, uint) external;
}

interface StakerLike {
  function totalSupply() external view returns (uint);
  function balanceOf(address) external view returns (uint);
  function stkToken() external view returns (IERC20);
}

abstract contract RewarderBase is Auth, Initializable {
  using SafeERC20 for IERC20;

  IERC20 public rewardToken;
  StakerLike public staker;
  address public rewardValut;
  EsTokenLike public esToken;

  uint public constant ONE = 10 ** 18; // one coin

  function initialize(address rt, address staker_, address rv) public virtual initializer {
    rely(msg.sender);
    rewardToken = IERC20(rt);
    staker = StakerLike(staker_);
    rewardValut = rv;
  }

  modifier onlyStaker() {
    require(msg.sender == address(staker), "Rewarder/not-staker");
    _;
  }

  event Claim(address indexed usr, address recv, uint amount);

  function updateBefore(address usr, int amt) external onlyStaker whenNotPaused {
    _updateBefore(usr, amt);
  }

  function updateAfter(address usr, int amt) external onlyStaker whenNotPaused {
    _updateAfter(usr, amt);
  }

  function setEstoken(address est) external auth {
    esToken = EsTokenLike(est);
  }

  function _updateBefore(address usr, int amt) internal virtual {}

  function _updateAfter(address usr, int amt) internal virtual {}

  function claim(address recv) external whenNotPaused {
    uint amount = _claim(msg.sender);
    if (amount == 0) {
      return;
    }
    if (address(esToken) != address(0)) {
      IERC20(rewardToken).safeTransferFrom(rewardValut, address(this), amount);
      IERC20(rewardToken).forceApprove(address(esToken), amount);
      esToken.deposit(recv, amount);
    } else {
      IERC20(rewardToken).safeTransferFrom(rewardValut, recv, amount);
    }
    emit Claim(msg.sender, recv, amount);
  }

  function compound(address usr) external {}

  function _claim(address usr) internal virtual returns (uint);

  function claimable(address usr) public view virtual returns (uint);
}

// Periodic rewards
// When increasing and reducint the stake, you can only update the stake for the next cycle
// At the start of a new cycle, set the reward per stake (reward per stake ONE -> osr) for this cycle
// Because the osr for each cycle is different, when the user claims,
// the rewards for each cycle need to be calculated separately
contract RewarderCycle is RewarderBase {
  using SafeERC20 for IERC20;

  uint public cycleId;

  // key is cycle id, value is per cycle reward
  mapping(uint => uint) public pcrs;
  mapping(uint => uint) public totalStakes;
  // key1 is user, key2 is cycle id,  value is  stake
  mapping(address => mapping(uint => uint)) public us;
  // key is user, value is claimeded cycle id
  mapping(address => uint) public ucid;

  mapping(address => uint) public usid;

  uint public constant MIN = 1;

  // pcr: per cycle reward
  function _newCycle(uint pcr) internal {
    pcrs[cycleId] = pcr;
    cycleId++;
    totalStakes[cycleId] = staker.totalSupply();
  }

  function newCycle(uint pcr) external auth {
    _newCycle(pcr);
  }

  function _updateAfter(address usr, int) internal override {
    uint cid = cycleId;
    uint bal = staker.balanceOf(usr);
    mapping(uint => uint) storage us_ = us[usr];
    us_[cid + 1] = bal == 0 ? MIN : bal;
    usid[usr] = cid + 1;
  }

  function claimable(address usr) public view override returns (uint) {
    uint cid = cycleId;
    uint uid = ucid[usr] > 0 ? ucid[usr] : 1;
    uint amount = 0;
    uint last = 0; // last stake amount not zero
    mapping(uint => uint) storage us_ = us[usr];
    for (uint i = uid; i < cid; i++) {
      uint s = us_[i];
      if (s > 0) {
        last = s;
      } else {
        s = last;
      }
      if (s == MIN || s == 0) {
        continue;
      }
      amount += (s * pcrs[i]) / totalStakes[i];
    }
    return amount;
  }

  function _clear(address usr) internal {
    uint uid = ucid[usr];
    uint cid = cycleId;
    mapping(uint => uint) storage us_ = us[usr];
    for (uint i = uid; i < cid; i++) {
      delete us_[i];
    }
    ucid[usr] = cid;
    us_[cid] = staker.balanceOf(usr);
  }

  function _claim(address usr) internal override returns (uint) {
    uint amount = claimable(usr);
    _clear(usr);
    return amount;
  }
}

// The reward for staking ONE token for 1000 seconds is
// the same as the reward for staking 1000 tokens for 1 second
contract RewarderAccum is RewarderBase {
  using SafeERC20 for IERC20;

  uint public PSR; // per second reward
  uint public OPSR; // ONE token per second reward

  mapping(address => uint) public upts; // user update times
  mapping(address => uint) public uaas; // user accumulated amounts: uaas = upts * staker.balanceOf

  function setPSR(uint psr) external auth {
    PSR = psr;
  }

  function _updateBefore(address usr, int) internal override {
    _update(usr);
  }

  function _updateAfter(address, int) internal override {
    uint total = staker.totalSupply();
    OPSR = total == 0 ? 0 : PSR * ONE / total;
  }

  function _update(address usr) internal {
    uint u = block.timestamp - upts[usr];
    uint amt = accumAmt(usr, u);
    uaas[usr] = amt;
    upts[usr] = block.timestamp;
  }

  function claimable(address usr) public view override returns (uint) {
    uint du = block.timestamp - upts[usr];
    uint amt = accumAmt(usr, du);
    uint r = amt * OPSR / ONE;
    return r;
  }

  function accumAmt(address usr, uint du) public view returns (uint) {
    uint amt = uaas[usr];
    amt += du * staker.balanceOf(usr);
    return amt;
  }

  function _claim(address usr) internal override returns (uint) {
    _update(usr);

    uint reward = claimable(usr);
    uaas[usr] = 0;
    upts[usr] = block.timestamp;
    return reward;
  }
}
