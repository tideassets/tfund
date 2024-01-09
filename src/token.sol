// SPDX-License-Identifier: MIT
// Copyright (C) 2023
// token.sol: token contract
//
pragma solidity ^0.8.20;

import {BaseOFTV2} from "@layerzerolabs/solidity-examples/contracts/token/oft/v2/BaseOFTV2.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Auth} from "./auth.sol";

// new version of Ownable constructor must provide the owner address, so use abstract contract to avoid compilation error
abstract contract OFTV2 is BaseOFTV2, ERC20 {
  uint internal immutable ld2sdRate;

  constructor(
    string memory _name,
    string memory _symbol,
    uint8 _sharedDecimals,
    address _lzEndpoint
  ) ERC20(_name, _symbol) BaseOFTV2(_sharedDecimals, _lzEndpoint) {
    uint8 decimals = decimals();
    require(_sharedDecimals <= decimals, "OFT: sharedDecimals must be <= decimals");
    ld2sdRate = 10 ** (decimals - _sharedDecimals);
  }

  /**
   *
   * public functions
   *
   */
  function circulatingSupply() public view virtual override returns (uint) {
    return totalSupply();
  }

  function token() public view virtual override returns (address) {
    return address(this);
  }

  /**
   *
   * internal functions
   *
   */
  function _debitFrom(address _from, uint16, bytes32, uint _amount)
    internal
    virtual
    override
    returns (uint)
  {
    address spender = _msgSender();
    if (_from != spender) _spendAllowance(_from, spender, _amount);
    _burn(_from, _amount);
    return _amount;
  }

  function _creditTo(uint16, address _toAddress, uint _amount)
    internal
    virtual
    override
    returns (uint)
  {
    _mint(_toAddress, _amount);
    return _amount;
  }

  function _transferFrom(address _from, address _to, uint _amount)
    internal
    virtual
    override
    returns (uint)
  {
    address spender = _msgSender();
    // if transfer from this contract, no need to check allowance
    if (_from != address(this) && _from != spender) _spendAllowance(_from, spender, _amount);
    _transfer(_from, _to, _amount);
    return _amount;
  }

  function _ld2sdRate() internal view virtual override returns (uint) {
    return ld2sdRate;
  }
}

contract TToken is OFTV2, Auth {
  constructor(address _lzEndpoint, string memory _name, string memory _symbol)
    OFTV2(_name, _symbol, 8, _lzEndpoint)
    Ownable(msg.sender)
  {
    wards[msg.sender] = 1;
  }

  function decimals() public pure override returns (uint8) {
    return 18;
  }

  function _debitFrom(address _from, uint16 _dstChainId, bytes32 _toAddress, uint _amount)
    internal
    override
    whenNotPaused
    returns (uint)
  {
    uint amount = super._debitFrom(_from, _dstChainId, _toAddress, _amount);
    return amount;
  }

  function _creditTo(uint16 _srcChainId, address _toAddress, uint _amount)
    internal
    override
    whenNotPaused
    returns (uint)
  {
    uint amount = super._creditTo(_srcChainId, _toAddress, _amount);
    return amount;
  }

  function mint(address to, uint amount) external auth {
    _mint(to, amount);
  }

  function burn(address from, uint amount) external auth {
    _burn(from, amount);
  }

  // --- Alias --- for Dai
  function push(address usr, uint wad) external {
    bool ok = transfer(usr, wad);
    require(ok, "TToken/push-failed");
  }

  function pull(address usr, uint wad) external {
    bool ok = transferFrom(usr, msg.sender, wad);
    require(ok, "TToken/pull-failed");
  }

  function move(address src, address dst, uint wad) external {
    bool ok = transferFrom(src, dst, wad);
    require(ok, "TToken/move-failed");
  }
}
