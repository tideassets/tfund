// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {RewarderStake, RewarderPerSecond} from "../src/reward.sol";

contract RewarderTest is Test {
  RewarderPerSecond public psR;
  RewarderStake public stR;

  function setUp() public {}
}
