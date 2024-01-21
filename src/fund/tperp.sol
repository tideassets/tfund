// SPDX-License-Identifier: MIT
// Copyright (C) 2023
// act.sol: user actions and governance actions
//
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {IERC20, ERC20, IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Auth} from "src/auth.sol";
import {IPerpExRouter, IPerpReader, IPerpMarket, BaseOrderUtils} from "./interface/iperp.sol";
import {PerpCallback} from "./perpcallback.sol";

interface IPricer {
  function assetPrice(address asset) external view returns (uint);
}

contract TPerpRouter is Initializable, Auth, ReentrancyGuard {
  using SafeERC20 for IERC20;

  address perpCallback;
  address perpDataStore;
  address perpDepositVault;
  address perpRouter;
  IPerpExRouter public perpExRouter;
  IPerpReader public perpReader;
  IPricer public pricer;

  struct PerpMarket {
    address market;
    address long;
    address short;
    uint longAmount;
    uint shortAmount;
    uint marketPrice;
    int profit;
  }

  uint public constant PERP_FLOAT_PRECISION = 10 ** 30;
  uint public constant ORACALE_FLOAT_PRECISION = 10 ** 8;
  uint constant FLOAT_PRECISION = 10 ** 27;
  uint constant ONE = 1e18;

  address[] public perpMarketList;
  mapping(address => PerpMarket) public perpMarkets;
  bytes32 public constant MAX_PNL_FACTOR_FOR_TRADERS =
    keccak256(abi.encode("MAX_PNL_FACTOR_FOR_TRADERS"));

  function initialize(
    address perpExRouter_,
    address perpDataStore_,
    address perpReader_,
    address perpDepositVault_,
    address perpRouter_
  ) external initializer {
    wards[msg.sender] = 1;
    perpExRouter = IPerpExRouter(perpExRouter_);
    perpReader = IPerpReader(perpReader_);
    perpDataStore = perpDataStore_;
    perpDepositVault = perpDepositVault_;
    perpRouter = perpRouter_;
    perpCallback = address(new PerpCallback(address(this)));
    wards[perpCallback] = 1;
  }

  function file(bytes32 what, address data) external auth {
    if (what == "perpRouter") {
      perpRouter = data;
    } else if (what == "perpDepositVault") {
      perpDepositVault = data;
    } else if (what == "perpCallback") {
      perpCallback = data;
    } else if (what == "perpDataStore") {
      perpDataStore = data;
    } else if (what == "perpExRouter") {
      perpExRouter = IPerpExRouter(data);
    } else if (what == "perpReader") {
      perpReader = IPerpReader(data);
    } else if (what == "pricer") {
      pricer = IPricer(data);
    } else {
      revert("Fund/file-unrecognized-param");
    }
  }

  function assetPrice(address asset) public view returns (uint) {
    return pricer.assetPrice(asset);
  }

  function perpGenMarketSalt(address index, address long, address short)
    public
    pure
    returns (bytes32 salt)
  {
    salt = keccak256(abi.encode("GMX_MARKET", index, long, short, "base-v1"));
  }

  function perpGetMarket(bytes32 salt) public view returns (address) {
    IPerpMarket.MarketProps memory market = perpReader.getMarketBySalt(perpDataStore, salt);
    return market.marketToken;
  }

  function perpGetMarket(address market) public view returns (IPerpMarket.MarketProps memory) {
    return perpReader.getMarket(perpDataStore, market);
  }

  function perpGetMarketTokenPrice(address[3] memory tokens, uint[3] memory prices)
    public
    view
    returns (uint)
  {
    bytes32 salt = perpGenMarketSalt(tokens[0], tokens[1], tokens[2]);
    IPerpMarket.MarketProps memory mprops = IPerpMarket.MarketProps({
      marketToken: perpGetMarket(salt),
      indexToken: tokens[0],
      longToken: tokens[1],
      shortToken: tokens[2]
    });
    IPerpMarket.PriceProps memory indexPrice =
      IPerpMarket.PriceProps({min: prices[0], max: prices[0]});
    IPerpMarket.PriceProps memory longPrice =
      IPerpMarket.PriceProps({min: prices[1], max: prices[1]});
    IPerpMarket.PriceProps memory shortPrice =
      IPerpMarket.PriceProps({min: prices[2], max: prices[2]});
    (int mtPrice,) = perpReader.getMarketTokenPrice(
      perpDataStore, mprops, indexPrice, longPrice, shortPrice, MAX_PNL_FACTOR_FOR_TRADERS, true
    );
    require(mtPrice > 0, "Fund/invalid market price");
    return uint(mtPrice) / 1000; // 10 ** 3
  }

  function perpDepositCallback(bytes32, PerpMarket memory market, uint) external auth {
    PerpMarket storage m = perpMarkets[market.market];
    if (m.market == address(0)) {
      perpMarketList.push(market.market);
    }
    market.longAmount += m.longAmount;
    market.shortAmount += m.shortAmount;
    perpMarkets[market.market] = market;
    perpUpdateProfit(market.market);
  }

  function perpUpdateProfit(address market) public {
    PerpMarket storage m = perpMarkets[market];
    IPerpMarket.MarketProps memory mprops = perpGetMarket(market);
    address[3] memory tokens = [mprops.indexToken, mprops.longToken, mprops.shortToken];
    uint[3] memory prices =
      [assetPrice(mprops.indexToken), assetPrice(mprops.longToken), assetPrice(mprops.shortToken)];
    uint[3] memory perpPrices =
      [toPerpPrice(prices[0]), toPerpPrice(prices[1]), toPerpPrice(prices[2])];
    m.marketPrice = perpGetMarketTokenPrice(tokens, perpPrices);
    uint bal = IERC20(market).balanceOf(address(this));
    m.profit = int(m.marketPrice * bal) - int(m.longAmount * prices[1] + m.shortAmount * prices[2]);
  }

  function toPerpPrice(uint price_) public pure returns (uint) {
    return price_ * (10 ** 3); // perp price is 10 ** 30, we use 10 ** 27
  }

  function perpCancelDepositCallback(bytes32 key) external auth {}

  function perpWithdrawCallback(bytes32, address market, uint amount0, uint amount1) external auth {
    require(market != address(0), "Fund/invalid withdraw key");
    PerpMarket storage pmarket = perpMarkets[market];
    pmarket.longAmount -= amount0;
    pmarket.shortAmount -= amount1;
    perpUpdateProfit(market);
  }

  function perpCancelWithdrawCallback(bytes32 key) external auth {}

  function perpDeposit(
    address market,
    address long,
    address short,
    uint longAmount,
    uint shortAmount,
    uint execFee
  ) external payable auth nonReentrant returns (bytes32 key) {
    IERC20(long).safeTransferFrom(msg.sender, address(this), longAmount);
    IERC20(short).safeTransferFrom(msg.sender, address(this), shortAmount);
    perpExRouter.sendTokens(long, perpDepositVault, longAmount);
    perpExRouter.sendTokens(short, perpDepositVault, shortAmount);
    IPerpExRouter.CreateDepositParams memory params = IPerpExRouter.CreateDepositParams({
      receiver: address(this),
      callbackContract: perpCallback,
      uiFeeReceiver: address(this),
      market: market,
      initialLongToken: long,
      initialShortToken: short,
      longTokenSwapPath: new address[](0),
      shortTokenSwapPath: new address[](0),
      minMarketTokens: 0,
      shouldUnwrapNativeToken: true,
      executionFee: execFee,
      callbackGasLimit: 0
    });

    key = perpExRouter.createDeposit(params);
  }

  function perpWithdraw(address market, uint longAmount, uint shortAmount, uint execFee)
    external
    payable
    auth
    nonReentrant
    returns (bytes32 key)
  {
    IPerpExRouter.CreateWithdrawalParams memory params = IPerpExRouter.CreateWithdrawalParams({
      receiver: address(msg.sender),
      callbackContract: perpCallback,
      uiFeeReceiver: address(this),
      market: market,
      longTokenSwapPath: new address[](0),
      shortTokenSwapPath: new address[](0),
      minLongTokenAmount: longAmount,
      minShortTokenAmount: shortAmount,
      shouldUnwrapNativeToken: false,
      executionFee: execFee,
      callbackGasLimit: 0
    });

    key = perpExRouter.createWithdrawal{value: execFee}(params);
  }

  function perpOrder(BaseOrderUtils.CreateOrderParams calldata params)
    external
    payable
    auth
    nonReentrant
    returns (bytes32)
  {
    return perpExRouter.createOrder{value: params.numbers.executionFee}(params);
  }

  function perpUpdateOrder(
    bytes32 key,
    uint sizeDeltaUsd,
    uint acceptablePrice,
    uint triggerPrice,
    uint minOutputAmount
  ) external payable auth nonReentrant {
    perpExRouter.updateOrder(key, sizeDeltaUsd, acceptablePrice, triggerPrice, minOutputAmount);
  }

  function perpCancelOrder(bytes32 key) external auth nonReentrant {
    perpExRouter.cancelOrder(key);
  }

  function perpCancelDeposit(bytes32 key) external auth nonReentrant {
    perpExRouter.cancelDeposit(key);
  }

  function perpCancelWithdrawal(bytes32 key) external auth nonReentrant {
    perpExRouter.cancelWithdrawal(key);
  }

  function perpBalance(address asset) public view returns (uint) {
    uint bal = 0;
    for (uint i = 0; i < perpMarketList.length; ++i) {
      address mt = perpMarketList[i];
      PerpMarket memory m = perpMarkets[mt];
      if (m.long == asset) {
        bal += m.longAmount;
      } else if (m.short == asset) {
        bal += m.shortAmount;
      }
    }
    return bal;
  }

  function perpValue() public view returns (uint) {
    uint v = 0;
    uint len = perpMarketList.length;
    for (uint i = 0; i < len; ++i) {
      address mt = perpMarketList[i];
      IPerpMarket.MarketProps memory mprops = perpGetMarket(mt);
      address[3] memory tokens = [mprops.indexToken, mprops.longToken, mprops.shortToken];
      uint[3] memory prices =
        [assetPrice(mprops.indexToken), assetPrice(mprops.longToken), assetPrice(mprops.shortToken)];
      uint[3] memory perpPrices =
        [toPerpPrice(prices[0]), toPerpPrice(prices[1]), toPerpPrice(prices[2])];
      uint mtPrice = perpGetMarketTokenPrice(tokens, perpPrices);
      v += mtPrice * IERC20(mt).balanceOf(address(this));
    }
    return v;
  }
}
