// SPDX-License-Identifier: MIT
// Copyright (C) 2023
// act.sol: user actions and governance actions
//
pragma solidity ^0.8.20;

import "./lib/Deposit.sol";
import "./lib/Withdrawal.sol";
import "./lib/Order.sol";
import "./lib/EventUtils.sol";

interface IFund {
  struct PerpMarket {
    address market;
    address long;
    address short;
    uint longAmount;
    uint shortAmount;
    int marketPrice;
    int profit;
  }

  function perpDepositCallback(bytes32 key, PerpMarket memory market, uint amount) external;
  function perpCancelDepositCallback(bytes32 key) external;
  function perpWithdrawCallback(bytes32 key, uint amount0, uint amoutn1) external;
  function perpCancelWithdrawCallback(bytes32 key) external;
}

contract PerpCallback {
  address public immutable fund;

  constructor(address _fund) {
    fund = _fund;
  }

  function afterDepositExecution(
    bytes32 key,
    Deposit.Props memory deposit,
    EventUtils.EventLogData memory eventData
  ) external {
    IFund.PerpMarket memory market = IFund.PerpMarket({
      market: deposit.addresses.market,
      long: deposit.addresses.initialLongToken,
      short: deposit.addresses.initialShortToken,
      longAmount: deposit.numbers.initialLongTokenAmount,
      shortAmount: deposit.numbers.initialShortTokenAmount,
      marketPrice: 0,
      profit: 0
    });
    IFund(fund).perpDepositCallback(key, market, eventData.uintItems.items[0].value);
  }

  function afterDepositCancellation(
    bytes32 key,
    Deposit.Props memory,
    EventUtils.EventLogData memory
  ) external {
    IFund(fund).perpCancelDepositCallback(key);
  }

  function afterWithdrawalExecution(
    bytes32 key,
    Withdrawal.Props memory,
    EventUtils.EventLogData memory eventData
  ) external {
    IFund(fund).perpWithdrawCallback(
      key, eventData.uintItems.items[0].value, eventData.uintItems.items[1].value
    );
  }

  function afterWithdrawalCancellation(
    bytes32 key,
    Withdrawal.Props memory,
    EventUtils.EventLogData memory
  ) external {
    IFund(fund).perpCancelWithdrawCallback(key);
  }

  function afterOrderExecution(
    bytes32 key,
    Order.Props memory order,
    EventUtils.EventLogData memory eventData
  ) external {}

  function afterOrderCancellation(
    bytes32 key,
    Order.Props memory order,
    EventUtils.EventLogData memory eventData
  ) external {}

  function afterOrderFrozen(
    bytes32 key,
    Order.Props memory order,
    EventUtils.EventLogData memory eventData
  ) external {}
}
