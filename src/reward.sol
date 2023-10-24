// SPDX-License-Identifier: MIT
// Copyright (C) 2023
// uses.sol : use estoken for rewards
//

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./auth.sol";

interface EsTokenLike {
    function deposit(address, uint) external;
}

abstract contract Rewarder is Auth, ReentrancyGuard {
    EsTokenLike public esToken;
    IERC20 public core;
    uint public useEs = 1;

    mapping(address => mapping(address => uint)) public rewards;
    IERC20[] public rtokens;
    mapping(address => uint) public rtokenIndex;
    address[] public users;
    mapping(address => uint) public userIndex;

    constructor(address esToken_, address core_) {
        esToken = EsTokenLike(esToken_);
        core = IERC20(core_);
    }

    function useEsToken() external auth {
        useEs = 1;
    }

    function unUseEsToken() external auth {
        useEs = 0;
    }

    function _claim(address usr, uint amount, address rtoken) internal virtual {
        require(userIndex[usr] > 0, "Rewarder/no-user");
        require(rewards[usr][rtoken] >= amount, "Rewarder/no-reward");
        rewards[usr][rtoken] -= amount;
        if (rtoken == address(core)) {
            if (useEs == 1) {
                IERC20(rtoken).approve(address(esToken), amount);
                esToken.deposit(usr, amount);
                return;
            }
        }
        IERC20(rtoken).transfer(usr, amount);
    }

    function claimReward(
        address rtoken,
        uint amount
    ) external nonReentrant whenNotPaused {
        require(amount > 0, "Reward/no-reward");
        _claim(msg.sender, amount, rtoken);
    }

    function sendBounty(
        address rtoken,
        uint amount
    ) external virtual nonReentrant whenNotPaused {
        IERC20 rt = IERC20(rtoken);
        rt.transferFrom(msg.sender, address(this), amount);
        _addRtoken(rtoken);

        for (uint i = 0; i < users.length; i++) {
            _update(users[i]);
            (uint uw, uint tw) = _getWeight(users[i]);
            uint ra = (uw * amount) / tw;
            rewards[users[i]][rtoken] += ra;
        }
    }

    function _addRtoken(address rtoken) internal {
        if (rtokenIndex[rtoken] == 0) {
            rtokens.push(IERC20(rtoken));
            rtokenIndex[rtoken] = rtokens.length;
        }
    }

    function _delRtoken(address rtoken) internal {
        if (rtokenIndex[rtoken] > 0) {
            uint index = rtokenIndex[rtoken] - 1;
            rtokens[index] = rtokens[rtokens.length - 1];
            rtokenIndex[address(rtokens[index])] = index + 1;
            rtokens.pop();
            rtokenIndex[rtoken] = 0;
        }
    }

    function _addUser(address usr) internal {
        if (userIndex[usr] == 0) {
            users.push(usr);
            userIndex[usr] = users.length;
        }
    }

    function _delUser(address usr) internal {
        if (userIndex[usr] > 0) {
            uint index = userIndex[usr] - 1;
            users[index] = users[users.length - 1];
            userIndex[users[index]] = index + 1;
            users.pop();
            userIndex[usr] = 0;
        }
    }

    function _getWeight(address usr) internal view virtual returns (uint, uint);

    function _update(address usr) internal virtual {}

    function claimReward(
        address rtoken
    ) external nonReentrant whenNotPaused returns (uint) {
        _update(msg.sender);
        uint amount = rewards[msg.sender][rtoken];
        _claim(msg.sender, amount, rtoken);
        return amount;
    }

    function _claimAll(address usr) internal {
        for (uint i = 0; i < rtokens.length; i++) {
            IERC20 rtoken = rtokens[i];
            uint amount = rewards[usr][address(rtoken)];
            _claim(usr, amount, address(rtoken));
        }
    }

    function claimAll() external nonReentrant whenNotPaused {
        _update(msg.sender);
        _claimAll(msg.sender);
    }
}
