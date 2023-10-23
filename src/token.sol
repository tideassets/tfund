// SPDX-License-Identifier: MIT
// Copyright (C) 2023
// tdt.sol TDT token contract
//

pragma solidity ^0.8.20;

import "@layerzerolabs/solidity-examples/contracts/token/oft/v2/OFTV2.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

contract Token is OFTV2, Pausable {
  // ---- Auth ----
  mapping(address => uint) wards;

  modifier auth() {
    require(wards[msg.sender] == 1, "Val/not-authorized");
    _;
  }

  function rely(address usr) external auth whenNotPaused {
    wards[usr] = 1;
    emit Rely(usr);
  }

  function deny(address usr) external auth whenNotPaused {
    wards[usr] = 0;
    emit Deny(usr);
  }

  event Rely(address indexed usr);
  event Deny(address indexed usr);

  constructor(
    string memory name_,
    string memory symbol_,
    address endpoin_,
    uint init_amount_
  ) OFTV2(name_, symbol_, 8, endpoin_) {
    wards[msg.sender] = 1;
    _mint(msg.sender, init_amount_);
  }

  function pause() external auth {
    _pause();
  }

  function unpause() external auth {
    _unpause();
  }

  function _debitFrom(
    address from,
    uint16 dstChainId,
    bytes32 toAddr,
    uint amount
  ) internal override whenNotPaused returns (uint) {
    return super._debitFrom(from, dstChainId, toAddr, amount);
  }

  function mint(address account, uint amt) external whenNotPaused auth {
    _mint(account, amt);
  }

  function burn(address account, uint amt) external whenNotPaused {
    _burn(account, amt);
  }
}
