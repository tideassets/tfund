// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";
import {IPancakeV3Factory} from "@tswap/core-v3/interfaces/IPancakeV3Factory.sol";
import {IPancakeV3Pool} from "@tswap/core-v3/interfaces/IPancakeV3Pool.sol";

contract TSwapScript is Script {
  string constant MASTER_CHEF_V3 = "MasterChefV3";
  string constant STABLE_SWAP_FACTORY = "StableSwapFactory";
  string constant STABLE_SWAP_INFO = "StableSwapInfo";
  string constant FACTORY_V2 = "FactoryV2";
  string constant SMART_ROUTER = "SmartRouter";
  string constant SMART_ROUTER_HELPER = "SmartRouterHelper";
  string constant MIXED_ROUTE_QUOTER_V1 = "MixedRouteQuoterV1";
  string constant QUOTER_V2 = "QuoterV2";
  string constant TOKEN_VALIDATOR = "TokenValidator";
  string constant PANCAKE_V3_FACTORY = "PancakeV3Factory";
  string constant PANCAKE_V3_POOL_DEPLOYER = "PancakeV3PoolDeployer";
  string constant SWAP_ROUTER = "SwapRouter";
  string constant V3_MIGRATOR = "V3Migrator";
  string constant TICK_LENS = "TickLens";
  string constant NONFUNGIBLE_TOKEN_POSITION_DESCRIPTOR = "NonfungibleTokenPositionDescriptor";
  string constant NONFUNGIBLE_POSITION_MANAGER = "NonfungiblePositionManager";
  string constant PANCAKE_INTERFACE_MULTICALL = "PancakeInterfaceMulticall";
  string constant PANCAKE_V3_LM_POOL_DEPLOYER = "PancakeV3LmPoolDeployer";

  address deployer;
  string network;
  uint chainId;
  bool testnet;

  mapping(string => address) public addresses;

  function _set_arbitrum_sepolia() internal {
    // "MasterChefV3": "0x9468E00Dc527c154F4AF5300299e1034128F203D",
    // "StableSwapFactory": "0x36c8fa7ca1d981DbaD1b18Cc58EA5cE7A2E2F1CC",
    // "StableSwapInfo": "0x8964F3752AC0b02101aF351BC9c56bc554369E25",
    // "FactoryV2": "0x3615dcdebe21986dB9734B95587ebd9f69CC1DF4",
    // "SmartRouter": "0xbA1Ff174F8c58F5C0EC2BcD9E9718cc4dAE615CD",
    // "SmartRouterHelper": "0xaba0aD1eDFbc4A3D5c45923A49F88cd582D5e808",
    // "MixedRouteQuoterV1": "0x0c29C9A58Cee73407742728A4aAdB29b0b781F0A",
    // "QuoterV2": "0x65b59791Ec52dEEA89a60b303f40788f6B595C11",
    // "TokenValidator": "0x4749D65Efa47D4EeCf06745fE36b8211B665d76f",
    // "PancakeV3Factory": "0xfD9134ad32f64a1e054DE23bc7357A3D47F8c5e5",
    // "PancakeV3PoolDeployer": "0xdf464caec441D822949256c4c8e4c6245258732D",
    // "SwapRouter": "0x49362f7ca9bAb84ADa1059615A5ebaF514F92174",
    // "V3Migrator": "0xFfcbF426639Db9d98DB4BBeeee3fc5b1b6fBC709",
    // "TickLens": "0x0f34b5f0f14Dc239F7505876216647d4648D6083",
    // "NonfungibleTokenPositionDescriptor": "0x1c6c5cf2B1f3d16c302C02AF0A14Cb624619922b",
    // "NonfungiblePositionManager": "0x01d7AF3f76150A07e6Cf968856d9aefE38Ae712F",
    // "PancakeInterfaceMulticall": "0xF54633C03b4350F93B3Bf2E0E63F6554B3a06786",
    // "PancakeV3LmPoolDeployer": "0xA0C06F621B574a5A4Bef9e66E17FF25E72148f04"
    addresses[MASTER_CHEF_V3] = 0x9468E00Dc527c154F4AF5300299e1034128F203D;
    addresses[STABLE_SWAP_FACTORY] = 0x36c8fa7ca1d981DbaD1b18Cc58EA5cE7A2E2F1CC;
    addresses[STABLE_SWAP_INFO] = 0x8964F3752AC0b02101aF351BC9c56bc554369E25;
    addresses[FACTORY_V2] = 0x3615dcdebe21986dB9734B95587ebd9f69CC1DF4;
    addresses[SMART_ROUTER] = 0xbA1Ff174F8c58F5C0EC2BcD9E9718cc4dAE615CD;
    addresses[SMART_ROUTER_HELPER] = 0xaba0aD1eDFbc4A3D5c45923A49F88cd582D5e808;
    addresses[MIXED_ROUTE_QUOTER_V1] = 0x0c29C9A58Cee73407742728A4aAdB29b0b781F0A;
    addresses[QUOTER_V2] = 0x65b59791Ec52dEEA89a60b303f40788f6B595C11;
    addresses[TOKEN_VALIDATOR] = 0x4749D65Efa47D4EeCf06745fE36b8211B665d76f;
    addresses[PANCAKE_V3_FACTORY] = 0xfD9134ad32f64a1e054DE23bc7357A3D47F8c5e5;
    addresses[PANCAKE_V3_POOL_DEPLOYER] = 0xdf464caec441D822949256c4c8e4c6245258732D;
    addresses[SWAP_ROUTER] = 0x49362f7ca9bAb84ADa1059615A5ebaF514F92174;
    addresses[V3_MIGRATOR] = 0xFfcbF426639Db9d98DB4BBeeee3fc5b1b6fBC709;
    addresses[TICK_LENS] = 0x0f34b5f0f14Dc239F7505876216647d4648D6083;
    addresses[NONFUNGIBLE_TOKEN_POSITION_DESCRIPTOR] = 0x1c6c5cf2B1f3d16c302C02AF0A14Cb624619922b;
    addresses[NONFUNGIBLE_POSITION_MANAGER] = 0x01d7AF3f76150A07e6Cf968856d9aefE38Ae712F;
    addresses[PANCAKE_INTERFACE_MULTICALL] = 0xF54633C03b4350F93B3Bf2E0E63F6554B3a06786;
    addresses[PANCAKE_V3_LM_POOL_DEPLOYER] = 0xA0C06F621B574a5A4Bef9e66E17FF25E72148f04;
  }

  function _set_addresses() internal {
    if (testnet) {
      if (chainId == 421614) {
        _set_arbitrum_sepolia();
      } else {
        revert("unsupported chainId");
      }
    } else {
      revert("unsupported network");
    }
  }

  function _before() internal virtual {
    deployer = vm.rememberKey(vm.envUint("PRIVATE_KEY"));
    chainId = vm.envUint("CHAIN_ID");
    network = vm.envString("NETWORK");
    testnet = vm.envBool("TESTNET");

    _set_addresses();
  }

  function _init_master_chef_v3() internal {
    //todo
  }

  function _create_pool() internal {
    //todo
  }

  function _run() internal virtual {
    vm.startBroadcast(deployer);
    //todo
    vm.stopBroadcast();
  }

  function _after() internal virtual {
    //todo
  }

  function run() public virtual {
    _before();
    _run();
    _after();
  }
}
