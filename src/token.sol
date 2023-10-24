// SPDX-License-Identifier: MIT
// Copyright (C) 2023
// token.sol: token contract
//

pragma solidity ^0.8.20;

import "@layerzerolabs/solidity-examples/contracts/token/oft/v2/OFTV2.sol";
import "./auth.sol";

contract Token is OFTV2, Auth {
    constructor(
        string memory name_,
        string memory symbol_,
        address endpoin_
    ) Ownable(msg.sender) OFTV2(name_, symbol_, 18, endpoin_) {
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
