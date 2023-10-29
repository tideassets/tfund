// SPDX-License-Identifier: MIT
// Copyright (C) 2023
// stake.sol : stake lp tokens for rewards
//

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./auth.sol";
import "./reward.sol";

interface RewarderLike {
    function stake(address, uint) external;

    function unstake(address, uint) external;

    function claim(address, uint) external;

    function claim(address) external;

    function sendReward(address, uint) external;
}

contract Stakex is ERC20, ReentrancyGuard, Auth {
    using SafeERC20 for IERC20;

    IERC20 public sToken;
    address public esToken;

    RTokens public rtokens;
    mapping(address => RewarderLike) public rewarders; // key is rtoken

    constructor(
        string memory name_,
        string memory symbol_,
        address sToken_,
        address esToken_
    ) ERC20(name_, symbol_) {
        sToken = IERC20(sToken_);
        esToken = esToken_;
        rtokens = new RTokens();
    }

    function addRtoken(address rtoken, bool isCycle) external auth {
        rtokens.addRtoken(rtoken);
        RewarderLike rl;
        if (isCycle) {
            RewarderCycle r = new RewarderCycle(rtoken, esToken);
            rl = RewarderLike(address(r));
        } else {
            RewarderPerSecond r = new RewarderPerSecond(rtoken, esToken);
            rl = RewarderLike(address(r));
        }
        rewarders[rtoken] = rl;
    }

    function delRtoken(address rtoken) external auth {
        rtokens.delRtoken(rtoken);
        delete rewarders[rtoken];
    }

    function stake(address to, uint amt) external nonReentrant {
        require(amt > 0, "Stake/zero-amount");
        sToken.transferFrom(msg.sender, address(this), amt);
        _mint(to, amt);

        _stake(to, amt);
    }

    function _stake(address to, uint amt) internal {
        uint rtlen = rtokens.count();
        mapping(address => RewarderLike) storage rewarders_ = rewarders;
        for (uint i = 0; i < rtlen; i++) {
            address rt = rtokens.rtokens(i);
            rewarders_[rt].stake(to, amt);
        }
    }

    function unstake(address to, uint amt) external nonReentrant {
        require(amt > 0, "Stake/zero-amount");
        _burn(msg.sender, amt);
        sToken.transfer(to, amt);

        _unstake(to, amt);
    }

    function _unstake(address to, uint amt) internal {
        uint rtlen = rtokens.count();
        mapping(address => RewarderLike) storage rewarders_ = rewarders;
        for (uint i = 0; i < rtlen; i++) {
            address rt = rtokens.rtokens(i);
            rewarders_[rt].unstake(to, amt);
        }
    }

    function distribute(address rtoken, uint amt) external auth {
        RewarderLike rl = rewarders[rtoken];
        IERC20 token = IERC20(rtoken);
        token.safeTransferFrom(msg.sender, address(rl), amt);
        rl.sendReward(rtoken, amt);
    }
}
