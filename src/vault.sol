// SPDX-License-Identifier: MIT
// Copyright (C) 2023
// vault.sol : core vault
//
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Auth} from "./auth.sol";

interface InvLike {
  function deposit(address[] memory asss_, uint[] memory amts_, address reward) external;
  function withdraw(address[] memory asss_, uint[] memory amts_) external;
  function claim() external;
  function depositedAmount(address usr, address ass) external view returns (uint);
  function rewards(address usr, address ass) external view returns (uint);
  function rewardTokens(address usr) external view returns (address[] memory);
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

contract Vault is Auth {
  using SafeERC20 for IERC20;

  struct Ass {
    uint min; // min persent
    uint max; // max persent
    address oracle; // price oracle
  }

  struct Inv {
    uint max;
    uint amt;
    uint pos;
  }

  mapping(address => Ass) public asss;
  mapping(address => mapping(address => Inv)) public invs; // adv_addr => ass_addk => Inv
  address[] public invetors;
  address[] public tokens;

  TTokenLike public core; // TDT, TCAv1, TCAv2
  OracleLike public coreOracle; // oracle for core
  bool public inited = false;

  uint constant ONE = 1.0e18;
  uint constant PENSENT_DIVISOR = 10000;

  constructor(address core_) {
    core = TTokenLike(core_);
  }

  function corePrice() public view returns (int) {
    if (address(coreOracle) == address(0)) {
      return int(ONE);
    }
    (, int lasstAnswer,,,) = OracleLike(coreOracle).latestRoundData();
    return lasstAnswer;
  }

  function tokensLen() public view returns (uint) {
    return tokens.length;
  }

  function invsLen() public view returns (uint) {
    return invetors.length;
  }

  function setAsset(address ass, uint min, uint max, address oracle) external auth {
    require(max > 0, "Vat/max persent error");
    require(asss[ass].max == 0, "Vat/already added");

    Ass storage a = asss[ass];
    a.min = min;
    a.max = max;
    a.oracle = oracle;
    tokens.push(ass);
  }

  function removeAsset(address ass) external auth {
    require(asss[ass].max > 0, "Val/asset not added");
    delete asss[ass];
  }

  function setOracle(address ass, address oracle) external auth {
    require(asss[ass].max > 0, "Val/asset not added");
    require(address(0) != oracle, "Val/oracle address is zero");
    asss[ass].oracle = oracle;
  }

  function setOracle(address coreOracle_) external auth {
    require(address(0) != coreOracle_, "Val/oracle address is zero");
    coreOracle = OracleLike(coreOracle_);
  }

  function setInv(address ass, address inv, uint max) external auth {
    require(asss[ass].max > 0, "Val/asset not added");
    invs[inv][ass].max = max;

    bool e = false;
    for (uint i = 0; i < invetors.length; i++) {
      if (inv == invetors[i]) {
        e = true;
        break;
      }
    }
    if (!e) {
      invetors.push(inv);
    }
  }

  function invetMax(address ass, address inv) public view returns (uint) {
    uint balance = assetAmount(ass);
    uint maxPersent = invs[inv][ass].max;
    uint max = (balance * maxPersent) / PENSENT_DIVISOR;

    InvLike invetor = InvLike(inv);
    uint damt = invetor.depositedAmount(address(this), ass);
    return max - damt;
  }

  function assetAmount(address ass) public view returns (uint) {
    IERC20 token = IERC20(ass);
    uint balance = token.balanceOf(address(this));
    for (uint i = 0; i < invetors.length; i++) {
      InvLike invetor = InvLike(invetors[i]);
      uint damt = invetor.depositedAmount(address(this), ass);
      uint rewards = invetor.rewards(address(this), ass);
      balance = balance + rewards + damt;
    }
    return balance;
  }

  function assetValue(address ass) public view returns (uint) {
    uint balance = assetAmount(ass);
    OracleLike o = OracleLike(asss[ass].oracle);
    (, int lastAnswer,,,) = o.latestRoundData();
    uint value = uint(lastAnswer) * balance / ONE;
    return value;
  }

  function totalValue() public view returns (uint) {
    uint total = 0;
    for (uint i = 1; i < tokens.length; i++) {
      total += assetValue(tokens[i]);
    }
    return total;
  }

  function _assetPersent(address ass, int amt) internal view returns (uint) {
    int total = int(totalValue());
    int assVal = int(assetValue(ass));
    OracleLike o = OracleLike(asss[ass].oracle);
    (, int lastAnswer,,,) = o.latestRoundData();
    int dval = (lastAnswer * amt) / int(ONE);
    total += dval;
    require(total > 0, "Val/ass amount error");
    assVal += dval;
    if (assVal < 0) {
      assVal = 0;
    }
    return (PENSENT_DIVISOR * uint(assVal)) / uint(total);
  }

  function assetPersent(address ass) public view returns (uint) {
    return _assetPersent(ass, 0);
  }

  function deposit(address[] calldata asss_, uint[] calldata amts_, address inv_) external auth {
    for (uint i = 0; i < asss_.length; i++) {
      uint amt = amts_[i];
      uint max = invetMax(asss_[i], inv_);
      require(amt <= max, "Val/amt error");
      IERC20 ass = IERC20(asss_[i]);
      ass.approve(inv_, amt);
    }
    InvLike(inv_).deposit(asss_, amts_, address(this));
  }

  function withdraw(address[] memory asss_, uint[] memory amts_, address inv_) external auth {
    InvLike(inv_).withdraw(asss_, amts_);
  }

  function buyFee(address ass, uint amt) public view returns (uint) {
    uint p = _assetPersent(ass, int(amt));
    if (p <= asss[ass].max) {
      return 0;
    }
    uint exc = p - asss[ass].max;
    return (exc * amt) / PENSENT_DIVISOR / 10;
  }

  function sellFee(address ass, uint amt) public view returns (uint) {
    uint p = _assetPersent(ass, -int(amt));
    if (p >= asss[ass].min) {
      return 0;
    }
    uint exc = asss[ass].min - p;
    return (exc * amt) / PENSENT_DIVISOR / 10;
  }

  // no buy fee
  function initAssets(address[] memory asss_, uint[] memory amts_) external auth {
    if (inited) {
      // exec once
      return;
    }
    inited = true;
    for (uint i = 0; i < asss_.length; i++) {
      _buy(asss_[i], msg.sender, amts_[i], false);
    }
  }

  function buyExactOut(address ass, address to, uint maxIn, uint out)
    external
    whenNotPaused
    returns (uint)
  {
    require(asss[ass].max > 0, "Vat/asset not in whitelist");

    (, int assPrice,,,) = OracleLike(asss[ass].oracle).latestRoundData();
    uint need = out * uint(corePrice()) / uint(assPrice);
    uint fee = buyFee(ass, need);
    need += fee;
    require(need <= maxIn, "Vat/amount in not enough");
    IERC20 token = IERC20(ass);
    token.safeTransferFrom(msg.sender, address(this), need);
    core.mint(to, out);
    return need;
  }

  function buyExactIn(address ass, address to, uint amt, uint minOut)
    external
    whenNotPaused
    returns (uint)
  {
    uint max = _buy(ass, to, amt, true);
    require(max >= minOut, "Vat/amount out is too large");
    return max;
  }

  // buy tdt, sell amt of ass buy tdt
  function _buy(address ass, address to, uint amt, bool useFee) internal returns (uint) {
    require(asss[ass].max > 0, "Vat/asset not in whitelist");

    uint fee = 0;
    if (useFee) {
      fee = buyFee(ass, amt);
    }

    (, int assPrice,,,) = OracleLike(asss[ass].oracle).latestRoundData();
    uint max = uint(assPrice) * (amt - fee) / uint(corePrice());

    IERC20 token = IERC20(ass);
    token.safeTransferFrom(msg.sender, address(this), amt);

    core.mint(to, max);
    return max;
  }

  function sellExactOut(address ass, address to, uint maxIn, uint out)
    external
    whenNotPaused
    returns (uint)
  {
    require(asss[ass].max > 0, "Vat/asset not in whitelist");
    (, int assPrice,,,) = OracleLike(asss[ass].oracle).latestRoundData();
    uint fee = sellFee(ass, out);
    uint need = uint(assPrice * int(out + fee) / corePrice());
    require(need <= maxIn, "Val/amount in is not enough");

    core.burn(msg.sender, need);

    IERC20 token = IERC20(ass);
    token.safeTransfer(to, out);
    return need;
  }

  // sell core for ass, amt is tdt amount for sell
  function sellExactIn(address ass, address to, uint amt, uint minOut)
    external
    whenNotPaused
    returns (uint)
  {
    require(asss[ass].max > 0, "Vat/asset not in whitelist");

    core.burn(msg.sender, amt);

    (, int assPrice,,,) = OracleLike(asss[ass].oracle).latestRoundData();
    uint max = uint(corePrice() * int(amt) / assPrice);

    uint fee = sellFee(ass, max);
    max = max - fee;
    require(max >= minOut, "Vat/amount out is too large");

    IERC20 token = IERC20(ass);
    token.safeTransfer(to, max);
    return max;
  }
}
