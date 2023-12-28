// SPDX-License-Identifier: MIT
// Copyright (C) 2023
// act.sol: user actions and governance actions
//
pragma solidity ^0.8.20;

import "./SqrtPriceMath.sol";
import "./TickMath.sol";

interface ISwapPool {
  function slot0()
    external
    view
    returns (
      uint160 sqrtPriceX96,
      int24 tick,
      uint16 observationIndex,
      uint16 observationCardinality,
      uint16 observationCardinalityNext,
      uint8 feeProtocol,
      bool unlocked
    );
}

library SwapLiquidity {
  function swapLiquidity(address pool, int128 liquidity, int24 tickLower, int24 tickUpper)
    internal
    view
    returns (int amount0, int amount1)
  {
    (uint160 sqrtPriceX96, int24 tick,,,,,) = ISwapPool(pool).slot0();
    if (liquidity != 0) {
      if (tick < tickLower) {
        // current tick is below the passed range; liquidity can only become in range by crossing from left to
        // right, when we'll need _more_ token0 (it's becoming more valuable) so user must provide it
        amount0 = SqrtPriceMath.getAmount0Delta(
          TickMath.getSqrtRatioAtTick(tickLower), TickMath.getSqrtRatioAtTick(tickUpper), liquidity
        );
      } else if (tick < tickUpper) {
        amount0 = SqrtPriceMath.getAmount0Delta(
          sqrtPriceX96, TickMath.getSqrtRatioAtTick(tickUpper), liquidity
        );
        amount1 = SqrtPriceMath.getAmount1Delta(
          TickMath.getSqrtRatioAtTick(tickLower), sqrtPriceX96, liquidity
        );
      } else {
        // current tick is above the passed range; liquidity can only become in range by crossing from right to
        // left, when we'll need _more_ token1 (it's becoming more valuable) so user must provide it
        amount1 = SqrtPriceMath.getAmount1Delta(
          TickMath.getSqrtRatioAtTick(tickLower), TickMath.getSqrtRatioAtTick(tickUpper), liquidity
        );
      }
    }
  }
}
