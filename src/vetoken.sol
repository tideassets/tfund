// SPDX-License-Identifier: MIT
// Copyright (C) 2023
// vex.sol : veXXX : veTDT, veTTL, veTTS, veTTP
//
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./reward.sol";

contract VeToken is ERC721, ReentrancyGuard, Rewarder {
    using SafeERC20 for IERC20;

    uint256 public tokenId; // current

    struct Pow {
        uint256 amt;
        uint256 start;
        Long long;
        uint256 pow;
    }

    enum Long {
        ONEMON,
        SIXMON,
        ONEYEAR,
        TWOYEAR,
        FOURYEAR
    }

    uint256 public constant POW_DIVISOR = 1000000;
    uint256 public totalPower;

    mapping(uint256 => Pow) public pows; // key is tokenId
    mapping(address => uint256[]) public ids; // key is usr address, value is tokenIds
    mapping(Long => uint256) public mults;
    mapping(Long => uint256) public longs;

    event Deposit(address indexed usr, uint256 amt, uint256 start, Long long);
    event Withdraw(address indexed usr, uint256 amt, uint256 start, Long long);

    constructor(
        string memory name_,
        string memory symbol_,
        address core_,
        address esToken_
    ) ERC721(name_, symbol_) Rewarder(esToken_, core_) {
        longs[Long.ONEMON] = 30 days;
        longs[Long.SIXMON] = 180 days;
        longs[Long.ONEYEAR] = 365 days;
        longs[Long.TWOYEAR] = longs[Long.ONEYEAR] * 2;
        longs[Long.FOURYEAR] = longs[Long.TWOYEAR] * 2;

        // base rate = 1.025
        // ONEMON = 1.025, SIXMON = 1.025 ** 6, ONEYEAR = 1.025 ** 12, 24, 48 ...
        mults[Long.ONEMON] = 1025000;
        mults[Long.SIXMON] = 1159563;
        mults[Long.ONEYEAR] = 1344889;
        mults[Long.TWOYEAR] = 1808726;
        mults[Long.FOURYEAR] = 3271490;
    }

    function power(uint256 tokenId_) public view returns (uint256) {
        Long l = pows[tokenId_].long;
        uint256 amt = pows[tokenId_].amt;
        uint256 mult = mults[l];
        return (mult * amt) / POW_DIVISOR;
    }

    // user power
    function power(address user) public view returns (uint256) {
        uint256[] memory ids_ = ids[user];
        uint256 p = 0;
        for (uint256 i = 0; i < ids_.length; i++) {
            uint256 id = ids_[i];
            if (ownerOf(id) != user) {
                continue;
            }
            p += power(id);
        }
        return p;
    }

    function deposit(
        uint256 amt,
        Long long
    ) external nonReentrant whenNotPaused returns (uint256) {
        SafeERC20.safeTransferFrom(core, msg.sender, address(this), amt);

        tokenId++;
        Pow memory pow = Pow(amt, block.timestamp, long, 0);
        pow.pow = power(tokenId);
        totalPower += pow.pow;
        pows[tokenId] = pow;

        _mint(msg.sender, tokenId);

        ids[msg.sender].push(tokenId);

        _updateReward(msg.sender);

        emit Deposit(msg.sender, amt, block.timestamp, long);
        return tokenId;
    }

    function withdraw(uint256 tokenId_) external nonReentrant whenNotPaused {
        require(
            ownerOf(tokenId_) == msg.sender,
            "VeToken/tokenId not belong you"
        );
        uint256 start = pows[tokenId_].start;
        Long long = pows[tokenId_].long;
        require(block.timestamp >= start + longs[long], "VeToken/time is't up");

        uint256 amt = pows[tokenId_].amt;
        uint256 pow = power(tokenId_);
        totalPower -= pow;
        core.safeTransfer(msg.sender, amt);

        _burn(tokenId_);
        delete pows[tokenId_];

        _updateReward(msg.sender);

        emit Withdraw(msg.sender, amt, start, long);
    }

    function transferFrom(address, address, uint256) public pure override {
        require(false, "VeToken/not allowed");
    }

    function _getUserAmount(
        address usr
    ) internal view override returns (uint) {
        return power(usr);
    }

    function _getTotalAmount() internal view override returns (uint) {
        return totalPower;
    }
}
