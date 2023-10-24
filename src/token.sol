// SPDX-License-Identifier: MIT
// Copyright (C) 2023
// token.sol: token contract
//

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@layerzerolabs/solidity-examples/contracts/token/oft/v2/BaseOFTV2.sol";
import "./auth.sol";


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
        ld2sdRate = 10**(decimals - _sharedDecimals);
    }

    /************************************************************************
     * public functions
     ************************************************************************/
    function circulatingSupply() public view virtual override returns (uint) {
        return totalSupply();
    }

    function token() public view virtual override returns (address) {
        return address(this);
    }

    /************************************************************************
     * internal functions
     ************************************************************************/
    function _debitFrom(
        address _from,
        uint16,
        bytes32,
        uint _amount
    ) internal virtual override returns (uint) {
        address spender = _msgSender();
        if (_from != spender) _spendAllowance(_from, spender, _amount);
        _burn(_from, _amount);
        return _amount;
    }

    function _creditTo(
        uint16,
        address _toAddress,
        uint _amount
    ) internal virtual override returns (uint) {
        _mint(_toAddress, _amount);
        return _amount;
    }

    function _transferFrom(
        address _from,
        address _to,
        uint _amount
    ) internal virtual override returns (uint) {
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

contract Token is OFTV2, Auth {
    constructor(
        string memory name_,
        string memory symbol_,
        address endpoin_
    ) Ownable(msg.sender) OFTV2(name_, symbol_, 8, endpoin_) {}

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
