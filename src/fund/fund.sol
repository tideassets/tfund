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
import {ISwapMasterChef, ISwapNFTManager} from "./interface/iswap.sol";
import {ILendPool, ILendAddressProvider, ILendDataProvider, IAToken} from "./interface/ilend.sol";
import {PerpCallback} from "./perpcallback.sol";
import {SwapLiquidity} from "./lib/SwapLiquidity.sol";

interface OracleLike {
  function latestRoundData()
    external
    view
    returns (uint80 roundId, int answer, uint startedAt, uint updatedAt, uint80 answeredInRound);
}

contract Fund is Auth, ERC20, ReentrancyGuard, Initializable {
  using SafeERC20 for IERC20;

  address perpCallback;
  address perpDataStore;
  address perpDepositVault;
  address perpRouter;
  IPerpExRouter public perpExRouter;
  IPerpReader public perpReader;
  ISwapMasterChef public swapMasterChef;
  ISwapNFTManager public swapNFTManager;
  ILendAddressProvider public lendAddressProvider;

  mapping(address => uint) usrAveragePrices;
  mapping(address => bool) assetWhiteList;
  address[] public assetList;

  uint[] public nftIds;
  mapping(uint => uint) public nftIdsIndex;

  struct PerpMarket {
    address market;
    address long;
    address short;
    uint longAmount;
    uint shortAmount;
    uint marketPrice;
    int profit;
  }

  address[] public perpMarketList;
  mapping(address => PerpMarket) public perpMarkets;
  bytes32 public constant MAX_PNL_FACTOR_FOR_TRADERS =
    keccak256(abi.encode("MAX_PNL_FACTOR_FOR_TRADERS"));

  mapping(address => OracleLike) public oracles;

  uint public constant PERP_FLOAT_PRECISION = 10 ** 30;
  uint public constant ORACALE_FLOAT_PRECISION = 10 ** 8;
  uint constant FLOAT_PRECISION = 10 ** 27;
  uint constant ONE = 1e18;

  constructor() ERC20("", "") {}

  function initialize(
    address swapMasterChef_,
    address lendAddressProvider_,
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

    swapMasterChef = ISwapMasterChef(swapMasterChef_);
    swapNFTManager = ISwapNFTManager(swapMasterChef.nonfungiblePositionManager());

    lendAddressProvider = ILendAddressProvider(lendAddressProvider_);
  }

  function name() public pure override returns (string memory) {
    return "Fund";
  }

  function symbol() public pure override returns (string memory) {
    return "TFUND";
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
    } else if (what == "swapMasterChef") {
      swapMasterChef = ISwapMasterChef(data);
    } else if (what == "swapNFTManager") {
      swapNFTManager = ISwapNFTManager(data);
    } else if (what == "lendAddressProvider") {
      lendAddressProvider = ILendAddressProvider(data);
    } else {
      revert("Fund/file-unrecognized-param");
    }
  }

  function init(address[] calldata assets, address[] calldata oracles_) external auth {
    require(assets.length == oracles_.length, "Fund/invalid length");
    for (uint i = 0; i < assets.length; ++i) {
      assetWhiteList[assets[i]] = true;
      oracles[assets[i]] = OracleLike(oracles_[i]);
      assetList.push(assets[i]);
    }
  }

  function file(bytes32 what, address who, bool data) public auth {
    if (what == "asset") {
      bool old = assetWhiteList[who];
      if (data != old) {
        assetWhiteList[who] = data;
        if (data) {
          assetList.push(who);
        } else {
          for (uint i = 0; i < assetList.length; ++i) {
            if (assetList[i] == who) {
              assetList[i] = assetList[assetList.length - 1];
              assetList.pop();
              break;
            }
          }
        }
      }
    } else {
      revert("Fund/file-unrecognized-param");
    }
  }

  function file(bytes32 what, address who, address data) public auth {
    if (what == "oracal") {
      oracles[who] = OracleLike(data);
    } else {
      revert("Fund/file-unrecognized-param");
    }
  }

  function assetPrice(address asset) public view returns (uint) {
    OracleLike o = oracles[asset];
    require(address(o) != address(0), "Fund/invalid oracle");
    (, int lasstAnswer,,,) = o.latestRoundData();
    require(lasstAnswer > 0, "Fund/invalid price");
    uint dec = IERC20Metadata(asset).decimals();
    return uint(lasstAnswer) * (10 ** (19 - dec)); // 10 ** (27 - 8 - dec)
  }

  function deposit(address asset, uint amount) external nonReentrant returns (uint) {
    IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
    uint ap = assetPrice(asset);
    uint p = price();
    uint m = amount * ap / p;
    uint bal = balanceOf(msg.sender);
    uint avp = usrAveragePrices[msg.sender];
    _mint(msg.sender, m);
    usrAveragePrices[msg.sender] = (avp * bal + m * p) / balanceOf(msg.sender);
    return m;
  }

  function withdraw(address asset, uint amount) external nonReentrant {
    uint ap = assetPrice(asset);
    uint p = price();
    uint m = amount * ap / p;
    require(balanceOf(msg.sender) >= m, "Fund/insufficient-balance");
    uint bal = balanceOf(msg.sender);
    uint avp = usrAveragePrices[msg.sender];
    _burn(msg.sender, m);
    if (balanceOf(msg.sender) == 0) {
      usrAveragePrices[msg.sender] = 0;
    } else {
      usrAveragePrices[msg.sender] = (avp * bal - m * p) / balanceOf(msg.sender);
    }
    IERC20(asset).safeTransfer(msg.sender, amount);
  }

  function price() public view returns (uint) {
    uint v = totalValue() * ONE;
    return v / totalSupply();
  }

  function totalValue() public view returns (uint) {
    uint asslen = assetList.length;
    uint v = 0;
    for (uint i = 0; i < asslen; ++i) {
      address ass = assetList[i];
      uint bal = IERC20(ass).balanceOf(address(this));
      v += assetPrice(ass) * bal;
    }
    v += lendValue();
    v += swapValue();
    v += perpValue();
    return v;
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
      receiver: address(this),
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

  function swapNftIds() external view returns (uint[] memory) {
    return nftIds;
  }

  function swapDeposit(ISwapNFTManager.MintParams calldata params)
    external
    payable
    auth
    nonReentrant
    returns (uint tokenId, uint amount0, uint amount1)
  {
    (uint id,, uint a0, uint a1) = swapNFTManager.mint(params);
    swapNFTManager.transferFrom(address(this), address(swapMasterChef), id);
    nftIdsIndex[id] = nftIds.length;
    nftIds.push(id);
    return (id, a0, a1);
  }

  function swapCollect(ISwapMasterChef.CollectParams memory params)
    public
    payable
    auth
    nonReentrant
    returns (uint amount0, uint amount1)
  {
    (amount0, amount1) = swapMasterChef.collect(params);
  }

  function swapHavrest(uint _tokenId, address _to) external auth nonReentrant returns (uint reward) {
    return swapMasterChef.harvest(_tokenId, _to);
  }

  function swapIncreaseLiquidity(ISwapMasterChef.IncreaseLiquidityParams calldata params)
    external
    payable
    auth
    nonReentrant
    returns (uint128 liquidity, uint amount0, uint amount1)
  {
    (liquidity, amount0, amount1) = swapMasterChef.increaseLiquidity(params);
  }

  function swapDecreaseLiquidity(ISwapMasterChef.DecreaseLiquidityParams calldata params)
    external
    payable
    auth
    nonReentrant
    returns (uint amount0, uint amount1)
  {
    (amount0, amount1) = swapMasterChef.decreaseLiquidity(params);
  }

  function swapWithdraw(uint tokenId) external auth nonReentrant returns (uint reward) {
    reward = swapMasterChef.withdraw(tokenId, address(this));
  }

  function swapBurn(uint tokenId) external auth nonReentrant {
    swapMasterChef.burn(tokenId);
    uint[] storage ids = nftIds;
    uint index = nftIdsIndex[tokenId];
    uint last = ids.length - 1;
    if (index != last) {
      uint lastId = ids[last];
      ids[index] = lastId;
      nftIdsIndex[lastId] = index;
    }
    ids.pop();
    delete nftIdsIndex[tokenId];
  }

  function swapPositionis(uint tokenId)
    public
    view
    returns (
      uint96 nonce,
      address operator,
      address token0,
      address token1,
      uint24 fee,
      int24 tickLower,
      int24 tickUpper,
      uint128 liquidity,
      uint feeGrowthInside0LastX128,
      uint feeGrowthInside1LastX128,
      uint128 tokensOwed0,
      uint128 tokensOwed1
    )
  {
    return swapMasterChef.positions(tokenId);
  }

  function swapValue() public view returns (uint) {
    uint v = 0;
    uint idsLen = nftIds.length;
    for (uint i = 0; i < idsLen; ++i) {
      uint id = nftIds[i];
      (
        ,
        ,
        address t0,
        address t1,
        ,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity,
        ,
        ,
        uint128 tokensOwned0,
        uint128 tokensOwned1
      ) = swapPositionis(id);
      (,,,,,,, uint pid,) = swapMasterChef.userPositionInfos(id);
      (, address pool,,,,,) = swapMasterChef.poolInfo(pid);
      (int amount0, int amount1) =
        SwapLiquidity.swapLiquidity(pool, int128(liquidity), tickLower, tickUpper);
      v += assetPrice(t0) * (uint(amount0) + tokensOwned0);
      v += assetPrice(t1) * (uint(amount1) + tokensOwned1);
    }
    return v;
  }

  function lendDeposit(address asset, uint amount) external auth nonReentrant {
    IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
    ILendPool(lendAddressProvider.getPool()).supply(asset, amount, address(this), 0);
  }

  function lendWithdraw(address asset, uint amount) public auth nonReentrant {
    ILendPool(lendAddressProvider.getPool()).withdraw(asset, amount, address(this));
  }

  function lendBalance(address asset) public view returns (uint) {
    ILendDataProvider ldp = ILendDataProvider(lendAddressProvider.getPoolDataProvider());
    (address aTokenAddress,,) = ldp.getReserveTokensAddresses(asset);
    return IAToken(aTokenAddress).balanceOf(address(this));
  }

  function lendValue() public view returns (uint) {
    uint v = 0;
    uint asslen = assetList.length;
    for (uint i = 0; i < asslen; ++i) {
      address ass = assetList[i];
      v += assetPrice(ass) * lendBalance(ass);
    }
    return v;
  }
}
