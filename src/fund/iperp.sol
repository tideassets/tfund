// SPDX-License-Identifier: MIT
// Copyright (C) 2023
// act.sol: user actions and governance actions
//
pragma solidity ^0.8.20;

import "./lib/BaseOrderUtils.sol";

interface IPerpExRouter {
  struct CreateDepositParams {
    address receiver;
    address callbackContract;
    address uiFeeReceiver;
    address market;
    address initialLongToken;
    address initialShortToken;
    address[] longTokenSwapPath;
    address[] shortTokenSwapPath;
    uint minMarketTokens;
    bool shouldUnwrapNativeToken;
    uint executionFee;
    uint callbackGasLimit;
  }

  struct CreateWithdrawalParams {
    address receiver;
    address callbackContract;
    address uiFeeReceiver;
    address market;
    address[] longTokenSwapPath;
    address[] shortTokenSwapPath;
    uint minLongTokenAmount;
    uint minShortTokenAmount;
    bool shouldUnwrapNativeToken;
    uint executionFee;
    uint callbackGasLimit;
  }

  struct Props {
    uint min;
    uint max;
  }

  struct SimulatePricesParams {
    address[] primaryTokens;
    Props[] primaryPrices;
  }

  function sendWnt(address receiver, uint amount) external payable;
  function sendTokens(address token, address receiver, uint amount) external payable;
  function sendNativeToken(address receiver, uint amount) external payable;

  function createDeposit(CreateDepositParams calldata params) external payable returns (bytes32);
  function cancelDeposit(bytes32 key) external payable;

  function createWithdrawal(CreateWithdrawalParams calldata params)
    external
    payable
    returns (bytes32);
  function cancelWithdrawal(bytes32 key) external payable;

  function createOrder(BaseOrderUtils.CreateOrderParams calldata params)
    external
    payable
    returns (bytes32);
  function updateOrder(
    bytes32 key,
    uint sizeDeltaUsd,
    uint acceptablePrice,
    uint triggerPrice,
    uint minOutputAmount
  ) external payable;
  function cancelOrder(bytes32 key) external payable;

  function simulateExecuteDeposit(bytes32 key, SimulatePricesParams memory simulatedOracleParams)
    external
    payable;
  function simulateExecuteWithdrawal(bytes32 key, SimulatePricesParams memory simulatedOracleParams)
    external
    payable;
  function simulateExecuteOrder(bytes32 key, SimulatePricesParams memory simulatedOracleParams)
    external
    payable;

  function claimFundingFees(address[] memory markets, address[] memory tokens, address receiver)
    external
    payable
    returns (uint[] memory);
  function claimCollateral(
    address[] memory markets,
    address[] memory tokens,
    uint[] memory timeKeys,
    address receiver
  ) external payable returns (uint[] memory);
  function claimAffiliateRewards(
    address[] memory markets,
    address[] memory tokens,
    address receiver
  ) external payable returns (uint[] memory);
  function claimUiFees(address[] memory markets, address[] memory tokens, address receiver)
    external
    payable
    returns (uint[] memory);

  function multicall(bytes[] calldata data) external payable returns (bytes[] memory results);
}

interface IPerpMarket {
  struct Props {
    address marketToken;
    address indexToken;
    address longToken;
    address shortToken;
  }
}

interface IPerpReader is IPerpMarket {
  function getMarketBySalt(address dataStore, bytes32 salt) external view returns (Props memory);
  function getMarkets(address dataStore, uint start, uint end)
    external
    view
    returns (Props[] memory);
}
