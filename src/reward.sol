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

    uint public sendId = 0;
    mapping(uint => uint) public coinRewards; // one coin reward per id
    uint public constant ONE = 10 ** 18;

    struct Rw {
        uint r;
        uint id;
    }
    mapping(address => mapping(address => Rw)) public rewards;
    IERC20[] public rtokens;
    mapping(address => uint) public rtokenIndex;

    event SendBounty(address indexed rtoken, uint amount);
    event ClaimReward(address indexed usr, uint amount, address indexed rtoken);

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

    function sendBounty(
        address rtoken,
        uint amount
    ) external virtual nonReentrant whenNotPaused {
        IERC20 rt = IERC20(rtoken);
        rt.transferFrom(msg.sender, address(this), amount);
        _addRtoken(rtoken);

        sendId++;
        coinRewards[sendId] = (ONE * amount) / _getTotalAmount();

        emit SendBounty(rtoken, amount);
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

    function _getUserAmount(address usr) internal view virtual returns (uint);

    function _getTotalAmount() internal view virtual returns (uint);

    function _update(address usr) internal virtual {}

    function _updateReward(address usr, address rtoken_) internal virtual {
        uint id = rewards[usr][rtoken_].id + 1;
        uint r = 0;
        uint sid = sendId;
        mapping(uint => uint) storage coinRewards_ = coinRewards;
        for (uint i = id; i <= sid; i++) {
            r += (coinRewards_[i] * _getUserAmount(usr)) / ONE;
        }
        rewards[usr][rtoken_].id = sid;
        rewards[usr][rtoken_].r += r;
    }

    function _updateReward(address usr) internal {
        IERC20[] memory rtokens_ = rtokens;
        for (uint i = 0; i < rtokens_.length; i++) {
            _updateReward(usr, address(rtokens_[i]));
        }
    }

    function claimReward(
        address rtoken
    ) external nonReentrant whenNotPaused returns (uint) {
        _update(msg.sender);
        uint amount = rewards[msg.sender][rtoken].r;
        _claim(msg.sender, amount, rtoken);
        return amount;
    }

    function _claimAll(address usr) internal {
        mapping(address => Rw) storage rs = rewards[usr];
        for (uint i = 0; i < rtokens.length; i++) {
            IERC20 rtoken = rtokens[i];
            uint amount = rs[address(rtoken)].r;
            _claim(usr, amount, address(rtoken));
        }
    }

    function _claim(address usr, uint amount, address rtoken) internal virtual {
        _updateReward(usr, rtoken);
        require(rewards[usr][rtoken].r >= amount, "Rewarder/no-reward");
        rewards[usr][rtoken].r -= amount;
        
        bool b = rtoken == address(core) && useEs == 1;
        if (b) {
            IERC20(rtoken).approve(address(esToken), amount);
            esToken.deposit(usr, amount);
        } else {
            IERC20(rtoken).transfer(usr, amount);
        }
        emit ClaimReward(usr, amount, rtoken);
    }

    function claimReward(
        address rtoken,
        uint amount
    ) external nonReentrant whenNotPaused {
        require(amount > 0, "Reward/no-reward");
        _claim(msg.sender, amount, rtoken);
    }

    function claimAll() external nonReentrant whenNotPaused {
        _update(msg.sender);
        _claimAll(msg.sender);
    }
}
