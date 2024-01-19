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
  function deposit(address asset, uint amt) external returns (uint);
  function withdraw(address asset, uint amt) external returns (uint);
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

  struct Asset {
    uint min; // min persent
    uint max; // max persent
    uint out; // fund persent
    uint inv; // fund amount
    address gem; // asset address
    address oracle; // price oracle
  }

  bytes32[] public assetList;
  mapping(bytes32 name => uint index) assetIndexes;
  mapping(bytes32 name => Asset) public assets;

  FundLike fund;
  CoreLike public core; // TDT, TCAv1, TCAv2
  OracleLike public coreOracle; // oracle for core
  bool public inited = false;
  uint public excfee; // Fee charged for the part that exceeds the purchase or sale

  uint constant ONE = 1e18;
  uint constant ORACLE_PRECISION = 8;
  uint constant FLOAT_PRECISION = 27;

  // events
  event InitAssets(bytes32[] names, Asset[] assets);
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

  function corePrice() public view returns (uint) {
    if (address(coreOracle) == address(0)) {
      return 1e9; // 1 usd: 10 ** (27 - 18)
    }
    (, int lasstAnswer,,,) = OracleLike(coreOracle).latestRoundData();
    require(lasstAnswer > 0, "Vault/invalid core price");
    return uint(lasstAnswer) * 10; // 10 ** (27 - 8 - 18)
  }

  function assetPrice(bytes32 name) public view returns (uint) {
    OracleLike o = OracleLike(assets[name].oracle);
    (, int lasstAnswer,,,) = o.latestRoundData();
    require(lasstAnswer > 0, "Vault/invalid asset price");
    uint dec = IERC20Metadata(assets[name].gem).decimals();
    return uint(lasstAnswer) * (10 ** (19 - dec)); // 10 ** (27 - 8 - dec)
  }

  function assLen() public view returns (uint) {
    return assetList.length;
  }

  function init(bytes32[] calldata names, Asset[] calldata assets_) external auth {
    for (uint i = 0; i < names.length; ++i) {
      assets[names[i]] = assets_[i];
      _file(names[i], false);
    }
    emit InitAssets(names, assets_);
  }

  function _file(bytes32 who, bool rm) internal {
    if (!rm) {
      if (assetIndexes[who] > 0) {
        return;
      }
      assetList.push(who);
      assetIndexes[who] = assetList.length;
    } else {
      require(assetIndexes[who] > 0, "Vault/asset not added");
      bytes32 last = assetList[assetList.length - 1];
      if (who != last) {
        uint i = assetIndexes[who] - 1;
        assetList[i] = last;
        assetIndexes[last] = i + 1;
      }
      assetList.pop();
      delete assetIndexes[who];
      delete assets[who];
    }
  }

  function file(bytes32 who, bytes32 what, uint data) external auth whenNotPaused {
    if (what == "max") {
      assets[who].max = data;
    } else if (what == "min") {
      assets[who].min = data;
    } else if (what == "out") {
      assets[who].max = data;
    } else if (what == "inv") {
      assets[who].max = data;
    } else {
      revert("Vault/file-unrecognized-param");
    }
    emit Filed(who, what, data);
  }

  function file(bytes32 who, bytes32 what, address data) external auth whenNotPaused {
    if (what == "gem") {
      assets[who].gem = data;
    } else if (what == "oracle") {
      assets[who].oracle = data;
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
    Asset memory asset = assets[name];
    IERC20 token = IERC20(asset.gem);
    return token.balanceOf(address(this)) + asset.inv;
  }

  function assetValue(bytes32 name) public view returns (uint) {
    uint balance = assetAmount(name);
    uint value = uint(assetPrice(name)) * balance;
    return value;
  }

  function totalValue() public view returns (uint) {
    uint total = 0;
    uint len = assetList.length;
    for (uint i = 1; i < len; i++) {
      bytes32 name = assetList[i];
      Asset memory asset = assets[name];
      uint bal = IERC20(asset.gem).balanceOf(address(this));
      total += assetPrice(name) * bal;
    }
    if (address(fund) != address(0)) {
      total += uint(fund.price()) * fund.balanceOf(address(this));
    }
    return total;
  }

  function price() public view returns (int) {
    return int(totalValue() * ONE / core.totalSupply());
  }

  function _calcuPersent(bytes32 name, int amt) internal view returns (uint) {
    int total = int(totalValue());
    require(total > 0, "Vault/asset amount error");
    int aval = int(assetValue(name));
    int dval = int(assetPrice(name)) * amt;
    total += dval;
    aval += dval;
    if (aval < 0) {
      aval = 0;
    }
    return uint(aval) / uint(total);
  }

  function assetPersent(bytes32 name) public view returns (uint) {
    return _calcuPersent(name, 0);
  }

  function maxFundDeposit(bytes32 name) public view returns (uint) {
    Asset memory asset = assets[name];
    IERC20 token = IERC20(asset.gem);
    uint total = token.balanceOf(address(this)) + asset.inv;
    return total * ONE / asset.out;
  }

  function fundDeposit(bytes32 name, uint amt) external auth nonReentrant {
    require(address(fund) != address(0), "Vault/fund is zero");
    require(amt <= maxFundDeposit(name), "Vault/invilid deposit amount");
    Asset storage asset = assets[name];
    IERC20 token = IERC20(asset.gem);
    token.forceApprove(address(fund), amt);
    uint d = fund.deposit(asset.gem, amt);
    asset.inv += d;

    emit FundDeposited(name, amt);
  }

  function fundWithdraw(bytes32 name, uint amt) external auth nonReentrant {
    require(address(fund) != address(0), "Vault/fund is zero");
    Asset storage asset = assets[name];
    uint w = fund.withdraw(asset.gem, amt);
    if (w > asset.inv) {
      asset.inv = 0;
    } else {
      asset.inv = 0;
    }

    emit FundWithdrawn(name, amt);
  }

  function buyFee(bytes32 name, uint amt) public view returns (uint) {
    uint p = _calcuPersent(name, int(amt));
    Asset memory asset = assets[name];
    if (p <= asset.max) {
      return 0;
    }
    uint exc = p - asset.max;
    return (exc * amt) / ONE * excfee / ONE;
  }

  function sellFee(bytes32 name, uint amt) public view returns (uint) {
    uint p = _calcuPersent(name, -int(amt));
    Asset memory asset = assets[name];
    if (p >= asset.min) {
      return 0;
    }
    uint exc = asset.min - p;
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
    Asset memory asset = assets[name];
    require(asset.max > 0, "Vault/asset not in whitelist");

    uint need = out * corePrice() / assetPrice(name);
    require(need > 0, "Vault/out amount is invalid");
    uint fee = buyFee(name, need);
    need += fee;
    require(need <= maxIn, "Vault/amount in not enough");
    IERC20(asset.gem).safeTransferFrom(msg.sender, address(this), need);
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

  // buy tdt, sell amt of asset buy tdt
  function _buyExactIn(bytes32 name, address to, uint amt, bool useFee) internal returns (uint) {
    Asset memory asset = assets[name];
    require(asset.max > 0, "Vault/asset not in whitelist");

    uint fee = 0;
    if (useFee) {
      fee = buyFee(name, amt);
    }

    IERC20(asset.gem).safeTransferFrom(msg.sender, address(this), amt);

    uint max = assetPrice(name) * (amt - fee) / corePrice();
    core.mint(to, max);

    return max;
  }

  function sellExactOut(bytes32 name, address to, uint maxIn, uint out)
    external
    whenNotPaused
    nonReentrant
    returns (uint)
  {
    Asset memory asset = assets[name];
    require(asset.max > 0, "Vault/asset not in whitelist");

    uint fee = sellFee(name, out);
    uint need = assetPrice(name) * (out + fee) / corePrice();
    require(need > 0, "Vault/out amount is invalid");
    require(need <= maxIn, "Vault/amount in is not enough");

    core.burn(msg.sender, need);
    IERC20(asset.gem).safeTransfer(to, out);

    emit Sold(msg.sender, name, to, need, out);
    return need;
  }

  // sell core for asset, amt is tdt amount for sell
  function sellExactIn(bytes32 name, address to, uint amt, uint minOut)
    external
    whenNotPaused
    nonReentrant
    returns (uint)
  {
    Asset memory asset = assets[name];
    require(asset.max > 0, "Vault/asset not in whitelist");

    core.burn(msg.sender, amt);

    uint max = corePrice() * amt / assetPrice(name);

    uint fee = sellFee(name, max);
    max = max - fee;
    require(max >= minOut, "Vault/amount out is too large");

    IERC20 token = IERC20(asset.gem);
    token.safeTransfer(to, max);
    emit Sold(msg.sender, name, to, amt, max);
    return max;
  }
}
