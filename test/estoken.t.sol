// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {EsToken} from "../src/estoken.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract A is ERC20 {
  constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

  function mint(address to, uint amount) public {
    _mint(to, amount);
  }

  function burn(address from, uint amount) public {
    _burn(from, amount);
  }
}

contract EsTokenTest is Test {
  EsToken esToken;
  A ANYONE;
  uint public constant ONE = 10 ** 18;

  function setUp() public {
    ANYONE = new A("Anyone", "ANY");
    esToken = new EsToken(address(ANYONE), "Test Token", "TT");
    ANYONE.mint(address(this), 1000 ether);
    ANYONE.approve(address(esToken), 1000 ether);
  }

  function testVesting() public {
    uint amt = 100 ether;
    esToken.mint(address(this), amt);
    uint vestingId = esToken.vesting(amt);
    assertTrue(vestingId > 0, "Vesting ID should be greater than 0");
  }

  function testClaim() public {
    uint amt = 300 ether;
    esToken.deposit(address(this), amt);
    assertEq(ANYONE.balanceOf(address(this)), 700 ether, "ANYONE balance should be reduced");
    uint vestingId = esToken.vesting(amt);
    assertTrue(vestingId > 0, "Vesting ID should be greater than 0");
    assertEq(esToken.VESTING_DURATION(), 180 days, "Vesting duration should be 180 days");

    // Increase time by 30 days
    vm.warp(block.timestamp + 30 days);

    uint claimedAmt = esToken.claim(address(this));
    assertTrue(claimedAmt > 0, "Claimed amount should be greater than 0");
    assertTrue(50 ether - claimedAmt < 1 ether, "Claimed amount should be 50");
    assertEq(esToken.balanceOf(address(this)), 0, "Balance should be 250");
    assertTrue(
      750 ether - ANYONE.balanceOf(address(this)) < 1 ether, "ANYONE balance should be reduced"
    );
  }

  function testMultipleClaim() public {
    testClaim();

    vm.warp(block.timestamp + 30 days);
    uint claimedAmt2 = esToken.claim(address(this));
    assertEq(claimedAmt2, 50 ether, "Claimed amount should be 50");
    assertEq(esToken.balanceOf(address(this)), 0, "Balance should be 250");
    assertEq(ANYONE.balanceOf(address(this)), 800 ether, "ANYONE balance should be reduced");

    vm.warp(block.timestamp + 120 days);
    uint claimedAmt3 = esToken.claim(address(this));
    assertEq(claimedAmt3, 200 ether, "Claimed amount should be 50");
    assertEq(esToken.balanceOf(address(this)), 0, "Balance should be 250");
    assertEq(ANYONE.balanceOf(address(this)), 1000 ether, "ANYONE balance should be reduced");
  }

  function testMultipleVest() public {
    uint amt1 = 100 ether;
    uint amt2 = 200 ether;

    esToken.deposit(address(this), amt1);
    esToken.deposit(address(this), amt2);

    uint vestingId1 = esToken.vesting(amt1);
    assertTrue(vestingId1 > 0, "First vesting ID should be greater than 0");

    uint vestingId2 = esToken.vesting(amt2);
    assertTrue(vestingId2 > vestingId1, "Second vesting ID should be greater than the first one");

    uint[] memory ids = new uint[](2);
    ids[0] = esToken.vestingIds(address(this), 0);
    ids[1] = esToken.vestingIds(address(this), 1);
    assertEq(ids.length, 2, "There should be two vesting IDs");
    assertEq(ids[0], vestingId1, "The first vesting ID should match");
    assertEq(ids[1], vestingId2, "The second vesting ID should match");
  }

  function testVestingDuration() public {
    assertEq(esToken.VESTING_DURATION(), 180 days, "Vesting duration should be 180 days");
    esToken.setVestingDuration(90 days);
    assertEq(esToken.VESTING_DURATION(), 90 days, "Vesting duration should be 90 days");
  }

  function testMultipleVestAndClaim() public {
    uint amt = 900 ether;
    uint vamt = 300 ether;
    assertEq(esToken.VESTING_DURATION(), 180 days, "Vesting duration should be 180 days");

    esToken.deposit(address(this), amt);
    assertEq(ANYONE.balanceOf(address(this)), 100 ether, "this balance should be 100 ether");

    uint vestingId1 = esToken.vesting(vamt);
    assertTrue(vestingId1 > 0, "First vesting ID should be greater than 0");

    vm.warp(block.timestamp + 60 days);
    uint claimedAmt1 = esToken.claim(address(this));
    assertEq(claimedAmt1, 100 ether, "Claimed amount should be 50");
    assertEq(esToken.balanceOf(address(this)), 600 ether, "Balance should be 600");
    assertEq(ANYONE.balanceOf(address(this)), 200 ether, "this balance should be 200 ether");
    uint vestingId2 = esToken.vesting(vamt);
    assertTrue(vestingId2 > vestingId1, "Second vesting ID should be greater than the first one");

    vm.warp(block.timestamp + 60 days);
    uint claimedAmt2 = esToken.claim(address(this));
    assertEq(claimedAmt2, 200 ether, "Claimed amount should be 50");
    assertEq(esToken.balanceOf(address(this)), 300 ether, "Balance should be 250");
    assertEq(ANYONE.balanceOf(address(this)), 400 ether, "ANYONE balance should be reduced");

    uint vestingId3 = esToken.vesting(vamt);
    assertTrue(vestingId3 > vestingId2, "Third vesting ID should be greater than the second one");

    vm.warp(block.timestamp + 60 days);
    uint claimedAmt3 = esToken.claim(address(this));
    assertEq(claimedAmt3, 300 ether, "Claimed amount should be 50");
    assertEq(esToken.balanceOf(address(this)), 0, "Balance should be 250");
    assertEq(ANYONE.balanceOf(address(this)), 700 ether, "ANYONE balance should be reduced");

    vm.warp(block.timestamp + 60 days);
    uint claimedAmt4 = esToken.claim(address(this));
    assertEq(claimedAmt4, 200 ether, "Claimed amount should be 50");
    assertEq(esToken.balanceOf(address(this)), 0, "Balance should be 250");
    assertEq(ANYONE.balanceOf(address(this)), 900 ether, "ANYONE balance should be reduced");

    vm.warp(block.timestamp + 60 days);
    uint claimedAmt5 = esToken.claim(address(this));
    assertEq(claimedAmt5, 100 ether, "Claimed amount should be 50");
    assertEq(esToken.balanceOf(address(this)), 0, "Balance should be 250");
    assertEq(ANYONE.balanceOf(address(this)), 1000 ether, "ANYONE balance should be reduced");
  }

  function testDeposit() public {
    uint amt = 100 ether;
    esToken.deposit(address(this), amt);
    uint balance = esToken.balanceOf(address(this));
    assertEq(balance, amt, "Balance should be equal to the deposited amount");
    assertEq(ANYONE.balanceOf(address(this)), 900 ether, "ANYONE balance should be reduced");
  }

  function testTransfer() public {
    vm.expectRevert(EsToken.NoTransfer.selector);
    esToken.transfer(address(this), 10 ether);
  }

  function testTransferFrom() public {
    vm.expectRevert(EsToken.NoTransferFrom.selector);
    esToken.transferFrom(address(this), address(0), 10 ether);
  }
}
