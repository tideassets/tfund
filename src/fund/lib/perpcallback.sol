// SPDX-License-Identifier: MIT
// Copyright (C) 2023
// act.sol: user actions and governance actions
//
pragma solidity ^0.8.20;

import "./Deposit.sol";
import "./Withdrawal.sol";
import "./EventUtils.sol";
import {Auth} from "../../auth.sol";

interface IFund {
  function perpDepositCallback(bytes32 key, uint amount) external;
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
    Deposit.Props memory,
    EventUtils.EventLogData memory eventData
  ) external {
    IFund(fund).perpDepositCallback(key, eventData.uintItems.items[0].value);
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
}
