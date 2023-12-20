// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {VeToken, IERC20} from "../src/vetoken.sol";
import {TToken, Auth} from "../src/token.sol";

interface NFTLike {
  function transferFrom(address, address, uint) external;
}

contract User is Auth {
  function doDeposit(VeToken ve, uint amount, VeToken.Long long) external auth returns (uint) {
    return ve.deposit(amount, long);
  }

  function doWithdraw(VeToken ve, uint tokenId) external auth {
    ve.withdraw(tokenId);
  }

  function approve(address token, address spender, uint amt) external auth {
    IERC20(token).approve(spender, amt);
  }

  function transferNFT(address nft, address to, uint id) external auth {
    NFTLike(nft).transferFrom(address(this), to, id);
  }
}

contract VeTokenTest is Test {
  VeToken public vt;
  IERC20 TDT;
  User u;

  function onERC721Received(address, address, uint, bytes memory) public pure returns (bytes4) {
    return 0x150b7a02;
  }

  function setUp() public {
    TToken tdt = new TToken(address(0x1234), "TDT token", "TDT");
    TDT = IERC20(address(tdt));
    vt = new VeToken();
    vt.initialize(address(TDT), "TDT veToken", "veTDT");
    u = new User();
    tdt.mint(address(u), 1000 ether);
    u.approve(address(TDT), address(vt), 1000 ether);
  }

  function testDeposit() public {
    u.doDeposit(vt, 100 ether, VeToken.Long.ONEMON);
    uint p = vt.powerOf(1);
    assertEq(
      p, 100 ether * vt.mults(VeToken.Long.ONEMON) / 1e6, "powerOf should be 100 * 1.025 ** 1"
    );

    u.doDeposit(vt, 100 ether, VeToken.Long.SIXMON);
    p = vt.powerOf(2);
    assertEq(
      p, 100 ether * vt.mults(VeToken.Long.SIXMON) / 1e6, "powerOf should be 100 * 1.025 ** 6"
    );

    u.doDeposit(vt, 100 ether, VeToken.Long.ONEYEAR);
    p = vt.powerOf(3);
    assertEq(
      p, 100 ether * vt.mults(VeToken.Long.ONEYEAR) / 1e6, "powerOf should be 100 * 1.025 ** 12"
    );

    u.doDeposit(vt, 100 ether, VeToken.Long.TWOYEAR);
    p = vt.powerOf(4);
    assertEq(
      p, 100 ether * vt.mults(VeToken.Long.TWOYEAR) / 1e6, "powerOf should be 100 * 1.025 ** 24"
    );

    u.doDeposit(vt, 100 ether, VeToken.Long.FOURYEAR);
    p = vt.powerOf(5);
    assertEq(
      p, 100 ether * vt.mults(VeToken.Long.FOURYEAR) / 1e6, "powerOf should be 100 * 1.025 ** 48"
    );
  }

  function testPower() public {
    u.doDeposit(vt, 100 ether, VeToken.Long.ONEMON);
    u.doDeposit(vt, 100 ether, VeToken.Long.SIXMON);
    u.doDeposit(vt, 100 ether, VeToken.Long.ONEYEAR);
    u.doDeposit(vt, 100 ether, VeToken.Long.TWOYEAR);
    u.doDeposit(vt, 100 ether, VeToken.Long.FOURYEAR);

    uint p = vt.powerOf(address(u));
    assertEq(
      p,
      100 ether * vt.mults(VeToken.Long.ONEMON) / 1e6
        + 100 ether * vt.mults(VeToken.Long.SIXMON) / 1e6
        + 100 ether * vt.mults(VeToken.Long.ONEYEAR) / 1e6
        + 100 ether * vt.mults(VeToken.Long.TWOYEAR) / 1e6
        + 100 ether * vt.mults(VeToken.Long.FOURYEAR) / 1e6,
      "powerOf should be 100 * 1.025 ** 1 + 100 * 1.025 ** 6 + 100 * 1.025 ** 12 + 100 * 1.025 ** 24 + 100 * 1.025 ** 48"
    );
  }

  function testWithdraw() public {
    u.doDeposit(vt, 100 ether, VeToken.Long.ONEMON);
    u.doDeposit(vt, 100 ether, VeToken.Long.SIXMON);
    u.doDeposit(vt, 100 ether, VeToken.Long.ONEYEAR);
    u.doDeposit(vt, 100 ether, VeToken.Long.TWOYEAR);
    u.doDeposit(vt, 100 ether, VeToken.Long.FOURYEAR);

    uint p = vt.powerOf(address(u));
    console2.log("powerOf", p);
    assertEq(
      p,
      100 ether * vt.mults(VeToken.Long.ONEMON) / 1e6
        + 100 ether * vt.mults(VeToken.Long.SIXMON) / 1e6
        + 100 ether * vt.mults(VeToken.Long.ONEYEAR) / 1e6
        + 100 ether * vt.mults(VeToken.Long.TWOYEAR) / 1e6
        + 100 ether * vt.mults(VeToken.Long.FOURYEAR) / 1e6,
      "powerOf should be 100 * 1.025 ** 1 + 100 * 1.025 ** 6 + 100 * 1.025 ** 12 + 100 * 1.025 ** 24 + 100 * 1.025 ** 48"
    );

    vm.warp(block.timestamp + 30 days);
    u.doWithdraw(vt, 1);
    p = vt.powerOf(address(u));
    assertEq(
      p,
      100 ether * vt.mults(VeToken.Long.SIXMON) / 1e6
        + 100 ether * vt.mults(VeToken.Long.ONEYEAR) / 1e6
        + 100 ether * vt.mults(VeToken.Long.TWOYEAR) / 1e6
        + 100 ether * vt.mults(VeToken.Long.FOURYEAR) / 1e6,
      "powerOf should be 100 * 1.025 ** 6 + 100 * 1.025 ** 12 + 100 * 1.025 ** 24 + 100 * 1.025 ** 48"
    );

    vm.warp(block.timestamp + 180 days);
    u.doWithdraw(vt, 2);
    p = vt.powerOf(address(u));
    assertEq(
      p,
      100 ether * vt.mults(VeToken.Long.ONEYEAR) / 1e6
        + 100 ether * vt.mults(VeToken.Long.TWOYEAR) / 1e6
        + 100 ether * vt.mults(VeToken.Long.FOURYEAR) / 1e6,
      "powerOf should be 100 * 1.025 ** 12 + 100"
    );

    vm.warp(block.timestamp + 365 days);
    u.doWithdraw(vt, 3);
    p = vt.powerOf(address(u));
    assertEq(
      p,
      100 ether * vt.mults(VeToken.Long.TWOYEAR) / 1e6
        + 100 ether * vt.mults(VeToken.Long.FOURYEAR) / 1e6,
      "powerOf should be 100 * 1.025 ** 24 + 100 * 1.025 ** 48"
    );

    vm.warp(block.timestamp + 365 days);
    u.doWithdraw(vt, 4);
    p = vt.powerOf(address(u));
    assertEq(
      p, 100 ether * vt.mults(VeToken.Long.FOURYEAR) / 1e6, "powerOf should be 100 * 1.025 ** 48"
    );

    vm.warp(block.timestamp + 365 days * 4);
    u.doWithdraw(vt, 5);
    p = vt.powerOf(address(u));
    assertEq(p, 0, "powerOf should be 0");

    assertEq(TDT.balanceOf(address(u)), 1000 ether, "TDT should be 1000");
    assertEq(TDT.balanceOf(address(vt)), 0, "TDT should be 0");
    assertEq(vt.balanceOf(address(u)), 0, "veTDT should be 0");
  }

  function testTransferFrom() public {
    u.doDeposit(vt, 100 ether, VeToken.Long.ONEMON);
    u.doDeposit(vt, 100 ether, VeToken.Long.SIXMON);
    u.doDeposit(vt, 100 ether, VeToken.Long.ONEYEAR);
    u.doDeposit(vt, 100 ether, VeToken.Long.TWOYEAR);
    u.doDeposit(vt, 100 ether, VeToken.Long.FOURYEAR);

    uint p = vt.powerOf(address(u));
    assertEq(
      p,
      100 ether * vt.mults(VeToken.Long.ONEMON) / 1e6
        + 100 ether * vt.mults(VeToken.Long.SIXMON) / 1e6
        + 100 ether * vt.mults(VeToken.Long.ONEYEAR) / 1e6
        + 100 ether * vt.mults(VeToken.Long.TWOYEAR) / 1e6
        + 100 ether * vt.mults(VeToken.Long.FOURYEAR) / 1e6,
      "powerOf should be 100 * 1.025 ** 1 + 100 * 1.025 ** 6 + 100 * 1.025 ** 12 + 100 * 1.025 ** 24 + 100 * 1.025 ** 48"
    );

    u.transferNFT(address(vt), address(this), 1);
    p = vt.powerOf(address(this));
    assertEq(p, 100 ether * vt.mults(VeToken.Long.ONEMON) / 1e6, "powerOf should be 100 * 1.025 ");

    u.transferNFT(address(vt), address(this), 2);
    p = vt.powerOf(address(this));
    assertEq(
      p,
      100 ether * vt.mults(VeToken.Long.ONEMON) / 1e6
        + 100 ether * vt.mults(VeToken.Long.SIXMON) / 1e6,
      "powerOf should be 100 * 1.025 ** 1 + 100 * 1.025 ** 6 + 100 * 1.025 ** 12"
    );

    u.transferNFT(address(vt), address(this), 3);
    p = vt.powerOf(address(this));
    assertEq(
      p,
      100 ether * vt.mults(VeToken.Long.ONEMON) / 1e6
        + 100 ether * vt.mults(VeToken.Long.SIXMON) / 1e6
        + 100 ether * vt.mults(VeToken.Long.ONEYEAR) / 1e6,
      "powerOf should be 100 * 1.025 ** 1 + 100 * 1.025 ** 6 + 100 * 1.025 ** 12"
    );

    u.transferNFT(address(vt), address(this), 4);
    p = vt.powerOf(address(this));
    assertEq(
      p,
      100 ether * vt.mults(VeToken.Long.ONEMON) / 1e6
        + 100 ether * vt.mults(VeToken.Long.SIXMON) / 1e6
        + 100 ether * vt.mults(VeToken.Long.ONEYEAR) / 1e6
        + 100 ether * vt.mults(VeToken.Long.TWOYEAR) / 1e6,
      "powerOf should be 100 * 1.025 ** 1 + 100 * 1.025 ** 6 + 100 * 1.025 ** 12 + 100 * 1.025 ** 24"
    );

    u.transferNFT(address(vt), address(this), 5);
    p = vt.powerOf(address(this));
    assertEq(
      p,
      100 ether * vt.mults(VeToken.Long.ONEMON) / 1e6
        + 100 ether * vt.mults(VeToken.Long.SIXMON) / 1e6
        + 100 ether * vt.mults(VeToken.Long.ONEYEAR) / 1e6
        + 100 ether * vt.mults(VeToken.Long.TWOYEAR) / 1e6
        + 100 ether * vt.mults(VeToken.Long.FOURYEAR) / 1e6,
      "powerOf should be 100 * 1.025 ** 1 + 100 * 1.025 ** 6 + 100 * 1.025 ** 12 + 100 * 1.025 ** 24 + 100 * 1.025 ** 48"
    );
  }
}
