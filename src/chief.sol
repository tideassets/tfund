// SPDX-License-Identifier: MIT
// Copyright (C) 2023
// tvt.sol: tide vetoken contract
//
pragma solidity ^0.8.20;

import {DSRoles, DSAuth, DSAuthority} from "ds-roles/roles.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IOUToken} from "./IOU.sol";

interface IOULike {
  function mint(address, uint) external;
  function burn(address, uint) external;
}

interface TokenLike {
  function transfer(address, uint) external returns (bool);
  function transferFrom(address, address, uint) external returns (bool);
}

interface NFTLike {
  function core() external view returns (address);
  function ownerOf(uint) external view returns (address);
  function powerOf(uint) external view returns (uint);
  function transferFrom(address, address, uint) external;
}

// you can vote use ERC20 token and veToken
contract TApprovals {
  mapping(bytes32 => address[]) public slates;
  mapping(address => bytes32) public votes;
  mapping(address => uint) public approvals;
  mapping(address => uint) public deposits;
  mapping(uint => address) public nfts;
  TokenLike public GOV; // voting token that gets locked up
  IOULike public IOU; // non-voting representation of a token, for e.g. secondary voting mechanisms
  address public hat; // the chieftain's hat

  uint public MAX_YAYS;

  event Etch(bytes32 indexed slate);

  // IOU constructed outside this contract reduces deployment costs significantly
  // lock/free/vote are quite sensitive to token invariants. Caution is advised.
  constructor(address GOV_, address IOU_, uint MAX_YAYS_) {
    GOV = TokenLike(GOV_);
    IOU = IOULike(IOU_);
    MAX_YAYS = MAX_YAYS_;
  }

  function lock(uint wad) public {
    bool ok = GOV.transferFrom(msg.sender, address(this), wad);
    require(ok, "Approvals/failed-transfer");
    IOU.mint(msg.sender, wad);
    deposits[msg.sender] = deposits[msg.sender] + wad;
    addWeight(wad, votes[msg.sender]);
  }

  function free(uint wad) public {
    deposits[msg.sender] = deposits[msg.sender] - wad;
    subWeight(wad, votes[msg.sender]);
    IOU.burn(msg.sender, wad);
    bool ok = GOV.transfer(msg.sender, wad);
    require(ok, "Approvals/failed-transfer");
  }

  function lockNFT(address nft, uint id) public {
    require(NFTLike(nft).core() == address(GOV), "Approveals/Not GOV token NFT");
    require(NFTLike(nft).ownerOf(id) == msg.sender, "Approvals/Not ownerOf id");
    uint wad = NFTLike(nft).powerOf(id);
    NFTLike(nft).transferFrom(msg.sender, address(this), id);
    IOU.mint(msg.sender, wad);
    deposits[msg.sender] = deposits[msg.sender] + wad;
    nfts[id] = msg.sender;
    addWeight(wad, votes[msg.sender]);
  }

  function freeNFT(address nft, uint id) public {
    require(NFTLike(nft).core() == address(GOV), "Approveals/Not GOV token NFT");
    require(nfts[id] == msg.sender, "Approvals/Not ownerOf id");
    uint wad = NFTLike(nft).powerOf(id);
    deposits[msg.sender] = deposits[msg.sender] - wad;
    subWeight(wad, votes[msg.sender]);
    IOU.burn(msg.sender, wad);
    delete nfts[id];
    NFTLike(nft).transferFrom(address(this), msg.sender, id);
  }

  function etch(address[] memory yays) public returns (bytes32 slate) {
    require(yays.length <= MAX_YAYS);
    requireByteOrderedSet(yays);

    bytes32 hash = keccak256(abi.encodePacked(yays));
    slates[hash] = yays;
    emit Etch(hash);
    return hash;
  }

  function vote(address[] memory yays) public returns (bytes32) 
  // note  both sub-calls note
  {
    bytes32 slate = etch(yays);
    vote(slate);
    return slate;
  }

  function vote(bytes32 slate) public {
    require(slates[slate].length > 0, "ds-chief-invalid-slate");
    uint weight = deposits[msg.sender];
    subWeight(weight, votes[msg.sender]);
    votes[msg.sender] = slate;
    addWeight(weight, votes[msg.sender]);
  }

  // like `drop`/`swap` except simply "elect this address if it is higher than current hat"
  function lift(address whom) public {
    require(approvals[whom] > approvals[hat]);
    hat = whom;
  }

  function addWeight(uint weight, bytes32 slate) internal {
    address[] storage yays = slates[slate];
    for (uint i = 0; i < yays.length; i++) {
      approvals[yays[i]] = approvals[yays[i]] + weight;
    }
  }

  function subWeight(uint weight, bytes32 slate) internal {
    address[] storage yays = slates[slate];
    for (uint i = 0; i < yays.length; i++) {
      approvals[yays[i]] = approvals[yays[i]] - weight;
    }
  }

  // Throws unless the array of addresses is a ordered set.
  function requireByteOrderedSet(address[] memory yays) internal pure {
    if (yays.length == 0 || yays.length == 1) {
      return;
    }
    for (uint i = 0; i < yays.length - 1; i++) {
      // strict inequality ensures both ordering and uniqueness
      require((yays[i]) < (yays[i + 1]));
    }
  }
}

// `hat` address is unique root user (has every role) and the
// unique owner of role 0 (typically 'sys' or 'internal')
contract TChief is DSRoles, TApprovals {
  constructor(address GOV, address IOU, uint MAX_YAYS) TApprovals(GOV, IOU, MAX_YAYS) {
    authority = this;
    owner = address(0);
  }

  function setOwner(address owner_) public pure override {
    owner_;
    revert();
  }

  function setAuthority(DSAuthority authority_) public pure override {
    authority_;
    revert();
  }

  function isUserRoot(address who) public view override returns (bool) {
    return (who == hat);
  }

  function setRootUser(address who, bool enabled) public pure override {
    who;
    enabled;
    revert();
  }
}

contract TChiefFab {
  function newChief(address gov, uint MAX_YAYS) public returns (TChief chief) {
    IOUToken iou = new IOUToken('IOU', "iou token");
    chief = new TChief(gov, address(iou), MAX_YAYS);
    iou.transferOwnership(address(chief));
  }
}
