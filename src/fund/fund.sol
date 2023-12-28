// SPDX-License-Identifier: MIT
// Copyright (C) 2023
// act.sol: user actions and governance actions
//
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Auth} from "src/auth.sol";
import {IPerpExRouter, IPerpReader, IPerpMarket, BaseOrderUtils} from "src/fund/iperp.sol";
import {ISwapMasterChef, ISwapNFTManager} from "src/fund/iswap.sol";
import {ILendPool, ILendAddressProvider, ILendDataProvider, IAToken} from "src/fund/ilend.sol";
import {PerpCallback} from "./lib/perpcallback.sol";

contract Fund is Auth, Initializable {
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

  uint[] public nftIds;
  mapping(uint => uint) public nftIdsIndex;
  mapping(uint => mapping(address => uint)) public swapDeposits;

  struct PerpMarket {
    address market;
    address long;
    address short;
    uint longAmount;
    uint shortAmount;
  }

  address[] public perpMarketList;
  mapping(address => uint) public perpMarketsIndex;
  mapping(address => PerpMarket) public perpMarkets;
  mapping(address => mapping(address => uint)) public perpMarketsAmount;
  mapping(bytes32 => PerpMarket) public perpWithdraws;
  bytes32 public constant MAX_PNL_FACTOR_FOR_TRADERS =
    keccak256(abi.encode("MAX_PNL_FACTOR_FOR_TRADERS"));

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

  function setDao(address vault, address dao) external auth {
    vaultDaos[vault] = dao;
  }

  function deposit(address asset, uint amount) external {
    IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
    vaultDeposits[msg.sender][asset] += amount;
    assetsDeposit[asset] += amount;
  }

  function withdraw(address asset, uint amount) external {
    require(vaultDeposits[msg.sender][asset] >= amount, "Fund/insufficient-balance");
    IERC20(asset).safeTransfer(msg.sender, amount);
    vaultDeposits[msg.sender][asset] -= amount;
    assetsDeposit[asset] -= amount;
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

  function getPerpMarketTokenPrice(address[3] calldata tokens, uint[3] calldata prices)
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
    return mtPrice;
  }

  function perpDepositCallback(bytes32, PerpMarket memory market, uint) external {
    perpMarketsAmount[market.market][market.long] += market.longAmount;
    perpMarketsAmount[market.market][market.short] += market.shortAmount;
    if (perpMarketsIndex[market.market] == 0) {
      perpMarketList.push(market.market);
      perpMarketsIndex[market.market] = perpMarketList.length;
      perpMarkets[market.market] = market;
    }
  }

  function perpCancelDepositCallback(bytes32 key) external {}

  function perpWithdrawCallback(bytes32 key, uint amount0, uint amount1) external {
    PerpMarket memory pmarket = perpWithdraws[key];
    require(pmarket.market != address(0), "Fund/invalid withdraw key");
    address market = pmarket.market;
    perpMarketsAmount[market][pmarket.long] -= amount0;
    perpMarketsAmount[market][pmarket.short] -= amount1;
    delete perpWithdraws[key];
  }

  function perpCancelWithdrawCallback(bytes32 key) external {
    delete perpWithdraws[key];
  }

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

  function perpWithdraw(
    address market,
    address long,
    address short,
    uint longAmount,
    uint shortAmount,
    uint execFee
  ) external payable auth returns (bytes32 key) {
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
    perpWithdraws[key] = PerpMarket({
      market: market,
      long: long,
      short: short,
      longAmount: longAmount,
      shortAmount: shortAmount
    });
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
}
