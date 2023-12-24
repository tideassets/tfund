// SPDX-License-Identifier: MIT
// Copyright (C) 2023
// act.sol: user actions and governance actions
//
pragma solidity ^0.8.20;

interface IPool {
  function supply(address asset, uint amount, address onBehalfOf, uint16 referralCode) external;
  function withdraw(address asset, uint amount, address to) external returns (uint);
  function getUserAccountData(address user)
    external
    view
    returns (
      uint totalCollateralBase,
      uint totalDebtBase,
      uint availableBorrowsBase,
      uint currentLiquidationThreshold,
      uint ltv,
      uint healthFactor
    );
}

interface IAddressProvider {
  function getPool() external view returns (address);
  function getPoolDataProvider() external view returns (address);
}

interface IDataProvider {
  function getUserReserveData(address asset, address user)
    external
    view
    returns (
      uint currentATokenBalance,
      uint currentStableDebt,
      uint currentVariableDebt,
      uint principalStableDebt,
      uint scaledVariableDebt,
      uint stableBorrowRate,
      uint liquidityRate,
      uint40 stableRateLastUpdated,
      bool usageAsCollateralEnabled
    );
  function getReserveTokensAddresses(address asset)
    external
    view
    returns (
      address aTokenAddress,
      address stableDebtTokenAddress,
      address variableDebtTokenAddress
    );
}
