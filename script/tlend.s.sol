// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";

contract TLendScript is Script {
  address deployer;
  string network;
  uint chainId;
  bool testnet;

  function _before() internal {
    deployer = vm.rememberKey(vm.envUint("PRIVATE_KEY"));
    chainId = vm.envUint("CHAIN_ID");
    network = vm.envString("NETWORK");
    testnet = vm.envBool("TESTNET");
  }

  function _run() internal {
    //todo
  }
  function _after() internal {
    //todo
  }

  function run() public {
    vm.startBroadcast(deployer);
    _before();
    _run();
    _after();
    vm.stopBroadcast();
  }
}
