// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {RewarderCycle, RewarderPerSecond} from "../src/reward.sol";
import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Auth} from "../src/auth.sol";
import {RewarderLike, Stakex} from "../src/stake.sol";

contract MStaker is ERC20 {
  constructor() ERC20("Staker", "STK") {}

  address rtoken;
  address rewarder;

  // function mint(address usr, uint amt) external {
  //   _mint(usr, amt);
  // }

  // function burn(address usr, uint amt) external {
  //   _burn(usr, amt);
  // }

  function stake(address usr, uint amt) external {
    RewarderLike(rewarder).stake(usr, amt);
    _mint(usr, amt);
  }

  function unstake(address usr, uint amt) external {
    RewarderLike(rewarder).unstake(usr, amt);
    _burn(usr, amt);
  }

  function addRtoken(address rtoken_, address rewarder_) external {
    rtoken = rtoken_;
    rewarder = rewarder_;
  }
}

contract MEsToken is ERC20 {
  constructor() ERC20("EsToken", "EST") {}

  function deposit(address usr, uint amt) external {
    _mint(usr, amt);
  }
}

// contract MRewardValut is Auth, ERC20 {
//   constructor() ERC20("RewardValut", "RV") {}

//   function getReward(address rtoken, uint amt) external auth returns (uint) {
//     IERC20(rtoken).transfer(msg.sender, amt);
//     return amt;
//   }
// }

contract MRewardVault is Auth {
  function doApprove(address token, address usr, uint amt) external auth {
    IERC20(token).approve(usr, amt);
  }
}

contract MToken is ERC20, Auth {
  constructor() ERC20("Token", "TKN") {}

  function mint(address usr, uint amt) external auth {
    _mint(usr, amt);
  }
}

contract RewarderPerSecondTest is Test {
  RewarderPerSecond public R;
  Stakex public staker;
  MEsToken public esToken;
  MRewardVault public rewardValut;
  MToken public reward;
  MToken public asset;

  function setUp() public {
    esToken = new MEsToken();
    rewardValut = new MRewardVault();
    reward = new MToken();
    asset = new MToken();

    staker = new Stakex("Staker", "STK", address(asset));
    R = new RewarderPerSecond(address(reward), address(staker), address(rewardValut));
    R.setRewardPerSecond(1e9);

    reward.mint(address(rewardValut), 1e9 ether);
    asset.mint(address(this), 1e9 ether);

    rewardValut.doApprove(address(reward), address(R), type(uint).max);
    asset.approve(address(staker), type(uint).max);

    staker.addRtoken(address(reward), address(R));
  }

  function testStake() public {
    staker.stake(address(this), 1 ether);
    assertEq(staker.balanceOf(address(this)), 1 ether);
    vm.warp(block.timestamp + 1 seconds);
    assertEq(R.claimable(address(this)), 1e9, "1 second should be same");
    // vm.warp(block.timestamp + 100 seconds);
    // assertEq(R.claimable(address(this)), 101 * 1e9, "100 second should be same");
    // vm.warp(block.timestamp + 100 seconds);
    // assertEq(R.claimable(address(this)), 201 * 1e9, "200 second should be same");
  }

  function testClaim() public {
    staker.stake(address(this), 1 ether);
    assertEq(staker.balanceOf(address(this)), 1 ether);

    vm.warp(block.timestamp + 1 seconds);
    assertEq(R.claimable(address(this)), 1e9, "1 second should be same");
    assertEq(reward.balanceOf(address(this)), 0, "balance should be zero before claim");
    R.claim(address(this), address(this));
    assertEq(reward.balanceOf(address(this)), 1e9, "balance should be same 1 secon");

    vm.warp(block.timestamp + 100 seconds);
    assertEq(R.claimable(address(this)), 100 * 1e9, "100 second should be same");
    R.claim(address(this), address(this));
    assertEq(reward.balanceOf(address(this)), 101e9, "101 second should be same");
    vm.warp(block.timestamp + 100 seconds);
    assertEq(R.claimable(address(this)), 100 * 1e9, "100 second should be same");
    R.claim(address(this), address(this));
    assertEq(reward.balanceOf(address(this)), 201e9, "201 second should be same");
  }

  function testUnstake() external {
    testClaim();
    staker.unstake(address(this), 1 ether);
    vm.warp(block.timestamp + 100 seconds);
    assertEq(R.claimable(address(this)), 0, "claimable should be zero");
    testStake();
  }
}

contract RewarderCycleTest is Test {
  RewarderCycle public R;
  MStaker public staker;
  MEsToken public esToken;
  MRewardVault public rewardValut;
  MToken public reward;
  MToken public asset;

  function setUp() public {
    staker = new MStaker();
    esToken = new MEsToken();
    rewardValut = new MRewardVault();
    reward = new MToken();
    asset = new MToken();
    R = new RewarderCycle(address(reward), address(staker), address(rewardValut));
    R.newCycle(1e9);
    reward.mint(address(rewardValut), 1e9 ether);
    rewardValut.doApprove(address(reward), address(R), type(uint).max);

    staker.addRtoken(address(reward), address(R));
  }

  function testStake() public {
    staker.stake(address(this), 1 ether);
    assertEq(staker.balanceOf(address(this)), 1 ether);
    vm.warp(1 seconds);
    assertEq(R.claimable(address(this)), 0, "before new cycle, should be zero");
  }

  function testClaim() public {
    staker.stake(address(this), 1 ether);
    assertEq(staker.balanceOf(address(this)), 1 ether);

    vm.warp(1 seconds);
    assertEq(R.claimable(address(this)), 1e9, "1 second should be same");
    assertEq(reward.balanceOf(address(this)), 0, "balance should be zero before claim");
    R.claim(address(this), address(this));
    assertEq(reward.balanceOf(address(this)), 1e9, "balance should be same 1 secon");

    vm.warp(block.timestamp + 100 seconds);
    assertEq(R.claimable(address(this)), 100 * 1e9, "100 second should be same");
    R.claim(address(this), address(this));
    assertEq(reward.balanceOf(address(this)), 101e9, "101 second should be same");
    vm.warp(block.timestamp + 100 seconds);
    assertEq(R.claimable(address(this)), 100 * 1e9, "100 second should be same");
    R.claim(address(this), address(this));
    assertEq(reward.balanceOf(address(this)), 201e9, "201 second should be same");
  }
}
