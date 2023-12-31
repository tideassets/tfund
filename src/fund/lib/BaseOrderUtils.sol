// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import "./Order.sol";
import "./Market.sol";

// @title Order
// @dev Library for common order functions used in OrderUtils, IncreaseOrderUtils
// DecreaseOrderUtils, SwapOrderUtils
library BaseOrderUtils {
  using Order for Order.Props;

  // @dev CreateOrderParams struct used in createOrder to avoid stack
  // too deep errors
  //
  // @param addresses address values
  // @param numbers number values
  // @param orderType for order.orderType
  // @param decreasePositionSwapType for order.decreasePositionSwapType
  // @param isLong for order.isLong
  // @param shouldUnwrapNativeToken for order.shouldUnwrapNativeToken
  struct CreateOrderParams {
    CreateOrderParamsAddresses addresses;
    CreateOrderParamsNumbers numbers;
    Order.OrderType orderType;
    Order.DecreasePositionSwapType decreasePositionSwapType;
    bool isLong;
    bool shouldUnwrapNativeToken;
    bytes32 referralCode;
  }

  // @param receiver for order.receiver
  // @param callbackContract for order.callbackContract
  // @param market for order.market
  // @param initialCollateralToken for order.initialCollateralToken
  // @param swapPath for order.swapPath
  struct CreateOrderParamsAddresses {
    address receiver;
    address callbackContract;
    address uiFeeReceiver;
    address market;
    address initialCollateralToken;
    address[] swapPath;
  }

  // @param sizeDeltaUsd for order.sizeDeltaUsd
  // @param triggerPrice for order.triggerPrice
  // @param acceptablePrice for order.acceptablePrice
  // @param executionFee for order.executionFee
  // @param callbackGasLimit for order.callbackGasLimit
  // @param minOutputAmount for order.minOutputAmount
  struct CreateOrderParamsNumbers {
    uint sizeDeltaUsd;
    uint initialCollateralDeltaAmount;
    uint triggerPrice;
    uint acceptablePrice;
    uint executionFee;
    uint callbackGasLimit;
    uint minOutputAmount;
  }

  struct GetExecutionPriceCache {
    uint price;
    uint executionPrice;
    int adjustedPriceImpactUsd;
  }

  // @dev check if an orderType is a market order
  // @param orderType the order type
  // @return whether an orderType is a market order
  function isMarketOrder(Order.OrderType orderType) internal pure returns (bool) {
    // a liquidation order is not considered as a market order
    return orderType == Order.OrderType.MarketSwap || orderType == Order.OrderType.MarketIncrease
      || orderType == Order.OrderType.MarketDecrease;
  }

  // @dev check if an orderType is a limit order
  // @param orderType the order type
  // @return whether an orderType is a limit order
  function isLimitOrder(Order.OrderType orderType) internal pure returns (bool) {
    return orderType == Order.OrderType.LimitSwap || orderType == Order.OrderType.LimitIncrease
      || orderType == Order.OrderType.LimitDecrease;
  }

  // @dev check if an orderType is a swap order
  // @param orderType the order type
  // @return whether an orderType is a swap order
  function isSwapOrder(Order.OrderType orderType) internal pure returns (bool) {
    return orderType == Order.OrderType.MarketSwap || orderType == Order.OrderType.LimitSwap;
  }

  // @dev check if an orderType is a position order
  // @param orderType the order type
  // @return whether an orderType is a position order
  function isPositionOrder(Order.OrderType orderType) internal pure returns (bool) {
    return isIncreaseOrder(orderType) || isDecreaseOrder(orderType);
  }

  // @dev check if an orderType is an increase order
  // @param orderType the order type
  // @return whether an orderType is an increase order
  function isIncreaseOrder(Order.OrderType orderType) internal pure returns (bool) {
    return orderType == Order.OrderType.MarketIncrease || orderType == Order.OrderType.LimitIncrease;
  }

  // @dev check if an orderType is a decrease order
  // @param orderType the order type
  // @return whether an orderType is a decrease order
  function isDecreaseOrder(Order.OrderType orderType) internal pure returns (bool) {
    return orderType == Order.OrderType.MarketDecrease || orderType == Order.OrderType.LimitDecrease
      || orderType == Order.OrderType.StopLossDecrease || orderType == Order.OrderType.Liquidation;
  }

  // @dev check if an orderType is a liquidation order
  // @param orderType the order type
  // @return whether an orderType is a liquidation order
  function isLiquidationOrder(Order.OrderType orderType) internal pure returns (bool) {
    return orderType == Order.OrderType.Liquidation;
  }
}
