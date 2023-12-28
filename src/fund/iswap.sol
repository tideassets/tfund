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

  //     uint128 liquidity;
  // uint128 boostLiquidity;
  // int24 tickLower;
  // int24 tickUpper;
  // uint256 rewardGrowthInside;
  // uint256 reward;
  // address user;
  // uint256 pid;
  // uint256 boostMultiplier;

  function userPositionInfos(uint tokenId)
    external
    view
    returns (
      uint128 liquidity,
      uint128 boostLiquidity,
      int24 tickLower,
      int24 tickUpper,
      uint rewardGrowthInside,
      uint reward,
      address user,
      uint pid,
      uint boostMultiplier
    );

  function poolInfo(uint pid)
    external
    view
    returns (
      uint allocPoint,
      // V3 pool address
      address v3Pool,
      // V3 pool token0 address
      address token0,
      // V3 pool token1 address
      address token1,
      // V3 pool fee
      uint24 fee,
      // total liquidity staking in the pool
      uint totalLiquidity,
      // total boost liquidity staking in the pool
      uint totalBoostLiquidity
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
