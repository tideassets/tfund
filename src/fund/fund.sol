// SPDX-License-Identifier: MIT
// Copyright (C) 2023
// act.sol: user actions and governance actions
//
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC20, ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Auth} from "src/auth.sol";
import {IPerpExRouter, IPerpReader, IPerpMarket, BaseOrderUtils} from "src/fund/iperp.sol";
import {ISwapMasterChef, ISwapNFTManager} from "src/fund/iswap.sol";
import {ILendPool, ILendAddressProvider, ILendDataProvider, IAToken} from "src/fund/ilend.sol";
import {PerpCallback} from "./lib/perpcallback.sol";
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

  mapping(address => mapping(address => uint)) public vaultDeposits;
  mapping(address => address) public vaultDaos;
  mapping(address => uint) assetsDeposit;
  mapping(address => uint) usrAveragePrices;
  mapping(address => bool) assWhitelist;
  address[] public assList;

  uint[] public nftIds;
  mapping(uint => uint) public nftIdsIndex;
  mapping(uint => mapping(address => uint)) public swapDeposits;

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
  mapping(address => uint) public perpMarketsIndex;
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

  function file(bytes32 what, address who, bool data) external auth {
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

  function file(bytes32 what, address who, address data) external auth {
    if (what == "dao") {
      vaultDaos[who] = data;
    } else if (what == "oracal") {
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
    // vaultDeposits[msg.sender][asset] += amount;
    // assetsDeposit[asset] += amount;
    int ap = assPrice(asset);
    uint m = amount * uint(ap) / uint(price());
    _mint(msg.sender, m);
  }

  function withdraw(address asset, uint amount) external {
    // require(vaultDeposits[msg.sender][asset] >= amount, "Fund/insufficient-balance");
    int ap = assPrice(asset);
    uint m = amount * uint(ap) / uint(price());
    require(balanceOf(msg.sender) >= m, "Fund/insufficient-balance");
    _burn(msg.sender, m);
    IERC20(asset).safeTransfer(msg.sender, amount);
    // vaultDeposits[msg.sender][asset] -= amount;
    // assetsDeposit[asset] -= amount;
  }

  function price() public view returns (int) {
    return int(ONE);
  }

  function _claimProfit(address asset) internal {
    _swapClaim(asset);
    _lendClaim(asset);
  }

  function balanceOf(address vault, address ass) external view returns (uint) {
    return vaultDeposits[vault][ass];
  }

  function profitOf(address vault, address ass) external view returns (uint) {
    uint lp = lendProfit(ass);
    uint sp = swapProfit(ass);
    uint pp = perpProfit(ass);
    uint vbal = vaultDeposits[vault][ass];
    uint bal = IERC20(ass).balanceOf(address(this));
    uint abal = assetsDeposit[ass];

    return (bal - abal + lp + sp + pp) * vbal / abal;
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
    if (perpMarketsIndex[market.market] == 0) {
      perpMarketList.push(market.market);
      perpMarketsIndex[market.market] = perpMarketList.length;
    }

    PerpMarket storage m = perpMarkets[market.market];
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

    // bytes memory call0 = abi.encodeWithSignature(
    //   "sendTokens(address,address,uint256)", long, perpDepositVault, longAmount
    // );
    // bytes memory call1 = abi.encodeWithSignature(
    //   "sendTokens(address,address,uint256)", short, perpDepositVault, shortAmount
    // );
    // bytes memory call2 = abi.encodeWithSignature(
    //   "createDeposit((address,address,address,address,address,address,address[],address[],uint256,bool,uint256,uint256))",
    //   params
    // );
    // bytes[] memory calls = new bytes[](3);
    // calls[0] = call0;
    // calls[1] = call1;
    // calls[2] = call2;

    // bytes[] memory r = perpExRouter.multicall{value: execFee}(calls);
    // return bytes32(r[2]);
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

  // function perpSimulateExecuteDeposit(
  //   bytes32 key,
  //   IPerpExRouter.SimulatePricesParams memory simulatedOracleParams
  // ) external auth {
  //   perpExRouter.simulateExecuteDeposit(key, simulatedOracleParams);
  // }

  // function perpSimulateExecuteWithdrawal(
  //   bytes32 key,
  //   IPerpExRouter.SimulatePricesParams memory simulatedOracleParams
  // ) external auth {
  //   perpExRouter.simulateExecuteWithdrawal(key, simulatedOracleParams);
  // }

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

  function perpProfit(address) public pure returns (uint) {
    return 0;
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
      v += uint(mtPrice) * IERC20(mt).balanceOf(address(this)) / ONE;
    }
    return v;
  }

  function _perpClaim(address) internal pure {}

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
    swapDeposits[id][params.token0] = a0;
    swapDeposits[id][params.token1] = a1;
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
    (,, address token0, address token1,,,,,,,,) = swapPositionis(params.tokenId);
    swapDeposits[params.tokenId][token0] += amount0;
    swapDeposits[params.tokenId][token1] += amount1;
  }

  function swapDecreaseLiquidity(ISwapMasterChef.DecreaseLiquidityParams calldata params)
    external
    payable
    auth
    returns (uint amount0, uint amount1)
  {
    (amount0, amount1) = swapMasterChef.decreaseLiquidity(params);
    (,, address token0, address token1,,,,,,,,) = swapPositionis(params.tokenId);
    swapDeposits[params.tokenId][token0] -= amount0;
    swapDeposits[params.tokenId][token1] -= amount1;
  }

  function swapWithdraw(uint tokenId) external auth returns (uint reward) {
    (,, address token0, address token1,,,,,,,,) = swapPositionis(tokenId);
    swapDeposits[tokenId][token0] = 0;
    swapDeposits[tokenId][token1] = 0;
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

  function swapBalance(address asset) public view returns (uint) {
    uint len = nftIds.length;
    uint bal = 0;
    for (uint i = 0; i < len; ++i) {
      uint id = nftIds[i];
      bal += swapDeposits[id][asset];
    }
    return bal;
  }

  // function swapValue() public view returns (uint) {
  //   uint v = 0;
  //   uint asslen = assList.length;
  //   for (uint i = 0; i < asslen; ++i) {
  //     address ass = assList[i];
  //     uint bal = swapBalance(ass) + swapProfit(ass);
  //     v += uint(assPrice(ass)) * bal;
  //   }
  //   return v;
  // }

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

  function swapProfit(address asset) public view returns (uint) {
    uint len = nftIds.length;
    uint bal = 0;
    for (uint i = 0; i < len; ++i) {
      uint id = nftIds[i];
      (,, address t0, address t1,,,,,,, uint128 tokensOwned0, uint128 tokensOwned1) =
        swapPositionis(id);
      if (t0 == asset) {
        bal += tokensOwned0;
      } else if (t1 == asset) {
        bal += tokensOwned1;
      }
    }
    return bal;
  }

  function _swapClaim(address asset) internal {
    uint len = nftIds.length;
    for (uint i = 0; i < len; ++i) {
      uint id = nftIds[i];
      (,, address t0, address t1,,,,,,, uint128 tokensOwned0, uint128 tokensOwned1) =
        swapPositionis(id);
      if (t0 == asset || t1 == asset) {
        ISwapMasterChef.CollectParams memory params = ISwapMasterChef.CollectParams({
          tokenId: id,
          recipient: address(this),
          amount0Max: tokensOwned0,
          amount1Max: tokensOwned1
        });
        swapCollect(params);
      }
    }
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

  function lendProfit(address asset) public view returns (uint) {
    ILendDataProvider ldp = ILendDataProvider(lendAddressProvider.getPoolDataProvider());
    (address aTokenAddress,,) = ldp.getReserveTokensAddresses(asset);
    uint aBal = IAToken(aTokenAddress).balanceOf(address(this));
    uint sBal = IAToken(aTokenAddress).scaledBalanceOf(address(this));
    return aBal - sBal;
  }

  function _lendClaim(address asset) internal {
    uint profit = lendProfit(asset);
    ILendPool(lendAddressProvider.getPool()).withdraw(asset, profit, address(this));
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
