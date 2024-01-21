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

interface IPerpRouter {
  function perpValue() external view returns (uint);
  function perpDeposit(
    address market,
    address long,
    address short,
    uint longAmount,
    uint shortAmount,
    uint execFee
  ) external returns (bytes32 key);

  function perpWithdraw(address market, uint longAmount, uint shortAmount, uint execFee)
    external
    returns (bytes32 key);
}

contract Fund is Auth, ERC20, ReentrancyGuard, Initializable {
  using SafeERC20 for IERC20;

  ISwapMasterChef public swapMasterChef;
  ISwapNFTManager public swapNFTManager;
  ILendAddressProvider public lendAddressProvider;
  IPerpRouter public perpRouter;

  mapping(address => uint) usrAveragePrices;
  mapping(address => bool) assetWhiteList;
  address[] public assetList;

  uint[] public nftIds;
  mapping(uint => uint) public nftIdsIndex;

  mapping(address => OracleLike) public oracles;

  uint public constant PERP_FLOAT_PRECISION = 10 ** 30;
  uint public constant ORACALE_FLOAT_PRECISION = 10 ** 8;
  uint constant FLOAT_PRECISION = 10 ** 27;
  uint constant ONE = 1e18;

  constructor() ERC20("", "") {}

  function initialize(address swapMasterChef_, address lendAddressProvider_, address perpRouter_)
    external
    initializer
  {
    wards[msg.sender] = 1;

    swapMasterChef = ISwapMasterChef(swapMasterChef_);
    swapNFTManager = ISwapNFTManager(swapMasterChef.nonfungiblePositionManager());
    lendAddressProvider = ILendAddressProvider(lendAddressProvider_);
    perpRouter = IPerpRouter(perpRouter_);
  }

  function name() public pure override returns (string memory) {
    return "Fund";
  }

  function symbol() public pure override returns (string memory) {
    return "TFUND";
  }

  function file(bytes32 what, address data) external auth {
    if (what == "swapMasterChef") {
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
    v += perpRouter.perpValue();
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

  function perpDeposit(
    address market,
    address long,
    address short,
    uint longAmount,
    uint shortAmount,
    uint execFee
  ) external auth returns (bytes32 key) {
    return perpRouter.perpDeposit(market, long, short, longAmount, shortAmount, execFee);
  }

  function perpWithdraw(address market, uint longAmount, uint shortAmount, uint execFee)
    external
    auth
    returns (bytes32 key)
  {
    return perpRouter.perpWithdraw(market, longAmount, shortAmount, execFee);
  }
}
