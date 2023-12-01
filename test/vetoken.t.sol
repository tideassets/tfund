// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {VeToken, IERC20} from "../src/vetoken.sol";
import {TToken, Auth} from "../src/token.sol";

contract User is Auth {
  function doDeposit(VeToken ve, uint amount, uint long) external auth returns (uint) {
    return ve.deposit(amount, VeToken.Long(long));
  }

  function doWithdraw(VeToken ve, uint tokenId) external auth {
    ve.withdraw(tokenId);
  }

  function approve(address token, address spender, uint amt) external auth {
    IERC20(token).approve(spender, amt);
  }
}

contract VeTokenTest is Test {
  VeToken public vt;
  IERC20 TDT;
  User u;

  function setUp() public {
    TToken tdt = new TToken(address(0x1234), "TDT token", "TDT");
    TDT = IERC20(address(tdt));
    vt = new VeToken(address(TDT), "TDT veToken", "veTDT");
    u = new User();
    tdt.mint(address(u), 1000 ether);
    u.approve(address(TDT), address(vt), 1000 ether);
  }

  function testPower() public {}
  function testPower2() public {}
  function testDeposit() public {}
  function testWithdraw() public {}
}
