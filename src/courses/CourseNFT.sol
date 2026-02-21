// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC2981} from "@openzeppelin/contracts/token/common/ERC2981.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title CourseNFT
/// @notice ERC721 for a single course. Each token grants access to private course content.
contract CourseNFT is ERC721, ERC2981, Ownable, Pausable, ReentrancyGuard {
    uint256 private _nextTokenId;
    uint256 public mintPrice;
    uint256 public maxSupply;
    string  public baseTokenURI;
    string  public privateContentURI;
    address public treasury;

    event Minted(address indexed to, uint256 indexed tokenId);
    event MintedTo(address indexed payer, address indexed recipient, uint256 indexed tokenId);
    event MintPriceUpdated(uint256 newPrice);
    event PrivateContentUpdated(string newURI);
    event BaseURIUpdated(string newURI);
    event TreasuryUpdated(address indexed newTreasury);

    error IncorrectPayment();
    error MaxSupplyReached();
    error NotTokenHolder();
    error WithdrawalFailed();
    error ZeroAddress();

    constructor(
        string  memory name,
        string  memory symbol,
        uint256        _mintPrice,
        uint256        _maxSupply,
        string  memory _baseTokenURI,
        string  memory _privateContentURI,
        address        _treasury,
        uint96         royaltyFeeBps
    ) ERC721(name, symbol) Ownable(msg.sender) {
        mintPrice          = _mintPrice;
        maxSupply          = _maxSupply;
        baseTokenURI       = _baseTokenURI;
        privateContentURI  = _privateContentURI;
        treasury           = _treasury;
        _setDefaultRoyalty(_treasury, royaltyFeeBps);
    }

    function mint() external payable whenNotPaused nonReentrant returns (uint256) {
        if (msg.value != mintPrice) revert IncorrectPayment();
        if (maxSupply > 0 && _nextTokenId >= maxSupply) revert MaxSupplyReached();
        uint256 tokenId = _nextTokenId++;
        _safeMint(msg.sender, tokenId);
        emit Minted(msg.sender, tokenId);
        return tokenId;
    }

    function mintTo(address recipient) external payable whenNotPaused nonReentrant returns (uint256) {
        if (msg.value != mintPrice) revert IncorrectPayment();
        if (maxSupply > 0 && _nextTokenId >= maxSupply) revert MaxSupplyReached();
        uint256 tokenId = _nextTokenId++;
        _safeMint(recipient, tokenId);
        emit MintedTo(msg.sender, recipient, tokenId);
        return tokenId;
    }

    function getCourseContent(uint256 tokenId) external view returns (string memory) {
        if (ownerOf(tokenId) != msg.sender) revert NotTokenHolder();
        return privateContentURI;
    }

    function totalSupply() external view returns (uint256) { return _nextTokenId; }

    function canMint() external view returns (bool) {
        if (paused()) return false;
        if (maxSupply == 0) return true;
        return _nextTokenId < maxSupply;
    }

    function setMintPrice(uint256 newPrice) external onlyOwner {
        mintPrice = newPrice;
        emit MintPriceUpdated(newPrice);
    }

    function setPrivateContentURI(string memory newURI) external onlyOwner {
        privateContentURI = newURI;
        emit PrivateContentUpdated(newURI);
    }

    function setBaseURI(string memory newURI) external onlyOwner {
        baseTokenURI = newURI;
        emit BaseURIUpdated(newURI);
    }

    function setTreasury(address newTreasury) external onlyOwner {
        if (newTreasury == address(0)) revert ZeroAddress();
        treasury = newTreasury;
        emit TreasuryUpdated(newTreasury);
    }

    function setRoyalty(address receiver, uint96 feeBps) external onlyOwner {
        _setDefaultRoyalty(receiver, feeBps);
    }

    function pause()   external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    function withdraw() external onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        (bool success,) = treasury.call{value: balance}("");
        if (!success) revert WithdrawalFailed();
    }

    function _baseURI() internal view override returns (string memory) { return baseTokenURI; }

    function supportsInterface(bytes4 interfaceId)
        public view override(ERC721, ERC2981) returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
