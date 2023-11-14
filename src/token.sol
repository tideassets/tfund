// SPDX-License-Identifier: MIT
// Copyright (C) 2023
// token.sol: token contract
//

pragma solidity ^0.8.20;

import "@layerzerolabs/solidity-examples/contracts/token/oft/v2/fee/BaseOFTWithFee.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// new version of Ownable constructor must provide the owner address, so use abstract contract to avoid compilation error
abstract contract OFTWithFee is BaseOFTWithFee, ERC20 {

    uint internal immutable ld2sdRate;

    constructor(string memory _name, string memory _symbol, uint8 _sharedDecimals, address _lzEndpoint) ERC20(_name, _symbol) BaseOFTWithFee(_sharedDecimals, _lzEndpoint) {
        uint8 decimals = decimals();
        require(_sharedDecimals <= decimals, "OFTWithFee: sharedDecimals must be <= decimals");
        ld2sdRate = 10 ** (decimals - _sharedDecimals);
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
    function _debitFrom(address _from, uint16, bytes32, uint _amount) internal virtual override returns (uint) {
        address spender = _msgSender();
        if (_from != spender) _spendAllowance(_from, spender, _amount);
        _burn(_from, _amount);
        return _amount;
    }

    function _creditTo(uint16, address _toAddress, uint _amount) internal virtual override returns (uint) {
        _mint(_toAddress, _amount);
        return _amount;
    }

    function _transferFrom(address _from, address _to, uint _amount) internal virtual override returns (uint) {
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

contract TToken is OFTWithFee, Pausable {
    // Outbound cap
    mapping(uint16 => uint256) public chainIdToOutboundCap;
    mapping(uint16 => uint256) public chainIdToSentTokenAmount;
    mapping(uint16 => uint256) public chainIdToLastSentTimestamp;

    // Inbound cap
    mapping(uint16 => uint256) public chainIdToInboundCap;
    mapping(uint16 => uint256) public chainIdToReceivedTokenAmount;
    mapping(uint16 => uint256) public chainIdToLastReceivedTimestamp;

    // If an address is whitelisted, the inbound/outbound cap checks are skipped
    mapping(address => bool) public whitelist;

    error ExceedOutboundCap(uint256 cap, uint256 amount);
    error ExceedInboundCap(uint256 cap, uint256 amount);

    event SetOperator(address newOperator);
    event SetOutboundCap(uint16 indexed chainId, uint256 cap);
    event SetInboundCap(uint16 indexed chainId, uint256 cap);
    event SetWhitelist(address indexed addr, bool isWhitelist);
    event FallbackWithdraw(address indexed to, uint256 amount);
    event DropFailedMessage(uint16 srcChainId, bytes srcAddress, uint64 nonce);

    constructor(address _lzEndpoint) OFTWithFee("Tide Token", "TToken", 8, _lzEndpoint) Ownable(msg.sender) {}

    function decimals() public pure override returns (uint8){
        return 18;
    }

    function _debitFrom(
        address _from,
        uint16 _dstChainId,
        bytes32 _toAddress,
        uint256 _amount
    ) internal override whenNotPaused returns (uint256) {
        uint256 amount = super._debitFrom(
            _from,
            _dstChainId,
            _toAddress,
            _amount
        );

        if (whitelist[_from]) {
            return amount;
        }

        uint256 sentTokenAmount;
        uint256 lastSentTimestamp = chainIdToLastSentTimestamp[_dstChainId];
        uint256 currTimestamp = block.timestamp;
        if ((currTimestamp / (1 days)) > (lastSentTimestamp / (1 days))) {
            sentTokenAmount = amount;
        } else {
            sentTokenAmount = chainIdToSentTokenAmount[_dstChainId] + amount;
        }

        uint256 outboundCap = chainIdToOutboundCap[_dstChainId];
        if (sentTokenAmount > outboundCap) {
            revert ExceedOutboundCap(outboundCap, sentTokenAmount);
        }

        chainIdToSentTokenAmount[_dstChainId] = sentTokenAmount;
        chainIdToLastSentTimestamp[_dstChainId] = currTimestamp;

        return amount;
    }

    function _creditTo(
        uint16 _srcChainId,
        address _toAddress,
        uint256 _amount
    ) internal override whenNotPaused returns (uint256) {
        uint256 amount = super._creditTo(_srcChainId, _toAddress, _amount);

        if (whitelist[_toAddress]) {
            return amount;
        }

        uint256 receivedTokenAmount;
        uint256 lastReceivedTimestamp = chainIdToLastReceivedTimestamp[
        _srcChainId
        ];
        uint256 currTimestamp = block.timestamp;
        if ((currTimestamp / (1 days)) > (lastReceivedTimestamp / (1 days))) {
            receivedTokenAmount = amount;
        } else {
            receivedTokenAmount =
            chainIdToReceivedTokenAmount[_srcChainId] +
            amount;
        }

        uint256 inboundCap = chainIdToInboundCap[_srcChainId];
        if (receivedTokenAmount > inboundCap) {
            revert ExceedInboundCap(inboundCap, receivedTokenAmount);
        }

        chainIdToReceivedTokenAmount[_srcChainId] = receivedTokenAmount;
        chainIdToLastReceivedTimestamp[_srcChainId] = currTimestamp;

        return amount;
    }

    function setOutboundCap(uint16 chainId, uint256 cap) external onlyOwner {
        chainIdToOutboundCap[chainId] = cap;
        emit SetOutboundCap(chainId, cap);
    }

    function setInboundCap(uint16 chainId, uint256 cap) external onlyOwner {
        chainIdToInboundCap[chainId] = cap;
        emit SetInboundCap(chainId, cap);
    }

    function setWhitelist(address addr, bool isWhitelist) external onlyOwner {
        whitelist[addr] = isWhitelist;
        emit SetWhitelist(addr, isWhitelist);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}