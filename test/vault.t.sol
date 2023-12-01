// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {Vault, OracleLike, TTokenLike, Auth, IERC20} from "../src/vault.sol";
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
  function buyExactIn(address ass, address to, uint amt, uint minOut) external returns (uint);
  function buyExactOut(address ass, address to, uint maxIn, uint out) external returns (uint);
  function sellExactIn(address ass, address to, uint amt, uint minOut) external returns (uint);
  function sellExactOut(address ass, address to, uint maxIn, uint out) external returns (uint);
}

contract User is Auth {
  function buyTDTExactIn(IVault val, address ass, uint amt, uint minOut) public returns (uint) {
    return val.buyExactIn(ass, address(this), amt, minOut);
  }

  function buyTDTExactOut(IVault val, address ass, uint amt, uint minOut) public returns (uint) {
    return val.buyExactOut(ass, address(this), amt, minOut);
  }

  function sellTDTExactIn(IVault val, address ass, uint amt, uint minOut) public returns (uint) {
    return val.sellExactIn(ass, address(this), amt, minOut);
  }

  function sellTDTExactOut(IVault val, address ass, uint maxIn, uint out) public returns (uint) {
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

  function setUp() public {
    TToken tdt = new TToken(address(0x1234), "TDT token", "TDT");
    TDT = IERC20(address(tdt));
    val = new Vault(address(TDT));
    MockOracle o = new MockOracle();
    val.setOracle(address(o));
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

    val.setAsset(address(TCAv1), 1000, 4000, address(o1));
    val.setAsset(address(TCAv2), 2000, 5000, address(o2));
    val.setAsset(address(tsUSD), 3000, 6000, address(o3));
    val.setAsset(address(T1), 1000, 2000, address(o4));
    val.setAsset(address(T2), 2000, 3000, address(o5));
  }

  function testInitAssets() public {
    uint len = val.tokensLen();
    address[] memory tokens = new address[](len);
    uint[] memory amts = new uint[](len);
    for (uint i = 0; i < len; i++) {
      address t = val.tokens(i);
      tokens[i] = t;
      amts[i] = 1000 ether;
    }
    val.initAssets(tokens, amts);

    assertEq(TCAv1.balanceOf(address(val)), 1000 ether);
    assertEq(TCAv2.balanceOf(address(val)), 1000 ether);
    assertEq(tsUSD.balanceOf(address(val)), 1000 ether);
    assertEq(T1.balanceOf(address(val)), 1000 ether);
    assertEq(T2.balanceOf(address(val)), 1000 ether);
    assertEq(TDT.balanceOf(address(this)), 10000 ether);
  }

  function testBuyFee() public {
    testInitAssets();
    uint p = val.assetPersent(address(T1));
    console2.log("persent", p);
    uint fee = val.buyFee(address(T1), 1000 ether);
    console2.log("fee", fee);
    assertTrue(fee > 0, "fee should be greater than zero");
  }

  function testBuyExactIn() public {
    testInitAssets();
    assertEq(TDT.balanceOf(address(u1)), 0, "should zero TDT");
    uint fee = val.buyFee(address(T1), 1000 ether);
    console2.log("fee", fee);
    u1.buyTDTExactIn(IVault(address(val)), address(T1), 1000 ether, 0);
    console2.log("TDT", TDT.balanceOf(address(u1)));
    assertTrue(TDT.balanceOf(address(u1)) < 2000 ether, "should less then 2000 TDT");
    assertEq(TDT.balanceOf(address(u1)), (1000 ether - fee) * 2, "should get same TDT");
  }

  function testBuyExactOut() public {
    testInitAssets();
    assertEq(TDT.balanceOf(address(u1)), 0, "should zero TDT");
    uint balance = T1.balanceOf(address(u1));
    assertEq(balance, 10000 ether, "should get 10000 T1");
    uint fee = val.buyFee(address(T1), 500 ether);
    u1.buyTDTExactOut(IVault(address(val)), address(T1), 1000 ether, 1000 ether);
    assertEq(TDT.balanceOf(address(u1)), 1000 ether, "should get 1000 TDT");
    assertEq(T1.balanceOf(address(u1)), balance - 500 ether - fee, "should get same T1");
  }

  function testSellFee() public {
    testInitAssets();
    uint p = val.assetPersent(address(T1));
    console2.log("persent", p);
    uint fee = val.sellFee(address(T1), 1000 ether);
    console2.log("fee", fee);
    assertTrue(fee > 0, "fee should be greater than zero");
  }

  function testSellExactIn() public {
    testInitAssets();
    testBuyExactIn();

    uint tdt_balance = TDT.balanceOf(address(u1));
    uint t1_balance = T1.balanceOf(address(u1));
    uint fee = val.sellFee(address(T1), 50 ether);
    uint out = u1.sellTDTExactIn(IVault(address(val)), address(T1), 100 ether, 0);
    assertEq(tdt_balance - 100 ether, TDT.balanceOf(address(u1)), "should get same TDT");
    assertEq(T1.balanceOf(address(u1)), t1_balance - fee + out, "should get same T1");
  }

  function testSellExactOut() public {
    testInitAssets();
    testBuyExactIn();

    uint tdt_balance = TDT.balanceOf(address(u1));
    uint t1_balance = T1.balanceOf(address(u1));
    uint fee = val.sellFee(address(T1), 50 ether);
    uint out = u1.sellTDTExactOut(IVault(address(val)), address(T1), 200 ether, 100 ether);
    assertEq(tdt_balance - out, TDT.balanceOf(address(u1)), "should get same TDT");
    assertEq(T1.balanceOf(address(u1)), t1_balance - fee + 100 ether, "should get same T1");
  }
}
