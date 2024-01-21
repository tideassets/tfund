// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";
import "./deploy.s.sol";

contract DeployFundScript is DeployScript {
  struct InitAddresses {
    address perpExRouter;
    address perpDataStore;
    address perpReader;
    address perpDepositVault;
    address perpRouter;
    address swapMasterChef;
    address lendAddressProvider;
  }

  InitAddresses addrs;

  function _fund_oracles() internal view returns (address[] memory oracles_) {
    bytes32[] memory names = _TDT_tokensName();
    uint len = names.length;
    oracles_ = new address[](len);
    for (uint i = 0; i < len; i++) {
      oracles_[i] = oracles[names[i]];
    }
  }

  function _fund_tokens() internal view returns (address[] memory tokens) {
    bytes32[] memory names = _TDT_tokensName();
    uint len = names.length;
    tokens = new address[](len);
    for (uint i = 0; i < len; i++) {
      tokens[i] = gems[names[i]];
    }
  }

  function _setUpFund() internal {
    InitAddresses memory inputs = addrs;
    Fund fund = new Fund();
    TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
      address(fund),
      deployer,
      abi.encodeWithSignature(
        "initialize(address,address,address,address,address,address,address)",
        inputs.swapMasterChef,
        inputs.lendAddressProvider,
        inputs.perpExRouter,
        inputs.perpDataStore,
        inputs.perpReader,
        inputs.perpDepositVault,
        inputs.perpRouter
      )
    );
    registry.file(registry.FUND(), address(proxy));
    Fund tFund = Fund(registry.addresses(registry.FUND()));
    tFund.init(_fund_tokens(), _fund_oracles());

    Vault tdtVault = Vault(registry.addresses(registry.TDT_VAULT()));
    Vault sTCAVault = Vault(registry.addresses(registry.TCAS_VAULT()));
    Vault vTCAVault = Vault(registry.addresses(registry.TCAV_VAULT()));
    tdtVault.file("Fund", address(tFund));
    sTCAVault.file("Fund", address(tFund));
    vTCAVault.file("Fund", address(tFund));
  }

  function _before() internal virtual override {
    super._before();
    address registry_ = vm.envAddress("REGISTRY");
    registry = Registry(registry_);

    addrs.perpExRouter = vm.envAddress("PERP_EX_ROUTER");
    addrs.perpDataStore = vm.envAddress("PERP_DATA_STORE");
    addrs.perpReader = vm.envAddress("PERP_READER");
    addrs.perpDepositVault = vm.envAddress("PERP_DEPOSIT_VAULT");
    addrs.perpRouter = vm.envAddress("PERP_ROUTER");
    addrs.swapMasterChef = vm.envAddress("SWAP_MASTER_CHEF");
    addrs.lendAddressProvider = vm.envAddress("LEND_ADDRESS_PROVIDER");
  }

  function _run() internal virtual override {
    vm.startBroadcast(deployer);
    _setUpFund();
    vm.stopBroadcast();
  }

  function _after() internal virtual override {
    vm.startBroadcast(deployer);
    if (testnet) {
      // _test_fund();
    }
    vm.stopBroadcast();
  }
}
