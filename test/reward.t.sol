// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {RewarderCycle, RewarderAccum} from "../src/reward.sol";
import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Auth} from "../src/auth.sol";
import {RewarderLike, Stakex} from "../src/stake.sol";
import {IOU20} from "src/iou.sol";

contract MEsToken is ERC20 {
  constructor() ERC20("EsToken", "EST") {}

  function deposit(address usr, uint amt) external {
    _mint(usr, amt);
  }
}

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

contract RewarderAccumTest is Test {
  RewarderAccum public R;
  IOU20 iou;
  Stakex public staker;
  MEsToken public esToken;
  MRewardVault public rewardValut;
  MToken public reward;
  MToken public asset;

  uint constant RAY = 10 ** 27;

  function setUp() public {
    esToken = new MEsToken();
    rewardValut = new MRewardVault();
    reward = new MToken();
    asset = new MToken();

    staker = new Stakex();
    iou = new IOU20("stk IOU", "IOU");
    staker.initialize(address(asset), address(iou));
    iou.file("updater", address(staker));
    iou.file("owner", address(staker));
    R = new RewarderAccum(address(reward), address(staker), address(rewardValut));
    // R.setRPS(RAY * 315360 / 1000000 / (1 days * 365)); // yearly rate
    R.setRPS(1e9);

    reward.mint(address(rewardValut), 1e9 ether);
    asset.mint(address(this), 1e9 ether);

    rewardValut.doApprove(address(reward), address(R), type(uint).max);
    asset.approve(address(staker), type(uint).max);

    staker.addRewarder("TDT", address(R));
  }

  function onERC721Received(address, address, uint, bytes memory) public pure returns (bytes4) {
    return 0x150b7a02;
  }

  function testStake() public {
    staker.stake(address(this), 1 ether);
    assertEq(staker.balanceOf(address(this)), 1 ether);
    vm.warp(block.timestamp + 1 seconds);
    assertEq(R.claimable(address(this)), 1e9, "1 second should be same");
    vm.warp(block.timestamp + 100 seconds);
    assertEq(R.claimable(address(this)), 101 * 1e9, "100 second should be same");
    vm.warp(block.timestamp + 100 seconds);
    assertEq(R.claimable(address(this)), 201 * 1e9, "200 second should be same");
  }

  function testClaim() public {
    staker.stake(address(this), 1 ether);
    assertEq(staker.balanceOf(address(this)), 1 ether);

    vm.warp(block.timestamp + 1 seconds);
    assertEq(R.claimable(address(this)), 1e9, "assert 1 year");
    assertEq(reward.balanceOf(address(this)), 0, "balance should be zero before claim");
    R.claim(address(this));
    assertEq(reward.balanceOf(address(this)), 1e9, "assert 2 should be same");

    vm.warp(block.timestamp + 100 seconds);
    assertEq(R.claimable(address(this)), 100 * 1e9, "100 second should be same");
    R.claim(address(this));
    assertEq(reward.balanceOf(address(this)), 101e9, "101 second should be same");
    vm.warp(block.timestamp + 100 seconds);
    assertEq(R.claimable(address(this)), 100 * 1e9, "100 second should be same");
    R.claim(address(this));
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
  IOU20 iou;
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
    staker = new Stakex();
    iou = new IOU20("stk IOU", "IOU");
    staker.initialize(address(asset), address(iou));
    iou.file("updater", address(staker));
    iou.file("owner", address(staker));
    R = new RewarderCycle(address(reward), address(staker), address(rewardValut));

    R.newCycle(1e9);
    reward.mint(address(rewardValut), 1e9 ether);
    rewardValut.doApprove(address(reward), address(R), type(uint).max);

    asset.mint(address(this), 1e9 ether);
    asset.approve(address(staker), type(uint).max);

    staker.addRewarder("TDT", address(R));
  }

  function _testStake() public {
    staker.stake(address(this), 1 ether);
    assertEq(staker.balanceOf(address(this)), 1 ether);
    assertEq(R.claimable(address(this)), 0, "before new cycle, should be zero");
    R.newCycle(1e9);
    assertEq(R.claimable(address(this)), 0, "before new cycle, should be zero");
    R.newCycle(1e9);
    assertEq(R.claimable(address(this)), 1e9, "after new cycle, should NOT be zero");
  }

  function testStake() public {
    _testStake();

    assertEq(reward.balanceOf(address(this)), 0, "balance should be zero before claim");
    R.claim(address(this));
    assertEq(R.cycleId(), 3, "cycle id should be 3");
    assertEq(R.ucid(address(this)), 3, "cycle id should be 3");
    assertEq(staker.balanceOf(address(this)), 1 ether);
    assertEq(R.us(address(this), 3), 1 ether, "us should be 1 ether");
    assertEq(reward.balanceOf(address(this)), 1e9, "balance should be same 1 secon");

    R.newCycle(1e9);
    assertEq(R.cycleId(), 4, "cycle id should be 4");
    assertEq(R.claimable(address(this)), 1e9, "should be 1e9");
  }

  function testClaim() public {
    staker.stake(address(this), 1 ether);
    assertEq(staker.balanceOf(address(this)), 1 ether);

    R.newCycle(1e9);
    R.newCycle(1e9);
    R.newCycle(1e9);
    R.newCycle(1e9);
    staker.stake(address(this), 1 ether);
    R.newCycle(1e9);
    R.newCycle(1e9);
    assertEq(R.claimable(address(this)), 6e9, "should be 6e9");
    uint balance = reward.balanceOf(address(this));
    R.claim(address(this));
    assertEq(reward.balanceOf(address(this)), balance + 6e9, "balance should be same");
  }

  function testUnstake() external {
    testClaim();
    staker.unstake(address(this), 2 ether);
    R.newCycle(1e9);
    assertEq(R.claimable(address(this)), 0, "claimable should be zero");
    testClaim();
  }

  function testTransfer() external {
    staker.stake(address(this), 2 ether);
    R.newCycle(1e9);
    iou.transfer(address(0x123), 1 ether);
    assertEq(staker.balanceOf(address(this)), 1 ether);
    assertEq(staker.balanceOf(address(0x123)), 1 ether);

    R.newCycle(1e9);
    R.newCycle(1e9);
    assertEq(R.claimable(address(this)), 2e9, "this should be 1e9");
    assertEq(R.claimable(address(0x123)), 1e9, "123 should be 1e9");

    iou.transfer(address(0x123), 1 ether);
    assertEq(staker.balanceOf(address(this)), 0);
    assertEq(staker.balanceOf(address(0x123)), 2 ether);

    R.newCycle(1e9);
    R.newCycle(1e9);
    assertEq(R.claimable(address(this)), 2e9, "this should be 1e9");
    assertEq(R.claimable(address(0x123)), 4e9, "123 should be 3e9");
  }

  function testTransferFrom() external {
    staker.stake(address(this), 2 ether);
    R.newCycle(1e9);
    iou.approve(address(this), 1 ether);
    iou.transferFrom(address(this), address(0x123), 1 ether);
    assertEq(staker.balanceOf(address(this)), 1 ether);
    assertEq(staker.balanceOf(address(0x123)), 1 ether);

    R.newCycle(1e9);
    R.newCycle(1e9);
    assertEq(R.claimable(address(this)), 2e9, "this should be 1e9");
    assertEq(R.claimable(address(0x123)), 1e9, "123 should be 1e9");

    iou.transfer(address(0x123), 1 ether);
    assertEq(staker.balanceOf(address(this)), 0);
    assertEq(staker.balanceOf(address(0x123)), 2 ether);

    R.newCycle(1e9);
    R.newCycle(1e9);
    assertEq(R.claimable(address(this)), 2e9, "this should be 1e9");
    assertEq(R.claimable(address(0x123)), 4e9, "123 should be 3e9");
  }
}
