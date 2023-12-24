// SPDX-License-Identifier: MIT
// Copyright (C) 2023
// act.sol: user actions and governance actions
//
pragma solidity ^0.8.20;

interface IExRouter {
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

  function createDeposit(CreateDepositParams calldata params) external returns (bytes32);
  function cancelDeposit(bytes32 key) external;
  function createWithdrawal(CreateWithdrawalParams calldata params) external returns (bytes32);
  function cancelWithdrawal(bytes32 key) external;
  function simulateExecuteDeposit(bytes32 key, SimulatePricesParams memory simulatedOracleParams)
    external;
  function simulateExecuteWithdrawal(bytes32 key, SimulatePricesParams memory simulatedOracleParams)
    external;
  function claimFundingFees(address[] memory markets, address[] memory tokens, address receiver)
    external
    returns (uint[] memory);
  function claimCollateral(
    address[] memory markets,
    address[] memory tokens,
    uint[] memory timeKeys,
    address receiver
  ) external returns (uint[] memory);
  function claimAffiliateRewards(
    address[] memory markets,
    address[] memory tokens,
    address receiver
  ) external returns (uint[] memory);
  function claimUiFees(address[] memory markets, address[] memory tokens, address receiver)
    external
    returns (uint[] memory);
}
