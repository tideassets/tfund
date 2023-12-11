// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {Locker} from "../src/lock.sol";
import {Auth} from "../src/auth.sol";
import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface ILocker {
  function daoUnlock() external;
  function tsaUnlock() external;
  function teamUnlock() external;
  function lpFundUnlock() external;
}

abstract contract MRole is Auth {
  function unlock(address locker) external auth {
    _unlock(locker);
  }

  function _unlock(address locker) internal virtual;
}

contract MTeam is MRole {
  function _unlock(address locker) internal override {
    ILocker(locker).teamUnlock();
  }
}

contract MDao is MRole {
  function _unlock(address locker) internal override {
    ILocker(locker).daoUnlock();
  }
}

contract MTsaDao is MRole {
  function _unlock(address locker) internal override {
    ILocker(locker).tsaUnlock();
  }
}

contract MLpFund is MRole {
  function _unlock(address locker) internal override {
    ILocker(locker).lpFundUnlock();
  }
}

contract MToken is ERC20, Auth {
  constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

  function mint(address user, uint amt) external auth {
    _mint(user, amt);
  }
}

contract LockerTest is Test {
  Locker public locker;
  MRole public team;
  MRole public dao;
  MRole public tsaDao;
  MRole public lpFund;
  MToken public token;

  function setUp() public {
    team = new MTeam();
    dao = new MDao();
    tsaDao = new MTsaDao();
    lpFund = new MLpFund();

    token = new MToken("token", "TKN");
    locker =
      new Locker(address(token), address(dao), address(tsaDao), address(team), address(lpFund));
    token.rely(address(locker));
  }

  function testUnlock() public {
    team.unlock(address(locker));
    assertTrue(IERC20(token).balanceOf(address(team)) == 0, "team balance should be 0");
    dao.unlock(address(locker));
    assertTrue(IERC20(token).balanceOf(address(dao)) > 0, "dao balance should be >  0");
    tsaDao.unlock(address(locker));
    assertTrue(IERC20(token).balanceOf(address(tsaDao)) == 0, "tsadao balance should be 0");
    lpFund.unlock(address(locker));
    assertTrue(IERC20(token).balanceOf(address(lpFund)) == 0, "lpfund balance should be 0");

    assertEq(locker.remains("team"), 1e7 * 1e18, "team remains should be 1e7 * 1e18");
    assertEq(locker.remains("dao"), 8e6 * 1e18, "dao remains should be 8e6 * 1e18");
    assertEq(locker.remains("tsaDao"), 1e7 * 1e18, "tsaDao remains should be 1e7 * 1e18");
    assertEq(locker.remains("lpFund"), 7e7 * 1e18, "lpFund remains should be 7e7 * 1e18");

    uint amt;
    vm.warp(block.timestamp + 7 days);
    lpFund.unlock(address(locker));
    amt = uint(1e18 * 7e7) / 52 / 5;
    assertEq(
      IERC20(token).balanceOf(address(lpFund)), amt, "lpFund balance should be 7e7 * 1e18 / 52 / 5"
    );

    vm.warp(block.timestamp + 30 days);
    lpFund.unlock(address(locker));
    amt = uint(1e18 * 7e7) / 52 / 5 * 5;
    assertEq(
      IERC20(token).balanceOf(address(lpFund)), amt, "lpFund balance should be 7e7 * 1e18 / 52 / 5"
    );

    team.unlock(address(locker));
    assertEq(
      IERC20(token).balanceOf(address(team)),
      0,
      "team balance should be 0 beacuse lock 300 days first"
    );

    uint daoBalance = IERC20(token).balanceOf(address(dao));
    dao.unlock(address(locker));
    amt = uint(1e18 * 8e6) / 80;
    assertEq(
      IERC20(token).balanceOf(address(dao)),
      daoBalance + amt,
      "dao balance should be 8e6 * 1e18 / 80"
    );

    tsaDao.unlock(address(locker));
    amt = uint(1e18 * 1e7) / 50;
    assertEq(
      IERC20(token).balanceOf(address(tsaDao)), amt, "tsaDao balance should be 1e7 * 1e18 / 50"
    );
  }
}
