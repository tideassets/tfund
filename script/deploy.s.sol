// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";
import {TransparentUpgradeableProxy} from
  "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {TToken} from "src/token.sol";
import {Vault, IERC20Metadata} from "src/vault.sol";
import {Locker} from "src/lock.sol";
import {RewarderBase, RewarderCycle, RewarderAccum} from "src/reward.sol";
import {VeToken} from "src/vetoken.sol";
import {EsToken} from "src/estoken.sol";
import {Stakex} from "src/stake.sol";
import {Dao} from "src/dao.sol";
import {IOU20} from "src/iou.sol";
import {Registry} from "src/reg.sol";
import "src/fund/fund.sol";

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
  string network;
  uint chainId;
  bool testnet;

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

    TTLLocker.init();
    TTSLocker.init();
    TTPLocker.init();
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

  function _sTCA_tokensName() internal pure returns (bytes32[] memory names) {
    names = new bytes32[](3);
    names[0] = "USDT";
    names[1] = "USDC";
  }

  function _vTCA_tokensName() internal pure returns (bytes32[] memory names) {
    names = new bytes32[](7);
    names[0] = "WETH";
    names[1] = "WBTC";
    names[2] = "LINK";
  }

  function _TDT_tokensName() internal pure returns (bytes32[] memory names) {
    names = new bytes32[](10);
    names[0] = "WETH";
    names[1] = "USDT";
    names[2] = "USDC";
    names[3] = "WBTC";
    names[4] = "LINK";
  }

  mapping(bytes32 => address) public oracles;

  function _set_aritrum_sepolia_oracles() internal {
    oracles["WETH"] = 0xd30e2101a97dcbAeBCBC04F14C3f624E67A35165;
    oracles["WBTC"] = 0x56a43EB56Da12C0dc1D972ACb089c06a5dEF8e69;
    oracles["USDT"] = 0x80EDee6f667eCc9f63a0a6f55578F870651f06A4;
    oracles["USDC"] = 0x0153002d20B96532C639313c2d54c3dA09109309;
    oracles["LINK"] = 0x0FB99723Aee6f420beAD13e6bBB79b7E6F034298;
    oracles["DAI"] = 0xb113F5A928BCfF189C998ab20d753a47F9dE5A61;

    address weth = gems["WETH"];
    payable(weth).transfer(1 ether);
  }

  mapping(bytes32 => address) public gems;

  function _set_aritrum_sepolia_gems() internal {
    gems["USDT"] = 0xEF64357875D7B0108642d61B99072935B81b1384;
    gems["USDC"] = 0x39E618D761fdD06bF65065d2974128aAeC7b3Fed;
    gems["WBTC"] = 0x4Ac0ED77C4375D48B51D56cc49b7710c3640b9c2;
    gems["AAVE"] = 0x0FDc113b620F994fa7FE03b7454193f519494D40;
    gems["LINK"] = 0xaB7A6599C1804443C04c998D2be87Dc00A8c07bA;
    gems["DAI"] = 0x9714e454274dC66BE57FA8361233221a376f4C2e;
    gems["BAT"] = 0x27880d3ff48265b15FacA7109070be82eC9c861b;
    gems["UNI"] = 0xCB774CF40CfFc88190d27D5c628094d2ca5650B4;
    gems["MATIC"] = 0x6308A5473106B3b178bD8bDa1eFe4F5E930D957D;
  }

  function eqS(string memory a, string memory b) internal pure returns (bool) {
    return (keccak256(abi.encodePacked((a))) == keccak256(abi.encodePacked((b))));
  }

  function _set_oracles() internal {
    if (eqS(network, "arbitrum-sepolia")) {
      _set_aritrum_sepolia_oracles();
    } else {
      revert("DeployScript/_getOracles: network not supported");
    }
  }

  function _set_gems() internal {
    if (eqS(network, "arbitrum-sepolia")) {
      _set_aritrum_sepolia_gems();
    } else {
      revert("DeployScript/_getGems: network not supported");
    }
  }

  uint public constant ONE = 10 ** 18;
  uint public VAULT_INIT_AMOUNT = 10 ** 6;

  function _setUp_init_vault(bytes32[] memory names, bytes32 key) internal {
    uint len = names.length;
    Vault.Ass[] memory asss = new Vault.Ass[](len);
    uint[] memory amts = new uint[](len);
    for (uint i = 0; i < len; i++) {
      bytes32 name = names[i];
      address gem = gems[name];
      uint dec = IERC20Metadata(gem).decimals();
      amts[i] = 10 ** dec * VAULT_INIT_AMOUNT;
      if (name == "WETH") {
        amts[i] = ONE / 10; // no enough eth
      }
      asss[i] = Vault.Ass({
        min: 0,
        max: 80 * ONE / 100,
        out: 50 * ONE / 100,
        inv: 0,
        gem: gems[name],
        oracle: oracles[name]
      });
    }

    Vault vault = Vault(registry.addresses(key));
    vault.init(names, asss);
    vault.init(names, amts);
  }

  function _setUp_vault_init() internal {
    _set_gems();
    _set_oracles();
    _setUp_init_vault(_TDT_tokensName(), registry.TDT_VAULT());
    _setUp_init_vault(_sTCA_tokensName(), registry.TCAS_VAULT());
    _setUp_init_vault(_vTCA_tokensName(), registry.TCAV_VAULT());
  }

  function _readFundParams() internal view returns (Fund.InitAddresses memory addrs) {
    addrs.perpExRouter = vm.envAddress("PERP_EX_ROUTER");
    addrs.perpDataStore = vm.envAddress("PERP_DATA_STORE");
    addrs.perpReader = vm.envAddress("PERP_READER");
    addrs.perpDepositVault = vm.envAddress("PERP_DEPOSIT_VAULT");
    addrs.perpRouter = vm.envAddress("PERP_ROUTER");
    addrs.swapMasterChef = vm.envAddress("SWAP_MASTER_CHEF");
    addrs.lendAddressProvider = vm.envAddress("LEND_ADDRESS_PROVIDER");
  }

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
    Fund.InitAddresses memory inputs = _readFundParams();
    Fund fund = new Fund();
    TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
      address(fund),
      deployer,
      abi.encodeWithSignature(
        "initialize(address,address,address,address,address,address,address)",
        inputs.perpExRouter,
        inputs.perpDataStore,
        inputs.perpReader,
        inputs.perpDepositVault,
        inputs.perpRouter,
        inputs.swapMasterChef,
        inputs.lendAddressProvider
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

  function _setUp() internal {
    _setUpRegistry();
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

    _setUp_vault_init();
    _setUpFund();
  }

  function _run() internal {
    address registry_ = vm.envAddress("REGISTRY");
    if (registry_ == address(0)) {
      _setUp();
    } else {
      registry = Registry(registry_);
    }
  }

  function _before() internal {
    deployer = vm.rememberKey(vm.envUint("PRIVATE_KEY"));
    endpoint = vm.envAddress("LAYERZERO_ENDPOINT");
    chainId = vm.envUint("CHAIN_ID");
    network = vm.envString("NETWORK");
    testnet = vm.envBool("TESTNET");

    VAULT_INIT_AMOUNT = vm.envUint("VAULT_INIT_AMOUNT");
  }

  function run() public virtual {
    vm.startBroadcast(deployer);
    _before();
    _run();
    _after();
    vm.stopBroadcast();
  }

  function _after() internal {
    if (testnet) {
      _test_vault();
      _test_fund();
    }
  }

  function b32_S(bytes32 _bytes32) public pure returns (string memory) {
    uint8 i = 0;
    while (i < 32 && _bytes32[i] != 0) {
      i++;
    }
    bytes memory bytesArray = new bytes(i);
    for (i = 0; i < 32 && _bytes32[i] != 0; i++) {
      bytesArray[i] = _bytes32[i];
    }
    return string(bytesArray);
  }

  function _test_vault() internal {
    Vault tdtVault = Vault(registry.addresses(registry.TDT_VAULT()));
    bytes32[] memory names = _TDT_tokensName();
    uint len = names.length;
    for (uint i = 0; i < len; i++) {
      bytes32 name = names[i];
      address gem = gems[name];
      uint dec = IERC20Metadata(gem).decimals();
      uint amt_in = 10 ** dec * 1000000;
      uint amt_out = amt_in / 1000;
      if (name == "WETH") {
        amt_in = ONE / 10; // no enough eth
        amt_out = amt_in * 1000;
      }

      string memory nameS = b32_S(name);
      uint out = tdtVault.buyExactIn(name, deployer, amt_in, 0);
      console2.log("buyExactIn", nameS, amt_in, out);
      uint use_in = tdtVault.buyExactOut(name, deployer, amt_in, amt_out);
      console2.log("buyExactOut", nameS, use_in, amt_out);

      console2.log("Vault balance", nameS, tdtVault.assetAmount(name));
      console2.log("Vault value", nameS, tdtVault.assetValue(name));

      tdtVault.sellExactIn(name, deployer, out / 2, 0);
      tdtVault.sellExactOut(name, deployer, amt_out, use_in / 2);

      console2.log("Vault balance", nameS, tdtVault.assetAmount(name));
      console2.log("Vault value", nameS, tdtVault.assetValue(name));

      tdtVault.fundDeposit(name, amt_in);
    }
  }

  function _test_fund() internal {
    Fund fund = Fund(registry.addresses(registry.FUND()));
    console2.log("Fund price and total value", uint(fund.price()), fund.totalValue());
  }
}
