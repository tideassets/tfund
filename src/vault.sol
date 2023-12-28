// SPDX-License-Identifier: MIT
// Copyright (C) 2023
// vault.sol : core vault
//
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Auth} from "./auth.sol";

interface FundLike {
  function deposit(address ass, uint amt) external;
  function withdraw(address ass, uint amt) external;
  function balanceOf(address usr, address ass) external view returns (uint);
  function profitOf(address usr, address ass) external view returns (uint);
}

interface OracleLike {
  function latestRoundData()
    external
    view
    returns (uint80 roundId, int answer, uint startedAt, uint updatedAt, uint80 answeredInRound);
}

interface TTokenLike {
  function mint(address account, uint amt) external;
  function burn(address account, uint amt) external;
}

contract Vault is Auth, Initializable {
  using SafeERC20 for IERC20;

  struct Ass {
    uint min; // min persent
    uint max; // max persent
    uint out; // out persent
    // uint amt;
    address gem; // asset address
    address oracle; // price oracle
    address fund;
  }

  mapping(bytes32 name => Ass) public asss;
  bytes32[] public assList;
  mapping(bytes32 name => uint index) assIndexs;

  TTokenLike public core; // TDT, TCAv1, TCAv2
  OracleLike public coreOracle; // oracle for core
  bool public inited = false;
  uint public excfee; // Fee charged for the part that exceeds the purchase or sale

  uint constant ONE = 1e18;
  // oracal price precision is 1e8, we use 1e18, so must expend 1e10
  uint constant EXPEND_ORACAL_PRICE_PRECISION = 1e10;

  function initialize(address core_) public initializer {
    core = TTokenLike(core_);
    excfee = ONE / 10;
  }

  function corePrice() public view returns (int) {
    if (address(coreOracle) == address(0)) {
      return int(ONE);
    }
    (, int lasstAnswer,,,) = OracleLike(coreOracle).latestRoundData();
    return lasstAnswer * int(EXPEND_ORACAL_PRICE_PRECISION);
  }

  function assPrice(bytes32 name) public view returns (int) {
    OracleLike o = OracleLike(asss[name].oracle);
    (, int lasstAnswer,,,) = o.latestRoundData();
    return lasstAnswer * int(EXPEND_ORACAL_PRICE_PRECISION);
  }

  function assLen() public view returns (uint) {
    return assList.length;
  }

  function setFee(uint fee_) external auth {
    excfee = fee_;
  }

  function init(
    bytes32 who,
    uint min,
    uint max,
    uint out,
    address gem,
    address oracle,
    address fund
  ) external auth {
    asss[who] = Ass(min, max, out, gem, oracle, fund);
  }

  function _file(bytes32 who, bool rm) internal {
    if (!rm) {
      if (assIndexs[who] > 0) {
        return;
      }
      assList.push(who);
      assIndexs[who] = assList.length;
    } else {
      require(assIndexs[who] > 0, "Vault/asset not added");
      bytes32 last = assList[assList.length - 1];
      if (who != last) {
        uint i = assIndexs[who] - 1;
        assList[i] = last;
        assIndexs[last] = i + 1;
      }
      assList.pop();
      delete assIndexs[who];
      delete asss[who];
    }
  }

  function file(bytes32 who, bytes32 what, uint data) external auth whenNotPaused {
    if (what == "max") {
      asss[who].max = data;
    } else if (what == "min") {
      asss[who].min = data;
    } else if (what == "out") {
      asss[who].out = data;
    } else if (what == "amt") {
      // asss[who].amt = data;
    } else {
      revert("Vault/file-unrecognized-param");
    }
  }

  function file(bytes32 who, bytes32 what, address data) external auth whenNotPaused {
    if (what == "gem") {
      asss[who].gem = data;
    } else if (what == "oracle") {
      asss[who].oracle = data;
    } else if (what == "fund") {
      asss[who].fund = data;
    } else {
      revert("Vault/file-unrecognized-param");
    }
    _file(who, what == "gem" && data == address(0));
  }

  function file(bytes32 what, address data) external auth whenNotPaused {
    require(data != address(0), "Vault/file-address-is-zero");
    if (what == "Oracle") {
      coreOracle = OracleLike(data);
    } else {
      revert("Vault/file-unrecognized-param");
    }
  }

  function file(bytes32 what, uint data) external auth whenNotPaused {
    if (what == "fee") {
      excfee = data;
    } else {
      revert("Vault/file-unrecognized-param");
    }
  }

  function assetOut(bytes32 name) public view returns (uint) {
    Ass memory ass = asss[name];
    if (ass.fund == address(0) || ass.out == 0) {
      return 0;
    }
    FundLike fund = FundLike(ass.fund);
    uint amt = fund.balanceOf(address(this), ass.gem);
    uint fee = fund.profitOf(address(this), ass.gem);
    return amt + fee;
  }

  function assetAmount(bytes32 name) public view returns (uint) {
    Ass memory ass = asss[name];
    IERC20 token = IERC20(ass.gem);
    uint balance = token.balanceOf(address(this));
    balance = balance + assetOut(name);
    return balance;
  }

  function assetValue(bytes32 name) public view returns (uint) {
    uint balance = assetAmount(name);
    uint value = uint(assPrice(name)) * balance / ONE;
    return value;
  }

  function totalValue() public view returns (uint) {
    uint total = 0;
    for (uint i = 1; i < assList.length; i++) {
      total += assetValue(assList[i]);
    }
    return total;
  }

  function _calcuPersent(bytes32 name, int amt) internal view returns (uint) {
    int total = int(totalValue());
    int assVal = int(assetValue(name));
    int dval = (assPrice(name) * amt) / int(ONE);
    total += dval;
    require(total > 0, "Vault/ass amount error");
    assVal += dval;
    if (assVal < 0) {
      assVal = 0;
    }
    return (ONE * uint(assVal)) / uint(total);
  }

  function assetPersent(bytes32 name) public view returns (uint) {
    return _calcuPersent(name, 0);
  }

  function calcuOut(bytes32 name) public view returns (uint) {
    Ass memory ass = asss[name];
    uint amt = assetAmount(name);
    uint out = assetOut(name);
    return amt * ass.out / ONE - out;
  }

  function deposit(bytes32 name, uint amt) external auth {
    Ass memory ass = asss[name];
    uint max = calcuOut(name);
    require(amt <= max, "Vault/amt error");
    IERC20 token = IERC20(ass.gem);
    token.forceApprove(ass.fund, amt);
    FundLike(ass.fund).deposit(ass.gem, amt);
  }

  function withdraw(bytes32 name, uint amt) external auth {
    Ass memory ass = asss[name];
    FundLike(ass.fund).withdraw(ass.gem, amt);
  }

  function buyFee(bytes32 name, uint amt) public view returns (uint) {
    uint p = _calcuPersent(name, int(amt));
    Ass memory ass = asss[name];
    if (p <= ass.max) {
      return 0;
    }
    uint exc = p - ass.max;
    return (exc * amt) / ONE * excfee / ONE;
  }

  function sellFee(bytes32 name, uint amt) public view returns (uint) {
    uint p = _calcuPersent(name, -int(amt));
    Ass memory ass = asss[name];
    if (p >= ass.min) {
      return 0;
    }
    uint exc = ass.min - p;
    return (exc * amt) / ONE * excfee / ONE;
  }

  // no buy fee
  function init(bytes32[] memory names, uint[] memory amts_) external auth {
    if (inited) {
      // exec once
      return;
    }
    inited = true;
    for (uint i = 0; i < names.length; i++) {
      _buy(names[i], msg.sender, amts_[i], false);
    }
  }

  function buyExactOut(bytes32 name, address to, uint maxIn, uint out)
    external
    whenNotPaused
    returns (uint)
  {
    Ass memory ass = asss[name];
    require(ass.max > 0, "Vault/asset not in whitelist");

    uint need = out * uint(corePrice()) / uint(assPrice(name));
    uint fee = buyFee(name, need);
    need += fee;
    require(need <= maxIn, "Vault/amount in not enough");
    IERC20 token = IERC20(ass.gem);
    token.safeTransferFrom(msg.sender, address(this), need);
    core.mint(to, out);
    return need;
  }

  function buyExactIn(bytes32 name, address to, uint amt, uint minOut)
    external
    whenNotPaused
    returns (uint)
  {
    uint max = _buy(name, to, amt, true);
    require(max >= minOut, "Vault/amount out is too large");
    return max;
  }

  // buy tdt, sell amt of ass buy tdt
  function _buy(bytes32 name, address to, uint amt, bool useFee) internal returns (uint) {
    Ass memory ass = asss[name];
    require(ass.max > 0, "Vault/asset not in whitelist");

    uint fee = 0;
    if (useFee) {
      fee = buyFee(name, amt);
    }

    uint max = uint(assPrice(name)) * (amt - fee) / uint(corePrice());

    IERC20 token = IERC20(ass.gem);
    token.safeTransferFrom(msg.sender, address(this), amt);

    core.mint(to, max);
    return max;
  }

  function sellExactOut(bytes32 name, address to, uint maxIn, uint out)
    external
    whenNotPaused
    returns (uint)
  {
    Ass memory ass = asss[name];
    require(ass.max > 0, "Vault/asset not in whitelist");
    uint fee = sellFee(name, out);
    uint need = uint(assPrice(name) * int(out + fee) / corePrice());
    require(need <= maxIn, "Vault/amount in is not enough");

    core.burn(msg.sender, need);

    IERC20 token = IERC20(ass.gem);
    token.safeTransfer(to, out);
    return need;
  }

  // sell core for ass, amt is tdt amount for sell
  function sellExactIn(bytes32 name, address to, uint amt, uint minOut)
    external
    whenNotPaused
    returns (uint)
  {
    Ass memory ass = asss[name];
    require(ass.max > 0, "Vault/asset not in whitelist");

    core.burn(msg.sender, amt);

    uint max = uint(corePrice() * int(amt) / assPrice(name));

    uint fee = sellFee(name, max);
    max = max - fee;
    require(max >= minOut, "Vault/amount out is too large");

    IERC20 token = IERC20(ass.gem);
    token.safeTransfer(to, max);
    return max;
  }
}
