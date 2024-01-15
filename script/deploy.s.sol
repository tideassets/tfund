// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";
import {TransparentUpgradeableProxy} from
  "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {TToken} from "src/token.sol";
import {Vault} from "src/vault.sol";
import {Locker} from "src/lock.sol";
import {RewarderBase, RewarderCycle, RewarderAccum} from "src/reward.sol";
import {VeToken} from "src/vetoken.sol";
import {EsToken} from "src/estoken.sol";
import {Stakex} from "src/stake.sol";
import {Dao} from "src/dao.sol";
import {IOU20} from "src/iou.sol";
import {Registry} from "src/reg.sol";

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
  Registry registry;
  address endpoint;
  address deployer;
  uint chainId;

  function _setUpRegistry() internal {
    registry = new Registry();
  }

  function _setUpTokens() internal {
    TToken TDT = new TToken(endpoint, "TDT token", "TDT");
    TToken sTCA = new TToken(endpoint, "sTCA token", "sTCA");
    TToken vTCA = new TToken(endpoint, "vTCA token", "vTCA");
    TToken TTL = new TToken(endpoint, "TTL token", "TTL");
    TToken TTS = new TToken(endpoint, "TTS token", "TTS");
    TToken TTP = new TToken(endpoint, "TTP token", "TTP");

    registry.file(registry.TDT(), address(TDT));
    registry.file(registry.TCAs(), address(sTCA));
    registry.file(registry.TCAv(), address(vTCA));
    registry.file(registry.TTL(), address(TTL));
    registry.file(registry.TTS(), address(TTS));
    registry.file(registry.TTP(), address(TTP));
  }

  function _setUpVaults() internal {
    TransparentUpgradeableProxy tdtProxy = new TransparentUpgradeableProxy(
      address(new Vault()), 
      deployer, 
      abi.encodeWithSignature("initialize(address)", registry.addresses(registry.TDT()))
    );
    TransparentUpgradeableProxy sTCAProxy = new TransparentUpgradeableProxy(
      address(new Vault()),
      deployer,
      abi.encodeWithSignature("initialize(address)", registry.addresses(registry.TCAs()))
    );
    TransparentUpgradeableProxy vTCAProxy = new TransparentUpgradeableProxy(
      address(new Vault()),
      deployer,
      abi.encodeWithSignature("initialize(address)", registry.addresses(registry.TCAv()))
    );

    registry.file(registry.TDT_VAULT(), address(tdtProxy));
    registry.file(registry.TCAS_VAULT(), address(sTCAProxy));
    registry.file(registry.TCAV_VAULT(), address(vTCAProxy));
  }

  function _setUpDaos() internal {
    Dao dao = new Dao();
    Dao teamDao = new Dao();
    Dao tsaDao = new Dao();
    Dao lpFund = new Dao();

    registry.file(registry.DAO(), address(dao));
    registry.file(registry.TEAM_DAO(), address(teamDao));
    registry.file(registry.TSA_DAO(), address(tsaDao));
    registry.file(registry.LP_DAO(), address(lpFund));
  }

  function _setUpLockers() internal {
    address ttl = registry.addresses(registry.TTL());
    address tts = registry.addresses(registry.TTS());
    address ttp = registry.addresses(registry.TTP());
    address dao = registry.addresses(registry.DAO());
    address teamDao = registry.addresses(registry.TEAM_DAO());
    address tsaDao = registry.addresses(registry.TSA_DAO());
    address lpDao = registry.addresses(registry.LP_DAO());

    Locker TTLLocker = new Locker(ttl, dao, tsaDao, teamDao, lpDao);
    Locker TTSLocker = new Locker(tts, dao, tsaDao, teamDao, lpDao);
    Locker TTPLocker = new Locker(ttp, dao, tsaDao, teamDao, lpDao);

    registry.file(registry.TTL_LOKER(), address(TTLLocker));
    registry.file(registry.TTS_LOCK(), address(TTSLocker));
    registry.file(registry.TTP_LOKER(), address(TTPLocker));
  }

  function _setUpVeTokens() internal {
    TransparentUpgradeableProxy veTDTProxy = new TransparentUpgradeableProxy(
      address(new VeToken()),
      deployer,
      abi.encodeWithSignature("initialize(address,string,string)", registry.addresses(registry.TDT()), "TDT veToken", "veTDT")
    );
    TransparentUpgradeableProxy veTTLProxy = new TransparentUpgradeableProxy(
      address(new VeToken()),
      deployer,
      abi.encodeWithSignature("initialize(address,string,string)", registry.addresses(registry.TTL()), "TTL veToken", "veTTL")
    );
    TransparentUpgradeableProxy veTTSProxy = new TransparentUpgradeableProxy(
      address(new VeToken()),
      deployer,
      abi.encodeWithSignature("initialize(address,string,string)", registry.addresses(registry.TTS()), "TTS veToken", "veTTS")
    );
    TransparentUpgradeableProxy veTTPProxy = new TransparentUpgradeableProxy(
      address(new VeToken()),
      deployer,
      abi.encodeWithSignature("initialize(address,string,string)", registry.addresses(registry.TTP()), "TTP veToken", "veTTP")
    );

    registry.file(registry.VETDT(), address(veTDTProxy));
    registry.file(registry.VETTL(), address(veTTLProxy));
    registry.file(registry.VETTS(), address(veTTSProxy));
    registry.file(registry.VETTP(), address(veTTPProxy));
  }

  function _setUpEsTokens() internal {
    TransparentUpgradeableProxy esTTLProxy = new TransparentUpgradeableProxy(
      address(new EsToken()),
      deployer,
      abi.encodeWithSignature("initialize(address,string,string)", registry.addresses(registry.TTL()), "TTL esToken", "esTTL")
    );
    TransparentUpgradeableProxy esTTSProxy = new TransparentUpgradeableProxy(
      address(new EsToken()),
      deployer,
      abi.encodeWithSignature("initialize(address,string,string)", registry.addresses(registry.TTS()), "TTS esToken", "esTTS")
    );
    TransparentUpgradeableProxy esTTPProxy = new TransparentUpgradeableProxy(
      address(new EsToken()),
      deployer,
      abi.encodeWithSignature("initialize(address,string,string)", registry.addresses(registry.TTP()), "TTP esToken", "esTTP")
    );
    TransparentUpgradeableProxy esTDTProxy = new TransparentUpgradeableProxy(
      address(new EsToken()),
      deployer,
      abi.encodeWithSignature("initialize(address,string,string)", registry.addresses(registry.TDT()), "TDT esToken", "esTDT")
    );

    registry.file(registry.ESTDT(), address(esTDTProxy));
    registry.file(registry.ESTTL(), address(esTTLProxy));
    registry.file(registry.ESTTS(), address(esTTSProxy));
    registry.file(registry.ESTTP(), address(esTTPProxy));
  }

  function _setUpStakexs() internal {
    TransparentUpgradeableProxy tdtStkProxy = new TransparentUpgradeableProxy(
      address(new Stakex()),
      deployer,
      abi.encodeWithSignature("initialize(address)", registry.addresses(registry.TDT()))
    );
    TransparentUpgradeableProxy ttlStkProxy = new TransparentUpgradeableProxy(
      address(new Stakex()),
      deployer,
      abi.encodeWithSignature("initialize(address)", registry.addresses(registry.TDT()))
    );
    TransparentUpgradeableProxy ttsStkProxy = new TransparentUpgradeableProxy(
      address(new Stakex()),
      deployer,
      abi.encodeWithSignature("initialize(address)", registry.addresses(registry.TDT()))
    );
    TransparentUpgradeableProxy ttpStkProxy = new TransparentUpgradeableProxy(
      address(new Stakex()),
      deployer,
      abi.encodeWithSignature("initialize(address)", registry.addresses(registry.TDT()))
    );

    registry.file(registry.TDT_STAKER(), address(tdtStkProxy));
    registry.file(registry.TTL_STAKER(), address(ttlStkProxy));
    registry.file(registry.TTS_STAKER(), address(ttsStkProxy));
    registry.file(registry.TTP_STAKER(), address(ttpStkProxy));
  }

  function _setUpRewarders() internal {
    address tdt = registry.addresses(registry.TDT());
    address ttl = registry.addresses(registry.TTL());
    address tts = registry.addresses(registry.TTS());
    address ttp = registry.addresses(registry.TTP());
    address tdtStk = registry.addresses(registry.TDT_STAKER());
    address ttlStk = registry.addresses(registry.TTL_STAKER());
    address ttsStk = registry.addresses(registry.TTS_STAKER());
    address ttpStk = registry.addresses(registry.TTP_STAKER());
    address tsaDao = registry.addresses(registry.TSA_DAO());

    TransparentUpgradeableProxy tdtRewarderCycleProxy = new TransparentUpgradeableProxy(
      address(new RewarderCycle()),
      deployer,
      abi.encodeWithSignature("initialize(address,address,address)", tdt, tdtStk, tsaDao)
    );
    TransparentUpgradeableProxy ttlRewarderCycleProxy = new TransparentUpgradeableProxy(
      address(new RewarderCycle()),
      deployer,
      abi.encodeWithSignature("initialize(address,address,address)", ttl, ttlStk, tsaDao)
    );
    TransparentUpgradeableProxy ttsRewarderCycleProxy = new TransparentUpgradeableProxy(
      address(new RewarderCycle()),
      deployer,
      abi.encodeWithSignature("initialize(address,address,address)", tts, ttsStk, tsaDao)
    );
    TransparentUpgradeableProxy ttpRewarderCycleProxy = new TransparentUpgradeableProxy(
      address(new RewarderCycle()),
      deployer,
      abi.encodeWithSignature("initialize(address,address,address)", ttp, ttpStk, tsaDao)
    );
    TransparentUpgradeableProxy tdtRewarderAccumProxy = new TransparentUpgradeableProxy(
      address(new RewarderAccum()),
      deployer,
      abi.encodeWithSignature("initialize(address,address,address)", tdt, tdtStk, tsaDao)
    );
    TransparentUpgradeableProxy ttlRewarderAccumProxy = new TransparentUpgradeableProxy(
      address(new RewarderAccum()),
      deployer,
      abi.encodeWithSignature("initialize(address,address,address)", ttl, ttlStk, tsaDao)
    );
    TransparentUpgradeableProxy ttsRewarderAccumProxy = new TransparentUpgradeableProxy(
      address(new RewarderAccum()),
      deployer,
      abi.encodeWithSignature("initialize(address,address,address)", tts, ttsStk, tsaDao)
    );
    TransparentUpgradeableProxy ttpRewarderAccumProxy = new TransparentUpgradeableProxy(
      address(new RewarderAccum()),
      deployer,
      abi.encodeWithSignature("initialize(address,address,address)", ttp, ttpStk, tsaDao)
    );

    registry.file(registry.TDT_CYCLE_REWARDER(), address(tdtRewarderCycleProxy));
    registry.file(registry.TTL_CYCLE_REWARDER(), address(ttlRewarderCycleProxy));
    registry.file(registry.TTS_CYCLE_REWARDER(), address(ttsRewarderCycleProxy));
    registry.file(registry.TTP_CYCLE_REWARDER(), address(ttpRewarderCycleProxy));
    registry.file(registry.TDT_ACCUM_REWARDER(), address(tdtRewarderAccumProxy));
    registry.file(registry.TTL_ACCUM_REWARDER(), address(ttlRewarderAccumProxy));
    registry.file(registry.TTS_ACCUM_REWARDER(), address(ttsRewarderAccumProxy));
    registry.file(registry.TTP_ACCUM_REWARDER(), address(ttpRewarderAccumProxy));
  }

  function _setUpAuth() internal {
    address tdt = registry.addresses(registry.TDT());
    address ttl = registry.addresses(registry.TTL());
    address tts = registry.addresses(registry.TTS());
    address ttp = registry.addresses(registry.TTP());
    address sTCA = registry.addresses(registry.TCAs());
    address vTCA = registry.addresses(registry.TCAv());
    address tdtVault = registry.addresses(registry.TDT_VAULT());
    address sTCAVault = registry.addresses(registry.TCAS_VAULT());
    address vTCAVault = registry.addresses(registry.TCAV_VAULT());
    address TTLLocker = registry.addresses(registry.TTL_LOKER());
    address TTSLocker = registry.addresses(registry.TTS_LOCK());
    address TTPLocker = registry.addresses(registry.TTP_LOKER());

    TToken(tdt).rely(tdtVault);
    TToken(sTCA).rely(sTCAVault);
    TToken(vTCA).rely(vTCAVault);

    TToken(ttl).rely(TTLLocker);
    TToken(tts).rely(TTSLocker);
    TToken(ttp).rely(TTPLocker);
  }

  function _setUpParams() internal {
    address esTDT = registry.addresses(registry.ESTDT());
    address esTTL = registry.addresses(registry.ESTTL());
    address esTTS = registry.addresses(registry.ESTTS());
    address esTTP = registry.addresses(registry.ESTTP());

    RewarderAccum tdtRewarderAccum =
      RewarderAccum(registry.addresses(registry.TDT_ACCUM_REWARDER()));
    RewarderAccum ttlRewarderAccum =
      RewarderAccum(registry.addresses(registry.TTL_ACCUM_REWARDER()));
    RewarderAccum ttsRewarderAccum =
      RewarderAccum(registry.addresses(registry.TTS_ACCUM_REWARDER()));
    RewarderAccum ttpRewarderAccum =
      RewarderAccum(registry.addresses(registry.TTP_ACCUM_REWARDER()));

    tdtRewarderAccum.setEstoken(address(esTDT));
    ttlRewarderAccum.setEstoken(address(esTTL));
    ttsRewarderAccum.setEstoken(address(esTTS));
    ttpRewarderAccum.setEstoken(address(esTTP));

    tdtRewarderAccum.setPSR(1 ether);
    ttlRewarderAccum.setPSR(1 ether);
    ttsRewarderAccum.setPSR(1 ether);
    ttpRewarderAccum.setPSR(1 ether);
  }

  function _run() internal {
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
    deployer = vm.rememberKey(vm.envUint("PRIVATE_KEY"));
    endpoint = vm.envAddress("LAYERZERO_ENDPOINT");
    chainId = vm.envUint("CHAIN_ID");

    vm.startBroadcast(deployer);
    _run();
    vm.stopBroadcast();
  }
}
