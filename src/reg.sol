// SPDX-License-Identifier: MIT
// Copyright (C) 2023
// reg.sol : address registry

pragma solidity ^0.8.20;

import {Auth} from "./auth.sol";

contract Registry is Auth {
  bytes32 public constant TDT = "TDT";
  bytes32 public constant TCAs = "TCAs";
  bytes32 public constant TCAv = "TCAv";
  bytes32 public constant TSTABLE = "tStable";
  bytes32 public constant TTL = "TTL";
  bytes32 public constant TTS = "TTS";
  bytes32 public constant TTP = "TTP";

  bytes32 public constant TDT_VAULT = "TDT vault";
  bytes32 public constant TCAS_VAULT = "TCAs vault";
  bytes32 public constant TCAV_VAULT = "TCAv vault";

  bytes32 public constant DAO = "DAO";
  bytes32 public constant TEAM_DAO = "team DAO";
  bytes32 public constant TSA_DAO = "tsa DAO";
  bytes32 public constant LP_DAO = "lp DAO";

  bytes32 public constant TTL_LOKER = "TTL loker";
  bytes32 public constant TTS_LOCK = "TTS locker";
  bytes32 public constant TTP_LOKER = "TTP locker";

  bytes32 public constant VETDT = "veTDT";
  bytes32 public constant VETTL = "veTTL";
  bytes32 public constant VETTS = "veTTS";
  bytes32 public constant VETTP = "veTTP";

  bytes32 public constant ESTDT = "esTDT";
  bytes32 public constant ESTTL = "esTTL";
  bytes32 public constant ESTTS = "esTTS";
  bytes32 public constant ESTTP = "esTTP";

  bytes32 public constant TDT_STAKER = "TDT staker";
  bytes32 public constant TTS_STAKER = "TTS staker";
  bytes32 public constant TTL_STAKER = "TTL staker";
  bytes32 public constant TTP_STAKER = "TTP staker";

  bytes32 public constant TDT_CYCLE_REWARDER = "TDT cycle rewarder";
  bytes32 public constant TTL_CYCLE_REWARDER = "TTL cycle rewarder";
  bytes32 public constant TTS_CYCLE_REWARDER = "TTS cycle rewarder";
  bytes32 public constant TTP_CYCLE_REWARDER = "TTP cycle rewarder";

  bytes32 public constant TDT_ACCUM_REWARDER = "TDT accum rewarder";
  bytes32 public constant TTL_ACCUM_REWARDER = "TTL accum rewarder";
  bytes32 public constant TTS_ACCUM_REWARDER = "TTS accum rewarder";
  bytes32 public constant TTP_ACCUM_REWARDER = "TTP accum rewarder";

  mapping(bytes32 => address) public addresses;

  function file(bytes32 name, address data) external auth {
    addresses[name] = data;
  }
}
