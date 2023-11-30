// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {Vault, OracleLike} from "../src/vault.sol";
import {TToken} from "../src/token.sol";

contract MockOracle is OracleLike {
  int128 lastAnswer;

  constructor() {}

  function setLastAnswer(int128 a) external {
    lastAnswer = a;
  }

  function latestRoundData() external view returns (uint80, int, uint, uint, uint80) {
    return (0, lastAnswer, 0, 0, 0);
  }
}

interface IVault {
  function buy(address ass, address to, uint amt) external returns (uint);
  function sell(address ass, address to, uint amt) external returns (uint);
}

contract User {
  function buyTDT(IVault val, address ass, uint amt) public returns (uint) {
    return val.buy(ass, address(this), amt);
  }

  function sellTDT(IVault val, address ass, uint amt) public returns (uint) {
    return val.sell(ass, address(this), amt);
  }
}

contract VaultTest is Test {
  Vault public val;
  TToken TDT;

  TToken T1;
  TToken T2;

  User u1;
  User u2;

  function setUp() public {
    TDT = new TToken(address(0x1234), "TDT token", "TDT");
    val = new Vault(address(TDT));
    MockOracle o = new MockOracle();
    val.setOracle(address(o));

    u1 = new User();
    u2 = new User();
  }

  function testInitAsswts() public {}
  function testBuyFee() public {}
  function testBuy() public {}
  function testSellFee() public {}
  function testSell() public {}
}
