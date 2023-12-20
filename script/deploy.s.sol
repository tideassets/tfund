// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";
import {TToken} from "src/token.sol";
import {Vault} from "src/vault.sol";
import {Locker} from "src/lock.sol";
import {RewarderBase, RewarderCycle, RewarderAccum} from "src/reward.sol";
import {VeToken} from "src/vetoken.sol";
import {EsToken} from "src/estoken.sol";
import {Stakex} from "src/stake.sol";
import {Dao} from "src/dao.sol";

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
  address endpoint;
  TToken TDT;
  TToken sTCA;
  TToken vTCA;
  TToken TTL;
  TToken TTS;
  TToken TTP;

  Vault tdtVault;
  Vault sTCAVault;
  Vault vTCAVault;

  Locker TTLLocker;
  Locker TTSLocker;
  Locker TTPLocker;

  VeToken veTDT;
  VeToken veTTL;
  VeToken veTTS;
  VeToken veTTP;

  EsToken esTDT;
  EsToken esTTL;
  EsToken esTTS;
  EsToken esTTP;

  Dao dao;
  Dao teamDao;
  Dao tsaDao;
  Dao lpFund;

  Stakex tdtStk;
  Stakex ttlStk;
  Stakex ttsStk;
  Stakex ttpStk;

  RewarderCycle tdtRewarderCycle;
  RewarderCycle ttlRewarderCycle;
  RewarderCycle ttsRewarderCycle;
  RewarderCycle ttpRewarderCycle;

  RewarderAccum tdtRewarderAccum;
  RewarderAccum ttlRewarderAccum;
  RewarderAccum ttsRewarderAccum;
  RewarderAccum ttpRewarderAccum;

  function _setUpTokens() internal {
    TDT = new TToken(endpoint, "TDT token", "TDT");
    sTCA = new TToken(endpoint, "sTCA token", "sTCA");
    vTCA = new TToken(endpoint, "vTCA token", "vTCA");
    TTL = new TToken(endpoint, "TTL token", "TTL");
    TTS = new TToken(endpoint, "TTS token", "TTS");
    TTP = new TToken(endpoint, "TTP token", "TTP");
  }

  function _setUpVaults() internal {
    tdtVault = new Vault();
    tdtVault.initialize(address(TDT));
    sTCAVault = new Vault();
    sTCAVault.initialize(address(sTCA));
    vTCAVault = new Vault();
    vTCAVault.initialize(address(vTCA));
  }

  function _setUpDaos() internal {
    dao = new Dao();
    teamDao = new Dao();
    tsaDao = new Dao();
    lpFund = new Dao();
  }

  function _setUpLockers() internal {
    TTLLocker =
      new Locker(address(TTL), address(dao), address(tsaDao), address(teamDao), address(lpFund));
    TTSLocker =
      new Locker(address(TTS), address(dao), address(tsaDao), address(teamDao), address(lpFund));
    TTPLocker =
      new Locker(address(TTP), address(dao), address(tsaDao), address(teamDao), address(lpFund));
  }

  function _setUpVeTokens() internal {
    veTDT = new VeToken();
    veTDT.initialize(address(TDT), "TDT veToken", "veTDT");
    veTTL = new VeToken();
    veTTL.initialize(address(TTL), "TTL veToken", "veTTL");
    veTTS = new VeToken();
    veTTS.initialize(address(TTS), "TTS veToken", "veTTS");
    veTTP = new VeToken();
    veTTP.initialize(address(TTP), "TTP veToken", "veTTP");
  }

  function _setUpEsTokens() internal {
    esTDT = new EsToken(address(TDT), "TDT esToken", "esTDT");
    esTTL = new EsToken(address(TTL), "TTL esToken", "esTTL");
    esTTS = new EsToken(address(TTS), "TTS esToken", "esTTS");
    esTTP = new EsToken(address(TTP), "TTP esToken", "esTTP");
  }

  function _setUpStakexs() internal {
    tdtStk = new Stakex("TDT stkToken", "stkTDT", address(TDT));
    ttlStk = new Stakex("TTL stkToken", "stkTTL", address(TTL));
    ttsStk = new Stakex("TTS stkToken", "stkTTS",address(TTS));
    ttpStk = new Stakex("TTP stkToken", "stkTTP", address(TTP));
  }

  function _setUpRewarders() internal {
    tdtRewarderCycle = new RewarderCycle(address(TDT), address(tdtStk), address(tsaDao));
    ttlRewarderCycle = new RewarderCycle(address(TTL), address(ttlStk), address(tsaDao));
    ttsRewarderCycle = new RewarderCycle(address(TTS), address(ttsStk), address(tsaDao));
    ttpRewarderCycle = new RewarderCycle(address(TTP), address(ttpStk), address(tsaDao));

    tdtRewarderAccum = new RewarderAccum(address(TDT), address(tdtStk), address(tsaDao));
    ttlRewarderAccum = new RewarderAccum(address(TTL), address(ttlStk), address(tsaDao));
    ttsRewarderAccum = new RewarderAccum(address(TTS), address(ttsStk), address(tsaDao));
    ttpRewarderAccum = new RewarderAccum(address(TTP), address(ttpStk), address(tsaDao));
  }

  function _setUpAuth() internal {
    TDT.rely(address(tdtVault));
    sTCA.rely(address(sTCAVault));
    vTCA.rely(address(vTCAVault));

    TTL.rely(address(TTLLocker));
    TTS.rely(address(TTSLocker));
    TTP.rely(address(TTPLocker));
  }

  function _setUpParams() internal {
    tdtRewarderAccum.setEstoken(address(esTDT));
    ttlRewarderAccum.setEstoken(address(esTTL));
    ttsRewarderAccum.setEstoken(address(esTTS));
    ttpRewarderAccum.setEstoken(address(esTTP));

    tdtRewarderAccum.setRPS(1 ether);
    ttlRewarderAccum.setRPS(1 ether);
    ttsRewarderAccum.setRPS(1 ether);
    ttpRewarderAccum.setRPS(1 ether);
  }

  function _setUp() internal {
    _setUpTokens();
    _setUpVaults();
    _setUpDaos();
    _setUpLockers();
    _setUpVeTokens();
    _setUpEsTokens();
    _setUpStakexs();
    _setUpRewarders();

    _setUpAuth();
    _setUpParams();
  }

  function run() public {
    address deployer = vm.rememberKey(vm.envUint("PRIVATE_KEY"));
    endpoint = vm.envAddress("LAYERZERO_ENDPOINT");
    uint chainId = vm.envUint("CHAIN_ID");

    vm.startBroadcast(deployer);
    _setUp();

    vm.stopBroadcast();
  }
}
