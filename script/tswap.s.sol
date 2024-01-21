// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";
import {IPancakeV3Factory} from "@tswap/core-v3/interfaces/IPancakeV3Factory.sol";
import {IPancakeV3Pool} from "@tswap/core-v3/interfaces/IPancakeV3Pool.sol";

contract TSwapScript is Script {
  string public constant MASTER_CHEF_V3 = "MasterChefV3";
  string public constant STABLE_SWAP_FACTORY = "StableSwapFactory";
  string public constant STABLE_SWAP_INFO = "StableSwapInfo";
  string public constant FACTORY_V2 = "FactoryV2";
  string public constant SMART_ROUTER = "SmartRouter";
  string public constant SMART_ROUTER_HELPER = "SmartRouterHelper";
  string public constant MIXED_ROUTE_QUOTER_V1 = "MixedRouteQuoterV1";
  string public constant QUOTER_V2 = "QuoterV2";
  string public constant TOKEN_VALIDATOR = "TokenValidator";
  string public constant PANCAKE_V3_FACTORY = "PancakeV3Factory";
  string public constant PANCAKE_V3_POOL_DEPLOYER = "PancakeV3PoolDeployer";
  string public constant SWAP_ROUTER = "SwapRouter";
  string public constant V3_MIGRATOR = "V3Migrator";
  string public constant TICK_LENS = "TickLens";
  string public constant NONFUNGIBLE_TOKEN_POSITION_DESCRIPTOR =
    "NonfungibleTokenPositionDescriptor";
  string public constant NONFUNGIBLE_POSITION_MANAGER = "NonfungiblePositionManager";
  string public constant PANCAKE_INTERFACE_MULTICALL = "PancakeInterfaceMulticall";
  string public constant PANCAKE_V3_LM_POOL_DEPLOYER = "PancakeV3LmPoolDeployer";

  address deployer;
  string network;
  uint chainId;
  bool testnet;

  mapping(string => address) public addresses;

  function _set_arbitrum_sepolia() internal {
    // "MasterChefV3": "0xF9a41DF7D62add1a47E20eA7F6309af090FCa2FC",
    // "StableSwapFactory": "0x4eBcc666E480629fEA80610C823b2C60b9D365C7",
    // "StableSwapInfo": "0x2E5F0085f35b2F0fb96aF9467edC628cA1501C3F",
    // "FactoryV2": "0xe400fA08D7e7f113578cF874443c13F782F4E5b4",
    // "SmartRouter": "0x67Ee861BBE1617C200D7BA7CA1cd36a114092981",
    // "SmartRouterHelper": "0x781cAf7D2475916f7409e2E3A653c41D95a11172",
    // "MixedRouteQuoterV1": "0xfa9Ec0ca7F18a04056BC804f0bD94db503657327",
    // "QuoterV2": "0xad69FD9d3a27cD247edE245EFD78b767caaB5cf1",
    // "TokenValidator": "0x07f7A884795aE10D0CAF8102C26d4e50add0E569",
    // "PancakeV3Factory": "0x142771a351F8f89F9943FF8c1231643a42618F7A",
    // "PancakeV3PoolDeployer": "0xd5c07AA0D16ef46b48112A7dF1405E46A3CEDD6D",
    // "SwapRouter": "0xa4339497cAf19b64e145D67faEC4a0D5B8a5CbDE",
    // "V3Migrator": "0xd7a15dDadd049DB5fb0920336070f88369F5b137",
    // "TickLens": "0x946B12cA2DD1c8aa20DAd926C5658290a234E6Af",
    // "NonfungibleTokenPositionDescriptor": "0x3CCe8340DF9c3ecf7bD6d3Bf33377Ada47A84Ba8",
    // "NonfungiblePositionManager": "0xDFd9d6Bb004b14994995531D928ff7512b31F323",
    // "PancakeInterfaceMulticall": "0x2c7d6DdA3E8D57E02aaaF6A941483A49a7090Fe8",
    // "PancakeV3LmPoolDeployer": "0x08d62f104C606C44e22948a73af221993b2e9cD8"

    addresses[MASTER_CHEF_V3] = 0xF9a41DF7D62add1a47E20eA7F6309af090FCa2FC;
    addresses[STABLE_SWAP_FACTORY] = 0x4eBcc666E480629fEA80610C823b2C60b9D365C7;
    addresses[STABLE_SWAP_INFO] = 0x2E5F0085f35b2F0fb96aF9467edC628cA1501C3F;
    addresses[FACTORY_V2] = 0xe400fA08D7e7f113578cF874443c13F782F4E5b4;
    addresses[SMART_ROUTER] = 0x67Ee861BBE1617C200D7BA7CA1cd36a114092981;
    addresses[SMART_ROUTER_HELPER] = 0x781cAf7D2475916f7409e2E3A653c41D95a11172;
    addresses[MIXED_ROUTE_QUOTER_V1] = 0xfa9Ec0ca7F18a04056BC804f0bD94db503657327;
    addresses[QUOTER_V2] = 0xad69FD9d3a27cD247edE245EFD78b767caaB5cf1;
    addresses[TOKEN_VALIDATOR] = 0x07f7A884795aE10D0CAF8102C26d4e50add0E569;
    addresses[PANCAKE_V3_FACTORY] = 0x142771a351F8f89F9943FF8c1231643a42618F7A;
    addresses[PANCAKE_V3_POOL_DEPLOYER] = 0xd5c07AA0D16ef46b48112A7dF1405E46A3CEDD6D;
    addresses[SWAP_ROUTER] = 0xa4339497cAf19b64e145D67faEC4a0D5B8a5CbDE;
    addresses[V3_MIGRATOR] = 0xd7a15dDadd049DB5fb0920336070f88369F5b137;
    addresses[TICK_LENS] = 0x946B12cA2DD1c8aa20DAd926C5658290a234E6Af;
    addresses[NONFUNGIBLE_TOKEN_POSITION_DESCRIPTOR] = 0x3CCe8340DF9c3ecf7bD6d3Bf33377Ada47A84Ba8;
    addresses[NONFUNGIBLE_POSITION_MANAGER] = 0xDFd9d6Bb004b14994995531D928ff7512b31F323;
    addresses[PANCAKE_INTERFACE_MULTICALL] = 0x2c7d6DdA3E8D57E02aaaF6A941483A49a7090Fe8;
    addresses[PANCAKE_V3_LM_POOL_DEPLOYER] = 0x08d62f104C606C44e22948a73af221993b2e9cD8;
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
