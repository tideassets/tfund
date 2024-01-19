// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {Vault, OracleLike, CoreLike, Auth, IERC20} from "src/vault.sol";
import {TToken, ERC20} from "../src/token.sol";

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
  function buyExactIn(bytes32 ass, address to, uint amt, uint minOut) external returns (uint);
  function buyExactOut(bytes32 ass, address to, uint maxIn, uint out) external returns (uint);
  function sellExactIn(bytes32 ass, address to, uint amt, uint minOut) external returns (uint);
  function sellExactOut(bytes32 ass, address to, uint maxIn, uint out) external returns (uint);
}

contract User is Auth {
  function buyTDTExactIn(IVault val, bytes32 ass, uint amt, uint minOut) public returns (uint) {
    return val.buyExactIn(ass, address(this), amt, minOut);
  }

  function buyTDTExactOut(IVault val, bytes32 ass, uint amt, uint minOut) public returns (uint) {
    return val.buyExactOut(ass, address(this), amt, minOut);
  }

  function sellTDTExactIn(IVault val, bytes32 ass, uint amt, uint minOut) public returns (uint) {
    return val.sellExactIn(ass, address(this), amt, minOut);
  }

  function sellTDTExactOut(IVault val, bytes32 ass, uint maxIn, uint out) public returns (uint) {
    return val.sellExactOut(ass, address(this), maxIn, out);
  }

  function approve(IERC20 token, address user, uint amt) external auth {
    token.approve(user, amt);
  }
}

contract XToken is ERC20, Auth {
  constructor(string memory name_) ERC20(name_, "xToken") {}

  function mint(address user, uint amt) external auth {
    _mint(user, amt);
  }

  // function burn(address user, uint amt) external auth {
  //   _burn(user, amt);
  // }
}

contract VaultTest is Test {
  Vault public val;
  IERC20 TDT;
  IERC20 TCAv1;
  IERC20 TCAv2;
  IERC20 TTL;
  IERC20 TTS;
  IERC20 TTP;
  IERC20 tsUSD;

  IERC20 T1;
  IERC20 T2;

  User u1;
  User u2;

  uint constant ONE = 1e18;

  function setUp() public {
    TToken tdt = new TToken(address(0x1234), "TDT token", "TDT");
    TDT = IERC20(address(tdt));
    val = new Vault();
    val.initialize(address(TDT));
    MockOracle o = new MockOracle();
    val.file("Oracle", address(o));
    o.setLastAnswer(1 ether);

    tdt.rely(address(val));

    u1 = new User();
    u2 = new User();

    TToken TCAv1_ = new TToken(address(0x1234), "TCAv1 token", "TCAv1");
    TToken TCAv2_ = new TToken(address(0x1234), "TCAv2 token", "TCAv2");
    TToken tsUSD_ = new TToken(address(0x1234), "tsUSD token", "tsUSD");
    TCAv1 = IERC20(address(TCAv1_));
    TCAv2 = IERC20(address(TCAv2_));
    tsUSD = IERC20(address(tsUSD_));

    TCAv1_.mint(address(this), 1000000 ether);
    TCAv2_.mint(address(this), 1000000 ether);
    tsUSD_.mint(address(this), 1000000 ether);

    XToken T1_ = new XToken("T1");
    XToken T2_ = new XToken("T2");
    T1 = IERC20(address(T1_));
    T2 = IERC20(address(T2_));

    T1_.mint(address(this), 1000000 ether);
    T2_.mint(address(this), 1000000 ether);

    TCAv1.approve(address(val), 1000000 ether);
    TCAv2.approve(address(val), 1000000 ether);
    tsUSD.approve(address(val), 1000000 ether);
    T1.approve(address(val), 1000000 ether);
    T2.approve(address(val), 1000000 ether);

    TCAv1.transfer(address(u1), 10000 ether);
    TCAv2.transfer(address(u1), 10000 ether);
    tsUSD.transfer(address(u1), 10000 ether);
    T1.transfer(address(u1), 10000 ether);
    T2.transfer(address(u1), 10000 ether);

    TCAv1.transfer(address(u2), 10000 ether);
    TCAv2.transfer(address(u2), 10000 ether);
    tsUSD.transfer(address(u2), 10000 ether);
    T1.transfer(address(u2), 10000 ether);
    T2.transfer(address(u2), 10000 ether);

    u1.approve(TCAv1, address(val), 10000 ether);
    u1.approve(TCAv2, address(val), 10000 ether);
    u1.approve(tsUSD, address(val), 10000 ether);
    u1.approve(T1, address(val), 10000 ether);
    u1.approve(T2, address(val), 10000 ether);

    u2.approve(TCAv1, address(val), 10000 ether);
    u2.approve(TCAv2, address(val), 10000 ether);
    u2.approve(tsUSD, address(val), 10000 ether);
    u2.approve(T1, address(val), 10000 ether);
    u2.approve(T2, address(val), 10000 ether);

    MockOracle o1 = new MockOracle();
    MockOracle o2 = new MockOracle();
    MockOracle o3 = new MockOracle();
    MockOracle o4 = new MockOracle();
    MockOracle o5 = new MockOracle();

    o1.setLastAnswer(1.0e18);
    o2.setLastAnswer(1.0e18);
    o3.setLastAnswer(1.0e18);
    o4.setLastAnswer(2.0e18);
    o5.setLastAnswer(5.0e18);

    val.file("TCAv1", "min", 10 * ONE / 100);
    val.file("TCAv1", "max", 40 * ONE / 100);
    val.file("TCAv1", "oracle", address(o1));
    val.file("TCAv1", "gem", address(TCAv1));

    val.file("TCAv2", "min", 20 * ONE / 100);
    val.file("TCAv2", "max", 50 * ONE / 100);
    val.file("TCAv2", "oracle", address(o2));
    val.file("TCAv2", "gem", address(TCAv2));

    val.file("tsUSD", "min", 30 * ONE / 100);
    val.file("tsUSD", "max", 60 * ONE / 100);
    val.file("tsUSD", "oracle", address(o3));
    val.file("tsUSD", "gem", address(tsUSD));

    val.file("T1", "min", 10 * ONE / 100);
    val.file("T1", "max", 20 * ONE / 100);
    val.file("T1", "oracle", address(o4));
    val.file("T1", "gem", address(T1));

    val.file("T2", "min", 20 * ONE / 100);
    val.file("T2", "max", 30 * ONE / 100);
    val.file("T2", "oracle", address(o5));
    val.file("T2", "gem", address(T2));
  }

  function testInitAssets() public {
    uint len = val.assLen();
    bytes32[] memory names = new bytes32[](len);
    uint[] memory amts = new uint[](len);
    for (uint i = 0; i < len; i++) {
      bytes32 name = val.assetList(i);
      amts[i] = 1000 ether;
      names[i] = name;
    }
    val.init(names, amts);

    assertEq(TCAv1.balanceOf(address(val)), 1000 ether);
    assertEq(TCAv2.balanceOf(address(val)), 1000 ether);
    assertEq(tsUSD.balanceOf(address(val)), 1000 ether);
    assertEq(T1.balanceOf(address(val)), 1000 ether);
    assertEq(T2.balanceOf(address(val)), 1000 ether);
    assertEq(TDT.balanceOf(address(this)), 10000 ether);
  }

  function testBuyFee() public {
    testInitAssets();
    uint p = val.assetPersent("T1");
    console2.log("persent", p);
    uint fee = val.buyFee("T1", 1000 ether);
    console2.log("fee", fee);
    assertTrue(fee > 0, "fee should be greater than zero");
  }

  function testBuyExactIn() public {
    testInitAssets();
    assertEq(TDT.balanceOf(address(u1)), 0, "should zero TDT");
    uint fee = val.buyFee("T1", 1000 ether);
    console2.log("fee", fee);
    u1.buyTDTExactIn(IVault(address(val)), "T1", 1000 ether, 0);
    console2.log("TDT", TDT.balanceOf(address(u1)));
    assertTrue(TDT.balanceOf(address(u1)) < 2000 ether, "should less then 2000 TDT");
    assertEq(TDT.balanceOf(address(u1)), (1000 ether - fee) * 2, "should get same TDT");
  }

  function testBuyExactOut() public {
    testInitAssets();
    assertEq(TDT.balanceOf(address(u1)), 0, "should zero TDT");
    uint balance = T1.balanceOf(address(u1));
    assertEq(balance, 10000 ether, "should get 10000 T1");
    uint fee = val.buyFee("T1", 500 ether);
    u1.buyTDTExactOut(IVault(address(val)), "T1", 1000 ether, 1000 ether);
    assertEq(TDT.balanceOf(address(u1)), 1000 ether, "should get 1000 TDT");
    assertEq(T1.balanceOf(address(u1)), balance - 500 ether - fee, "should get same T1");
  }

  function testSellFee() public {
    testInitAssets();
    uint p = val.assetPersent("T1");
    console2.log("persent", p);
    p = val.assetPersent("T1");
    console2.log("persent2", p);
    uint fee = val.sellFee("T1", 900 ether);
    console2.log("fee", fee);
    assertTrue(fee > 0, "fee should be greater than zero");
  }

  function testSellExactIn() public {
    testInitAssets();
    testBuyExactIn();

    uint tdt_balance = TDT.balanceOf(address(u1));
    uint t1_balance = T1.balanceOf(address(u1));
    uint fee = val.sellFee("T1", 50 ether);
    uint out = u1.sellTDTExactIn(IVault(address(val)), "T1", 100 ether, 0);
    assertEq(tdt_balance - 100 ether, TDT.balanceOf(address(u1)), "should get same TDT");
    assertEq(T1.balanceOf(address(u1)), t1_balance - fee + out, "should get same T1");
  }

  function testSellExactOut() public {
    testInitAssets();
    testBuyExactIn();

    uint tdt_balance = TDT.balanceOf(address(u1));
    uint t1_balance = T1.balanceOf(address(u1));
    uint fee = val.sellFee("T1", 50 ether);
    uint out = u1.sellTDTExactOut(IVault(address(val)), "T1", 200 ether, 100 ether);
    assertEq(tdt_balance - out, TDT.balanceOf(address(u1)), "should get same TDT");
    assertEq(T1.balanceOf(address(u1)), t1_balance - fee + 100 ether, "should get same T1");
  }
}
