// SPDX-License-Identifier: MIT
// Copyright (C) 2023
// val.sol : core vault
//

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

interface InvLike {
  function deposit(
    address[] memory asss_,
    uint[] memory amts_,
    address reward
  ) external;

  function withdraw(address[] memory asss_, uint[] memory amts_) external;

  function claim() external;

  function depositedAmount(
    address usr,
    address ass
  ) external view returns (uint);

  function rewards(address usr, address ass) external view returns (uint);

  function rewardTokens(address usr) external view returns (address[] memory);
}

interface PriceProviderLike {
  function price(address ass1, address ass2) external view returns (uint); // ass1/ass2

  function price(address ass) external view returns (uint); // in usd
}

interface ERC20Like is IERC20 {
  function mint(address account, uint amt) external;

  function burn(address account, uint amt) external;
}

contract Val is ReentrancyGuard, Pausable {
  using SafeERC20 for IERC20;
  using SafeERC20 for ERC20Like;
  using SafeMath for uint;

  // ---- Auth ----
  mapping(address => uint) wards;

  modifier auth() {
    require(wards[msg.sender] == 1, "Val/not-authorized");
    _;
  }

  function rely(address usr) external auth whenNotPaused {
    wards[usr] = 1;
    emit Rely(usr);
  }

  function deny(address usr) external auth whenNotPaused {
    wards[usr] = 0;
    emit Deny(usr);
  }

  struct Ass {
    uint min; // min persent
    uint max; // max persent
    uint pos;
  }

  struct Inv {
    uint max;
    uint amt;
    uint pos;
  }

  mapping(address => Ass) public asss;
  mapping(address => mapping(address => Inv)) public invs; // adv_addr => ass_addk => Inv
  address[] invetors;
  address[] tokens;

  PriceProviderLike public priceProvider;
  ERC20Like public core; // TDT, TCAv1, TCAV2
  bool public inited = false;

  uint constant ONE = 1.00E18;
  uint constant PENSENT_DIVISOR = 10000;

  event Rely(address indexed usr);
  event Deny(address indexed usr);

  constructor(address core_, address pp) {
    core = ERC20Like(core_);
    priceProvider = PriceProviderLike(pp);
    wards[msg.sender] = 1;
    tokens.push(address(0)); // index 0 is 0
  }

  function pause() external auth {
    _pause();
  }

  function unpause() external auth {
    _unpause();
  }

  function setAsset(
    address ass,
    uint min,
    uint max
  ) external auth whenNotPaused {
    require(max > 0, "Vat/max persent error");

    Ass storage a = asss[ass];
    if (a.pos == 0) {
      tokens.push(ass);
    }
    a.min = min;
    a.max = max;
    a.pos = tokens.length - 1;
  }

  function removeAsset(address ass) external auth whenNotPaused {
    uint pos = asss[ass].pos;
    require(pos > 0, "Val/asset not in whitelist");
    address a = tokens[tokens.length - 1];
    tokens[pos] = a;
    tokens.pop();
    asss[a].pos = pos;
    delete asss[ass];
  }

  // price provider
  function setPriceProvider(address pp) external auth whenNotPaused {
    require(pp != address(0), "Vat/price provider not valid");
    priceProvider = PriceProviderLike(pp);
  }

  function setInv(
    address ass,
    address inv,
    uint max
  ) external auth whenNotPaused {
    require(asss[ass].pos > 0, "Val/asset not in whitelist");
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
    uint max = balance.mul(maxPersent).div(PENSENT_DIVISOR);

    InvLike invetor = InvLike(inv);
    uint damt = invetor.depositedAmount(address(this), ass);
    return max.sub(damt);
  }

  function assetAmount(address ass) public view returns (uint) {
    IERC20 token = IERC20(ass);
    uint balance = token.balanceOf(address(this));
    for (uint i = 0; i < invetors.length; i++) {
      InvLike invetor = InvLike(invetors[i]);
      uint damt = invetor.depositedAmount(address(this), ass);
      uint rewards = invetor.rewards(address(this), ass);
      balance = balance.add(rewards).add(damt);
    }
    return balance;
  }

  function assetValue(address ass) public view returns (uint) {
    uint balance = assetAmount(ass);
    uint value = priceProvider.price(ass).mul(balance).div(ONE);
    return value;
  }

  function totalValue() public view returns (uint) {
    uint total = 0;
    for (uint i = 1; i < tokens.length; i++) {
      // i == 0 is address(0)
      total += assetValue(tokens[i]);
    }
    return total;
  }

  function _assetPersent(address ass, int256 amt) internal view returns (uint) {
    int256 total = int256(totalValue());
    int256 assVal = int256(assetValue(ass));
    int256 dval = (int256(priceProvider.price(ass)) * amt) / int256(ONE);
    total += dval;
    assVal += dval;
    require(assVal > 0, "Val/asset is 0");
    return PENSENT_DIVISOR.mul(uint(assVal)).div(uint(total));
  }

  function assetPersent(address ass) public view returns (uint) {
    return _assetPersent(ass, 0);
  }

  function deposit(
    address[] memory asss_,
    uint[] memory amts_,
    address inv_
  ) external auth nonReentrant whenNotPaused {
    for (uint i = 0; i < asss_.length; i++) {
      uint amt = amts_[i];
      uint max = invetMax(asss_[i], inv_);
      require(amt <= max, "Val/amt error");
      IERC20 ass = IERC20(asss_[i]);
      ass.safeApprove(inv_, amt);
    }
    InvLike(inv_).deposit(asss_, amts_, address(this));
  }

  function withdraw(
    address[] memory asss_,
    uint[] memory amts_,
    address inv_
  ) external auth nonReentrant {
    InvLike(inv_).withdraw(asss_, amts_);
  }

  function buyFee(address ass, uint amt) public view returns (uint) {
    uint p = _assetPersent(ass, int256(amt));
    if (p <= asss[ass].max) {
      return 0;
    }
    uint exc = p - asss[ass].max;
    return exc.mul(amt).div(PENSENT_DIVISOR).div(10);
  }

  function sellFee(address ass, uint amt) public view returns (uint) {
    uint p = _assetPersent(ass, -int256(amt));
    if (p >= asss[ass].min) {
      return 0;
    }
    uint exc = asss[ass].min - p;
    return exc.mul(amt).div(PENSENT_DIVISOR).div(10);
  }

  // no buy fee
  function initAssets(
    address[] memory asss_,
    uint[] memory amts_
  ) external auth {
    if (inited) {
      // exec once
      return;
    }
    inited = true;
    for (uint i = 0; i < asss_.length; i++) {
      _buy(asss_[i], msg.sender, amts_[i], false);
    }
  }

  function buy(address ass, address to, uint amt) external returns (uint) {
    return _buy(ass, to, amt, true);
  }

  // buy tdt, sell amt of ass buy tdt
  function _buy(
    address ass,
    address to,
    uint amt,
    bool useFee
  ) internal nonReentrant whenNotPaused returns (uint) {
    require(asss[ass].pos > 0, "Vat/asset not in whitelist");

    IERC20 token = IERC20(ass);
    token.safeTransferFrom(msg.sender, address(this), amt);

    uint fee = 0;
    if (useFee) {
      fee = buyFee(ass, amt);
    }
    uint price = priceProvider.price(address(core), ass); // tdt/ass
    uint max = price.mul(amt.sub(fee));

    core.mint(to, max);
    return max;
  }

  // sell core for ass, amt is tdt amount for sell
  function sell(
    address ass,
    address to,
    uint amt
  ) external nonReentrant whenNotPaused returns (uint) {
    require(asss[ass].pos > 0, "Vat/asset not in whitelist");

    core.burn(msg.sender, amt);

    uint price = priceProvider.price(ass, address(core)); // ass/tdt
    uint max = price.mul(amt);
    uint fee = sellFee(ass, max);
    max = max.sub(fee);

    IERC20 token = IERC20(ass);
    token.safeTransfer(to, max);
    return max;
  }
}
