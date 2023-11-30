// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {TToken} from "../src/token.sol";

contract TTokenTest is Test {
  TToken public tToken;

  function setUp() public {
    tToken = new TToken(address(0), "Test Token", "TST");
  }

  // Test the decimals function
  function testDecimals() public {
    uint8 expected = 18;
    assertEq(tToken.decimals(), expected, "Decimals must be 18");
  }

  // Test the whitelist function
  function testWhitelist() public {
    tToken.setWhitelist(address(this), true);
    bool isWhitelisted = tToken.whitelist(address(this));
    assertEq(isWhitelisted, true, "Address should be whitelisted");
  }

  // Test the chainIdToOutboundCap function
  function testChainIdToOutboundCap() public {
    uint expectedCap = 1000;
    tToken.setOutboundCap(1, expectedCap);
    uint cap = tToken.chainIdToOutboundCap(1);
    assertEq(cap, expectedCap, "Outbound cap for chainId 1 should be 1000");
  }

  // Test the chainIdToInboundCap function
  function testChainIdToInboundCap() public {
    uint expectedCap = 1000;
    tToken.setInboundCap(1, expectedCap);
    uint cap = tToken.chainIdToInboundCap(1);
    assertEq(cap, expectedCap, "Inbound cap for chainId 1 should be 1000");
  }
}
