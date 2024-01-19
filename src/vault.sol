// SPDX-License-Identifier: MIT
// Copyright (C) 2023
// vault.sol : core vault
//
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20, IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Auth} from "./auth.sol";

interface FundLike {
  function deposit(address ass, uint amt) external returns (uint);
  function withdraw(address ass, uint amt) external returns (uint);
  function balanceOf(address) external view returns (uint);
  function price() external view returns (int);
}

interface OracleLike {
  function latestRoundData()
    external
    view
    returns (uint80 roundId, int answer, uint startedAt, uint updatedAt, uint80 answeredInRound);
}

interface CoreLike is IERC20 {
  function mint(address account, uint amt) external;
  function burn(address account, uint amt) external;
}

contract Vault is Auth, Initializable, ReentrancyGuard {
  using SafeERC20 for IERC20;

  struct Ass {
    uint min; // min persent
    uint max; // max persent
    uint out; // fund persent
    uint inv; // fund amount
    address gem; // asset address
    address oracle; // price oracle
  }

  bytes32[] public assList;
  mapping(bytes32 name => uint index) assIndexs;
  mapping(bytes32 name => Ass) public asss;

  FundLike fund;
  CoreLike public core; // TDT, TCAv1, TCAv2
  OracleLike public coreOracle; // oracle for core
  bool public inited = false;
  uint public excfee; // Fee charged for the part that exceeds the purchase or sale

  uint constant ONE = 1e18;
  // oracal price precision is 1e8, we use 1e18, so must expend 1e10
  uint constant EXPAND_ORACLE_PRICE_PRECISION = 1e10;

  // events
  event InitAssets(bytes32[] names, Ass[] assets);
  event InitBuying(bytes32[] names, uint[] amts);
  event Filed(bytes32 indexed who, bytes32 indexed what, uint data);
  event Filed(bytes32 indexed who, bytes32 indexed what, address data);
  event Filed(bytes32 indexed what, address data);
  event Filed(bytes32 indexed what, uint data);
  event FundDeposited(bytes32 indexed name, uint amt);
  event FundWithdrawn(bytes32 indexed name, uint amt);
  event Bought(address indexed u, bytes32 indexed name, address to, uint in_, uint out);
  event Sold(address indexed u, bytes32 indexed name, address to, uint in_, uint out);

  function initialize(address core_) public initializer {
    wards[msg.sender] = 1;
    core = CoreLike(core_);
    excfee = ONE / 10;
  }

  function corePrice() public view returns (int) {
    if (address(coreOracle) == address(0)) {
      return int(ONE);
    }
    (, int lasstAnswer,,,) = OracleLike(coreOracle).latestRoundData();
    return lasstAnswer * int(EXPAND_ORACLE_PRICE_PRECISION);
  }

  function assPrice(bytes32 name) public view returns (int) {
    OracleLike o = OracleLike(asss[name].oracle);
    (, int lasstAnswer,,,) = o.latestRoundData();
    return lasstAnswer * int(EXPAND_ORACLE_PRICE_PRECISION);
  }

  function assLen() public view returns (uint) {
    return assList.length;
  }

  function init(bytes32[] calldata names, Ass[] calldata assets) external auth {
    for (uint i = 0; i < names.length; ++i) {
      asss[names[i]] = assets[i];
      _file(names[i], false);
    }
    emit InitAssets(names, assets);
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
      asss[who].max = data;
    } else if (what == "inv") {
      asss[who].max = data;
    } else {
      revert("Vault/file-unrecognized-param");
    }
    emit Filed(who, what, data);
  }

  function file(bytes32 who, bytes32 what, address data) external auth whenNotPaused {
    if (what == "gem") {
      asss[who].gem = data;
    } else if (what == "oracle") {
      asss[who].oracle = data;
    } else {
      revert("Vault/file-unrecognized-param");
    }
    _file(who, what == "gem" && data == address(0));
    emit Filed(who, what, data);
  }

  function file(bytes32 what, address data) external auth whenNotPaused {
    require(data != address(0), "Vault/file-address-is-zero");
    if (what == "Oracle") {
      coreOracle = OracleLike(data);
    } else if (what == "Fund") {
      fund = FundLike(data);
    } else {
      revert("Vault/file-unrecognized-param");
    }
    emit Filed(what, data);
  }

  function file(bytes32 what, uint data) external auth whenNotPaused {
    if (what == "fee") {
      excfee = data;
    } else {
      revert("Vault/file-unrecognized-param");
    }
    emit Filed(what, data);
  }

  function assetAmount(bytes32 name) public view returns (uint) {
    Ass memory ass = asss[name];
    IERC20 token = IERC20(ass.gem);
    return token.balanceOf(address(this)) + ass.inv;
  }

  function assetValue(bytes32 name) public view returns (uint) {
    uint balance = assetAmount(name);
    uint value = uint(assPrice(name)) * balance;
    return value;
  }

  function totalValue() public view returns (uint) {
    uint total = 0;
    uint len = assList.length;
    for (uint i = 1; i < len; i++) {
      bytes32 name = assList[i];
      Ass memory ass = asss[name];
      uint bal = IERC20(ass.gem).balanceOf(address(this));
      total += uint(assPrice(name)) * bal;
    }
    if (address(fund) != address(0)) {
      total += uint(fund.price()) * fund.balanceOf(address(this));
    }
    return total;
  }

  function price() public view returns (int) {
    return int(totalValue() / core.totalSupply());
  }

  function _calcuPersent(bytes32 name, int amt) internal view returns (uint) {
    int total = int(totalValue());
    require(total > 0, "Vault/ass amount error");
    int assVal = int(assetValue(name));
    int dval = (assPrice(name) * amt);
    total += dval;
    assVal += dval;
    if (assVal < 0) {
      assVal = 0;
    }
    return (ONE * uint(assVal)) / uint(total);
  }

  function assetPersent(bytes32 name) public view returns (uint) {
    return _calcuPersent(name, 0);
  }

  function maxFundDeposit(bytes32 name) public view returns (uint) {
    Ass memory ass = asss[name];
    IERC20 token = IERC20(ass.gem);
    uint total = token.balanceOf(address(this)) + ass.inv;
    return total * ONE / ass.out;
  }

  function fundDeposit(bytes32 name, uint amt) external auth nonReentrant {
    require(address(fund) != address(0), "Vault/fund is zero");
    require(amt <= maxFundDeposit(name), "Vault/invilid deposit amount");
    Ass storage ass = asss[name];
    IERC20 token = IERC20(ass.gem);
    token.forceApprove(address(fund), amt);
    uint d = fund.deposit(ass.gem, amt);
    ass.inv += d;

    emit FundDeposited(name, amt);
  }

  function fundWithdraw(bytes32 name, uint amt) external auth nonReentrant {
    require(address(fund) != address(0), "Vault/fund is zero");
    Ass storage ass = asss[name];
    uint w = fund.withdraw(ass.gem, amt);
    if (w > ass.inv) {
      ass.inv = 0;
    } else {
      ass.inv = 0;
    }

    emit FundWithdrawn(name, amt);
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
      _buyExactIn(names[i], msg.sender, amts_[i], false);
    }

    emit InitBuying(names, amts_);
  }

  function buyExactOut(bytes32 name, address to, uint maxIn, uint out)
    external
    whenNotPaused
    nonReentrant
    returns (uint)
  {
    Ass memory ass = asss[name];
    require(ass.max > 0, "Vault/asset not in whitelist");

    uint dec = 10 ** IERC20Metadata(ass.gem).decimals();
    uint need = out * uint(corePrice()) * dec / uint(assPrice(name)) / ONE;
    require(need > 0, "Vault/out amount is invalid");
    uint fee = buyFee(name, need);
    need += fee;
    require(need <= maxIn, "Vault/amount in not enough");
    IERC20(ass.gem).safeTransferFrom(msg.sender, address(this), need);
    core.mint(to, out);

    emit Bought(msg.sender, name, to, need, out);
    return need;
  }

  function buyExactIn(bytes32 name, address to, uint amt, uint minOut)
    external
    whenNotPaused
    nonReentrant
    returns (uint)
  {
    uint max = _buyExactIn(name, to, amt, true);
    require(max >= minOut, "Vault/amount out is too large");

    emit Bought(msg.sender, name, to, amt, max);
    return max;
  }

  // buy tdt, sell amt of ass buy tdt
  function _buyExactIn(bytes32 name, address to, uint amt, bool useFee) internal returns (uint) {
    Ass memory ass = asss[name];
    require(ass.max > 0, "Vault/asset not in whitelist");

    uint fee = 0;
    if (useFee) {
      fee = buyFee(name, amt);
    }

    IERC20(ass.gem).safeTransferFrom(msg.sender, address(this), amt);

    uint dec = 10 ** IERC20Metadata(ass.gem).decimals();
    uint max = uint(assPrice(name)) * (amt - fee) * ONE / uint(corePrice()) / dec;
    core.mint(to, max);

    return max;
  }

  function sellExactOut(bytes32 name, address to, uint maxIn, uint out)
    external
    whenNotPaused
    nonReentrant
    returns (uint)
  {
    Ass memory ass = asss[name];
    require(ass.max > 0, "Vault/asset not in whitelist");

    uint fee = sellFee(name, out);
    uint dec = 10 ** IERC20Metadata(ass.gem).decimals();
    uint need = uint(assPrice(name) * int(out + fee)) * ONE / uint(corePrice()) / dec;
    require(need > 0, "Vault/out amount is invalid");
    require(need <= maxIn, "Vault/amount in is not enough");

    core.burn(msg.sender, need);
    IERC20(ass.gem).safeTransfer(to, out);

    emit Sold(msg.sender, name, to, need, out);
    return need;
  }

  // sell core for ass, amt is tdt amount for sell
  function sellExactIn(bytes32 name, address to, uint amt, uint minOut)
    external
    whenNotPaused
    nonReentrant
    returns (uint)
  {
    Ass memory ass = asss[name];
    require(ass.max > 0, "Vault/asset not in whitelist");

    core.burn(msg.sender, amt);

    uint dec = 10 ** IERC20Metadata(ass.gem).decimals();
    uint max = uint(corePrice() * int(amt)) * dec / uint(assPrice(name)) / ONE;

    uint fee = sellFee(name, max);
    max = max - fee;
    require(max >= minOut, "Vault/amount out is too large");

    IERC20 token = IERC20(ass.gem);
    token.safeTransfer(to, max);
    emit Sold(msg.sender, name, to, amt, max);
    return max;
  }
}
