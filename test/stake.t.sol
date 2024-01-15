// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {Stakex, RewarderLike} from "../src/stake.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IOU20} from "../src/iou.sol";

contract MEsToken is ERC20 {
  constructor() ERC20("EsToken", "EST") {}

  function deposit(address usr, uint amt) external {
    _mint(usr, amt);
  }
}

contract MRewarder is RewarderLike {
  function updateBefore(address usr, int amt) external override {}
  function updateAfter(address usr, int amt) external override {}
}

contract StakexTest is Test {
  Stakex public st;

  function setUp() public {
    MEsToken asset = new MEsToken();
    st = new Stakex();
    st.initialize(address(asset));
  }

  function testAddRewarder() public {
    MRewarder r = new MRewarder();
    st.file("TDT-A", "add", address(r));
    assertTrue(st.rs("TDT-A") == address(r));
    assertTrue(st.ra(0) == "TDT-A");
    assertTrue(st.ri("TDT-A") == 1);
  }

  function testRmRewarder() public {
    MRewarder r = new MRewarder();
    st.file("TDT-A", "add", address(r));
    st.file("TDT-A", "rm", address(0));
    assertTrue(st.rewarders().length == 0);
    assertTrue(st.ri("TDT-A") == 0);
    assertTrue(st.rs("TDT-A") == address(0));

    st.file("TDT-A", "add", address(r));
    st.file("TDT-B", "add", address(new MRewarder()));
    st.file("TDT-C", "add", address(new MRewarder()));
    assertEq(st.rewarders().length, 3);
    st.file("TDT-B", "rm", address(0));
    assertEq(st.rewarders().length, 2);
    assertTrue(st.ra(0) == "TDT-A");
    assertTrue(st.ra(1) == "TDT-C");
    assertTrue(st.ri("TDT-A") == 1);
    assertTrue(st.ri("TDT-C") == 2);
    st.file("TDT-A", "rm", address(0));
    assertEq(st.rewarders().length, 1);
    assertTrue(st.ra(0) == "TDT-C");
    assertTrue(st.ri("TDT-C") == 1);
    st.file("TDT-C", "rm", address(0));
    assertEq(st.rewarders().length, 0);
  }
}
