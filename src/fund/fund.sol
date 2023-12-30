// SPDX-License-Identifier: MIT
// Copyright (C) 2023
// act.sol: user actions and governance actions
//
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC20, ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
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

contract Fund is Auth, Initializable, ERC20 {
  using SafeERC20 for IERC20;

  struct InitAddresses {
    address perpExRouter;
    address perpDataStore;
    address perpReader;
    address perpDepositVault;
    address perpRouter;
    address swapMasterChef;
    address lendAddressProvider;
  }

  address perpCallback;
  address perpDataStore;
  address perpDepositVault;
  address perpRouter;
  IPerpExRouter public perpExRouter;
  IPerpReader public perpReader;
  ISwapMasterChef public swapMasterChef;
  ISwapNFTManager public swapNFTManager;
  ILendAddressProvider public lendAddressProvider;

  mapping(address => int) usrAveragePrices;
  mapping(address => bool) assWhitelist;
  address[] public assList;

  uint[] public nftIds;
  mapping(uint => uint) public nftIdsIndex;

  struct PerpMarket {
    address market;
    address long;
    address short;
    uint longAmount;
    uint shortAmount;
    int marketPrice;
    int profit;
  }

  address[] public perpMarketList;
  mapping(address => PerpMarket) public perpMarkets;
  bytes32 public constant MAX_PNL_FACTOR_FOR_TRADERS =
    keccak256(abi.encode("MAX_PNL_FACTOR_FOR_TRADERS"));

  mapping(address => OracleLike) public oracles;

  uint constant EXPAND_ORACLE_PRICE_PRECISION = 1e10; // because oracle price precision is 1e8, we use 1e18
  uint constant SHRINK_PERP_PRICE_PRECISION = 1e12; // because perp price precision is 1e30, we use 1e18
  uint constant ONE = 1e18;

  constructor() ERC20("Fund", "FUND") {}

  function initialize(InitAddresses calldata addrs) external initializer {
    perpExRouter = IPerpExRouter(addrs.perpExRouter);
    perpReader = IPerpReader(addrs.perpReader);
    perpDataStore = addrs.perpDataStore;
    perpDepositVault = addrs.perpDepositVault;
    perpRouter = addrs.perpRouter;
    perpCallback = address(new PerpCallback(address(this)));
    wards[perpCallback] = 1;

    swapMasterChef = ISwapMasterChef(addrs.swapMasterChef);
    swapNFTManager = ISwapNFTManager(swapMasterChef.nonfungiblePositionManager());

    lendAddressProvider = ILendAddressProvider(addrs.lendAddressProvider);
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
      assWhitelist[assets[i]] = true;
      oracles[assets[i]] = OracleLike(oracles_[i]);
      assList.push(assets[i]);
    }
  }

  function file(bytes32 what, address who, bool data) public auth {
    if (what == "asset") {
      bool old = assWhitelist[who];
      if (data != old) {
        assWhitelist[who] = data;
        if (data) {
          assList.push(who);
        } else {
          for (uint i = 0; i < assList.length; ++i) {
            if (assList[i] == who) {
              assList[i] = assList[assList.length - 1];
              assList.pop();
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

  function assPrice(address asset) public view returns (int) {
    OracleLike o = oracles[asset];
    require(address(o) != address(0), "Fund/invalid oracle");
    (, int lasstAnswer,,,) = o.latestRoundData();
    return lasstAnswer * int(EXPAND_ORACLE_PRICE_PRECISION);
  }

  function deposit(address asset, uint amount) external returns (uint) {
    IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
    int ap = assPrice(asset);
    int p = price();
    uint m = amount * uint(ap) / uint(p);
    uint bal = balanceOf(msg.sender);
    int avp = usrAveragePrices[msg.sender];
    _mint(msg.sender, m);
    usrAveragePrices[msg.sender] = (avp * int(bal) + int(m) * p) / int(balanceOf(msg.sender));
    return m;
  }

  function withdraw(address asset, uint amount) external {
    int ap = assPrice(asset);
    int p = price();
    uint m = amount * uint(ap) / uint(p);
    require(balanceOf(msg.sender) >= m, "Fund/insufficient-balance");
    uint bal = balanceOf(msg.sender);
    int avp = usrAveragePrices[msg.sender];
    _burn(msg.sender, m);
    if (balanceOf(msg.sender) == 0) {
      usrAveragePrices[msg.sender] = 0;
    } else {
      usrAveragePrices[msg.sender] = (avp * int(bal) - int(m) * p) / int(balanceOf(msg.sender));
    }
    IERC20(asset).safeTransfer(msg.sender, amount);
  }

  function price() public view returns (int) {
    uint v = totalValue();
    return int(v / totalSupply());
  }

  function totalValue() public view returns (uint) {
    uint asslen = assList.length;
    uint v = 0;
    for (uint i = 0; i < asslen; ++i) {
      address ass = assList[i];
      uint bal = IERC20(ass).balanceOf(address(this));
      v += uint(assPrice(ass)) * bal;
    }
    v += lendValue();
    v += swapValue();
    v += perpValue();
    return v;
  }

  function genPerpMarketSalt(address index, address long, address short)
    public
    pure
    returns (bytes32 salt)
  {
    salt = keccak256(abi.encode("GMX_MARKET", index, long, short, "base-v1"));
  }

  function getPerpMarket(bytes32 salt) public view returns (address) {
    IPerpMarket.MarketProps memory market = perpReader.getMarketBySalt(perpDataStore, salt);
    return market.marketToken;
  }

  function getPerpMarket(address market) public view returns (IPerpMarket.MarketProps memory) {
    return perpReader.getMarket(perpDataStore, market);
  }

  function getPerpMarketTokenPrice(address[3] memory tokens, uint[3] memory prices)
    public
    view
    returns (int)
  {
    bytes32 salt = genPerpMarketSalt(tokens[0], tokens[1], tokens[2]);
    IPerpMarket.MarketProps memory mprops = IPerpMarket.MarketProps({
      marketToken: getPerpMarket(salt),
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
    return mtPrice / int(SHRINK_PERP_PRICE_PRECISION);
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
    IPerpMarket.MarketProps memory mprops = getPerpMarket(market);
    address[3] memory tokens = [mprops.indexToken, mprops.longToken, mprops.shortToken];
    int[3] memory prices =
      [assPrice(mprops.indexToken), assPrice(mprops.longToken), assPrice(mprops.shortToken)];
    uint[3] memory perpPrices =
      [toPerpPrice(prices[0]), toPerpPrice(prices[1]), toPerpPrice(prices[2])];
    m.marketPrice = int(getPerpMarketTokenPrice(tokens, perpPrices));
    uint bal = IERC20(market).balanceOf(address(this));
    m.profit =
      m.marketPrice * int(bal) - (int(m.longAmount) * prices[1] + int(m.shortAmount) * prices[2]);
  }

  function toPerpPrice(int price_) public pure returns (uint) {
    return uint(price_) * SHRINK_PERP_PRICE_PRECISION;
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
  ) external payable auth returns (bytes32 key) {
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
  ) external payable auth {
    perpExRouter.updateOrder(key, sizeDeltaUsd, acceptablePrice, triggerPrice, minOutputAmount);
  }

  function perpCancelOrder(bytes32 key) external auth {
    perpExRouter.cancelOrder(key);
  }

  function perpCancelDeposit(bytes32 key) external auth {
    perpExRouter.cancelDeposit(key);
  }

  function perpCancelWithdrawal(bytes32 key) external auth {
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
      IPerpMarket.MarketProps memory mprops = getPerpMarket(mt);
      address[3] memory tokens = [mprops.indexToken, mprops.longToken, mprops.shortToken];
      int[3] memory prices =
        [assPrice(mprops.indexToken), assPrice(mprops.longToken), assPrice(mprops.shortToken)];
      uint[3] memory perpPrices =
        [toPerpPrice(prices[0]), toPerpPrice(prices[1]), toPerpPrice(prices[2])];
      int mtPrice = getPerpMarketTokenPrice(tokens, perpPrices);
      v += uint(mtPrice) * IERC20(mt).balanceOf(address(this));
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
    returns (uint amount0, uint amount1)
  {
    (amount0, amount1) = swapMasterChef.collect(params);
  }

  function swapHavrest(uint _tokenId, address _to) external auth returns (uint reward) {
    return swapMasterChef.harvest(_tokenId, _to);
  }

  function swapIncreaseLiquidity(ISwapMasterChef.IncreaseLiquidityParams calldata params)
    external
    payable
    auth
    returns (uint128 liquidity, uint amount0, uint amount1)
  {
    (liquidity, amount0, amount1) = swapMasterChef.increaseLiquidity(params);
  }

  function swapDecreaseLiquidity(ISwapMasterChef.DecreaseLiquidityParams calldata params)
    external
    payable
    auth
    returns (uint amount0, uint amount1)
  {
    (amount0, amount1) = swapMasterChef.decreaseLiquidity(params);
  }

  function swapWithdraw(uint tokenId) external auth returns (uint reward) {
    reward = swapMasterChef.withdraw(tokenId, address(this));
  }

  function swapBurn(uint tokenId) external auth {
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
      v += uint(assPrice(t0)) * (uint(amount0) + tokensOwned0);
      v += uint(assPrice(t1)) * (uint(amount1) + tokensOwned1);
    }
    return v;
  }

  function lendDeposit(address asset, uint amount) external auth {
    IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
    ILendPool(lendAddressProvider.getPool()).supply(asset, amount, address(this), 0);
  }

  function lendWithdraw(address asset, uint amount) public auth {
    ILendPool(lendAddressProvider.getPool()).withdraw(asset, amount, address(this));
  }

  function lendBalance(address asset) public view returns (uint) {
    ILendDataProvider ldp = ILendDataProvider(lendAddressProvider.getPoolDataProvider());
    (address aTokenAddress,,) = ldp.getReserveTokensAddresses(asset);
    return IAToken(aTokenAddress).balanceOf(address(this));
  }

  function lendValue() public view returns (uint) {
    uint v = 0;
    uint asslen = assList.length;
    for (uint i = 0; i < asslen; ++i) {
      address ass = assList[i];
      v += uint(assPrice(ass)) * lendBalance(ass);
    }
    return v;
  }
}
