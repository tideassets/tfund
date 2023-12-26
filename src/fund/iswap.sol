// SPDX-License-Identifier: MIT
// Copyright (C) 2023
// act.sol: user actions and governance actions
//
pragma solidity ^0.8.20;

interface ISwapMasterChef {
  struct IncreaseLiquidityParams {
    uint tokenId;
    uint amount0Desired;
    uint amount1Desired;
    uint amount0Min;
    uint amount1Min;
    uint deadline;
  }

  struct DecreaseLiquidityParams {
    uint tokenId;
    uint128 liquidity;
    uint amount0Min;
    uint amount1Min;
    uint deadline;
  }

  struct CollectParams {
    uint tokenId;
    address recipient;
    uint128 amount0Max;
    uint128 amount1Max;
  }

  function positions(uint tokenId)
    external
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
    );

  function increaseLiquidity(IncreaseLiquidityParams calldata params)
    external
    payable
    returns (uint128 liquidity, uint amount0, uint amount1);

  function decreaseLiquidity(DecreaseLiquidityParams calldata params)
    external
    payable
    returns (uint amount0, uint amount1);
  function collect(CollectParams calldata params)
    external
    payable
    returns (uint amount0, uint amount1);
  function collectTo(CollectParams calldata params, address to)
    external
    payable
    returns (uint amount0, uint amount1);
  function withdraw(uint _tokenId, address _to) external returns (uint reward);
  function burn(uint tokenId) external payable;
  function nonfungiblePositionManager() external view returns (address);
  function harvest(uint _tokenId, address _to) external returns (uint reward);
}

interface ISwapNFTManager {
  struct MintParams {
    address token0;
    address token1;
    uint24 fee;
    int24 tickLower;
    int24 tickUpper;
    uint amount0Desired;
    uint amount1Desired;
    uint amount0Min;
    uint amount1Min;
    address recipient;
    uint deadline;
  }

  function mint(MintParams calldata params)
    external
    payable
    returns (uint tokenId, uint128 liquidity, uint amount0, uint amount1);

  function transferFrom(address from, address to, uint tokenId) external;
  function balanceOf(address owner) external view returns (uint balance);
}
