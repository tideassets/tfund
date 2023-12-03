// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";

// 1. 创建6种代币: TDT, sTCA, vTCA, tsStable, TTL, TTS, TTP.
// 2. 创建3个 Vault: TDT Vault, sTCA Vault, vTCA Vault
// 3. 创建3个 Locker: TTL Locker, TTS Locker, TTP Locker
// 4. 创建4个金库地址 Role: Team, Dao, TsaDao , LpFund
// 5. 创建4个veToken: veTDT, veTTL, veTTS, veTTP
// 6. 创建4个esToken: esTDT, esTTL, esTTS, esTTP
// 7. 创建4个Rewarder: TDT Rewarder, TTL Rewarder, TTS Rewarder, TTP Rewarder

// 1. 设置 TDT Vault, sTCA Vault, vTCA Vault 的参数: writeList, min, max range, oracle
// 2. 设置 每个合约的auth: 
//    - TTL, TTS, TTP: 三种token mint auth: rely on locker
//    - TDT Vault, sTCA Vault, vTCA Vault: rely on owner, should set asset param and oracle
//    - TDT Rewarder, TTL Rewarder, TTS Rewarder, TTP Rewarder: rely on owner, should set vault and token
//    - VeToken: rely on owner, should set token

contract DeployScript is Script {
  function setUp() public {}

  function run() public {
    vm.broadcast();
  }
}
