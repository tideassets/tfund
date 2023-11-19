// SPDX-License-Identifier: MIT
// Copyright (C) 2023
// router.sol : user operation interface
//

pragma solidity ^0.8.20;

import "./auth.sol";

contract Router is Auth {
    constructor() {}
}

contract tLendRouter is Auth {
    constructor() {}

    function deposit(address token, address usr, uint amt) external {}

    function withdraw(address token, address receiver, uint amt) external {}

    function borrow(address token, address receiver, uint amt) external {}

    function zap() external {}

    function loop() external {}
}

contract tSwapRouter is Auth {
    constructor() {}

    function swap(
        address tokenA,
        uint amtA,
        address tokenB,
        uint minAmtB,
        address receiver
    ) external returns (uint) {}
}

contract tPerpRouter is Auth {
    constructor() {}
}

contract tStableRouter is Auth {}
