// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title IdentityNFT
/// @notice Renewable profile NFT ("Identity Card") for the gaming tower.
///         One card per address. Subscription-based: users pay in accepted tokens to
///         activate and renew their card (monthly 30-day or yearly 365-day).
///         Admin can suspend any card for misbehaviour regardless of payment status.
///         When `soulbound` is true, tokens cannot be transferred.
///         Each deployment is one independent collection / city.
contract IdentityNFT is ERC721, Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ── Constants ────────────────────────────────────────────────────────────

    uint256 public constant MONTHLY_PERIOD = 30 days;
    uint256 public constant YEARLY_PERIOD  = 365 days;

    // ── Enums ────────────────────────────────────────────────────────────────

    /// @notice Subscription period choices available at mint and renewal.
    enum Period { Monthly, Yearly }

    /// @notice Derived status of a token — never stored, always computed.
    enum Status { Active, Expired, Suspended }

    // ── Structs ──────────────────────────────────────────────────────────────

    struct TokenConfig {
        uint256 mintPrice;
        uint256 monthlyPrice;
        uint256 yearlyPrice;
        bool    enabled;
    }

    struct InitialTokenConfig {
        address token;
        uint256 mintPrice;
        uint256 monthlyPrice;
        uint256 yearlyPrice;
    }

    // ── Storage ──────────────────────────────────────────────────────────────

    uint256 private _nextTokenId; // starts at 1
    bool    public soulbound;
    address public treasury;

    /// @notice City this collection belongs to — set once at deploy, readable on-chain.
    string  public city;

    mapping(address => TokenConfig) public tokenConfigs;
    address[] private _acceptedTokens;

    /// @dev tokenId => creation timestamp (immutable after mint).
    mapping(uint256 => uint256) public createdAt;

    /// @dev tokenId => subscription expiry timestamp.
    ///      If still active:  renew extends from this value (paid days preserved).
    ///      If expired:       renew restarts from block.timestamp (no grace period).
    mapping(uint256 => uint256) public expiryOf;

    /// @dev tokenId => admin suspension flag (overrides payment status).
    mapping(uint256 => bool) public suspended;

    /// @dev tokenId => IPFS metadata URI (pfp, background, socials, etc.).
    ///      Set at mint, updatable by token owner at any time.
    mapping(uint256 => string) private _tokenURIs;

    /// @dev owner address => tokenId. 0 means no identity minted.
    mapping(address => uint256) public tokenIdOf;

    // ── Events ───────────────────────────────────────────────────────────────

    event IdentityMinted(address indexed to, uint256 indexed tokenId, Period period, uint256 expiry);
    event IdentityRenewed(uint256 indexed tokenId, Period period, uint256 newExpiry);
    event MetadataUpdated(uint256 indexed tokenId, string uri);
    event Suspended(uint256 indexed tokenId);
    event Unsuspended(uint256 indexed tokenId);
    event TokenConfigSet(address indexed token, uint256 mintPrice, uint256 monthlyPrice, uint256 yearlyPrice);
    event TokenDisabled(address indexed token);
    event TreasuryUpdated(address indexed newTreasury);

    // ── Errors ───────────────────────────────────────────────────────────────

    error AlreadyHasIdentity();
    error NoIdentityFound();
    error NotTokenOwner();
    error SoulboundToken();
    error ZeroAddress();
    error TokenNotAccepted(address token);

    // ── Constructor ──────────────────────────────────────────────────────────

    /// @param _name           ERC-721 name.
    /// @param _symbol         ERC-721 symbol.
    /// @param _city           City / collection label stored on-chain (e.g. "Medellín").
    /// @param _treasury       Address that receives mint / renewal fees.
    /// @param _soulbound      If true, tokens are non-transferable.
    /// @param _initialTokens  Initial payment token configurations.
    constructor(
        string  memory _name,
        string  memory _symbol,
        string  memory _city,
        address        _treasury,
        bool           _soulbound,
        InitialTokenConfig[] memory _initialTokens
    ) ERC721(_name, _symbol) Ownable(msg.sender) {
        if (_treasury == address(0)) revert ZeroAddress();

        treasury     = _treasury;
        city         = _city;
        soulbound    = _soulbound;
        _nextTokenId = 1; // 0 reserved as "no identity"

        for (uint256 i = 0; i < _initialTokens.length; i++) {
            _setTokenConfig(_initialTokens[i]);
        }
    }

    // ── Minting ──────────────────────────────────────────────────────────────

    /// @notice Mint a new identity card. One per address. Requires token approval.
    /// @param metadataURI IPFS URI for the profile (pfp, background, socials, etc.).
    /// @param period      Monthly (30 days) or Yearly (365 days) — first active window.
    /// @param token       Accepted ERC-20 token address used for payment.
    /// @return tokenId    The newly minted token ID.
    function mint(string calldata metadataURI, Period period, address token)
        external
        whenNotPaused
        nonReentrant
        returns (uint256 tokenId)
    {
        if (tokenIdOf[msg.sender] != 0) revert AlreadyHasIdentity();

        TokenConfig memory cfg = tokenConfigs[token];
        if (!cfg.enabled) revert TokenNotAccepted(token);

        if (cfg.mintPrice > 0) {
            IERC20(token).safeTransferFrom(msg.sender, treasury, cfg.mintPrice);
        }

        tokenId = _nextTokenId++;
        tokenIdOf[msg.sender] = tokenId;

        uint256 expiry = block.timestamp + _periodDuration(period);
        createdAt[tokenId]  = block.timestamp;
        expiryOf[tokenId]   = expiry;
        _tokenURIs[tokenId] = metadataURI;

        _safeMint(msg.sender, tokenId);

        emit IdentityMinted(msg.sender, tokenId, period, expiry);
        emit MetadataUpdated(tokenId, metadataURI);
    }

    // ── Renewal ──────────────────────────────────────────────────────────────

    /// @notice Renew an identity card subscription.
    ///
    ///         Renewal rules:
    ///         - Still active  → extends from current expiry (paid days are preserved).
    ///         - Already expired → restarts from block.timestamp (no grace period).
    ///
    ///         Anyone can pay (e.g. a friend sponsors the renewal).
    ///         Token used for renewal may differ from the one used at mint.
    ///
    /// @param tokenId Token to renew.
    /// @param period  Monthly or Yearly.
    /// @param token   Accepted ERC-20 token address used for payment.
    function renew(uint256 tokenId, Period period, address token)
        external
        whenNotPaused
        nonReentrant
    {
        if (expiryOf[tokenId] == 0) revert NoIdentityFound();

        TokenConfig memory cfg = tokenConfigs[token];
        if (!cfg.enabled) revert TokenNotAccepted(token);

        uint256 price = period == Period.Monthly ? cfg.monthlyPrice : cfg.yearlyPrice;
        if (price > 0) {
            IERC20(token).safeTransferFrom(msg.sender, treasury, price);
        }

        // Extend from current expiry if still active; restart from now if expired.
        uint256 base = expiryOf[tokenId] > block.timestamp
            ? expiryOf[tokenId]
            : block.timestamp;

        uint256 newExpiry = base + _periodDuration(period);
        expiryOf[tokenId] = newExpiry;

        emit IdentityRenewed(tokenId, period, newExpiry);
    }

    // ── Metadata ─────────────────────────────────────────────────────────────

    /// @notice Update the IPFS metadata URI for your identity card.
    ///         Only the token owner can call this.
    /// @param tokenId Token to update.
    /// @param newURI  New IPFS URI (pfp, background, socials, etc.).
    function updateMetadata(uint256 tokenId, string calldata newURI) external {
        if (ownerOf(tokenId) != msg.sender) revert NotTokenOwner();
        _tokenURIs[tokenId] = newURI;
        emit MetadataUpdated(tokenId, newURI);
    }

    /// @dev ERC-721 tokenURI override — returns the stored per-token IPFS URI.
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        return _tokenURIs[tokenId];
    }

    // ── Views ────────────────────────────────────────────────────────────────

    /// @notice Derived status of a token.
    ///         Suspended overrides everything; Active requires non-expired expiry.
    function statusOf(uint256 tokenId) external view returns (Status) {
        if (suspended[tokenId])                    return Status.Suspended;
        if (expiryOf[tokenId] >= block.timestamp)  return Status.Active;
        return Status.Expired;
    }

    /// @notice Returns true if `user` has an active, non-suspended identity card.
    function isValid(address user) external view returns (bool) {
        uint256 tokenId = tokenIdOf[user];
        if (tokenId == 0)       return false;
        if (suspended[tokenId]) return false;
        return expiryOf[tokenId] >= block.timestamp;
    }

    /// @notice Returns the expiry timestamp for `user`'s identity (0 if none).
    function expiryOfUser(address user) external view returns (uint256) {
        return expiryOf[tokenIdOf[user]];
    }

    function totalSupply() external view returns (uint256) {
        return _nextTokenId - 1;
    }

    /// @notice Returns all accepted payment token addresses.
    function getAcceptedTokens() external view returns (address[] memory) {
        return _acceptedTokens;
    }

    // ── Admin ────────────────────────────────────────────────────────────────

    /// @notice Suspend a token immediately — blocks platform access regardless of payment.
    ///         Use for misbehaviour enforcement.
    function suspend(uint256 tokenId) external onlyOwner {
        if (expiryOf[tokenId] == 0) revert NoIdentityFound();
        suspended[tokenId] = true;
        emit Suspended(tokenId);
    }

    /// @notice Restore a previously suspended token.
    function unsuspend(uint256 tokenId) external onlyOwner {
        suspended[tokenId] = false;
        emit Unsuspended(tokenId);
    }

    /// @notice Add or update a payment token configuration.
    ///         Re-calling with the same token re-enables it (if previously disabled).
    function setTokenConfig(
        address token,
        uint256 mintPrice,
        uint256 monthlyPrice,
        uint256 yearlyPrice
    ) external onlyOwner {
        _setTokenConfig(InitialTokenConfig({
            token:        token,
            mintPrice:    mintPrice,
            monthlyPrice: monthlyPrice,
            yearlyPrice:  yearlyPrice
        }));
    }

    /// @notice Disable a payment token so it can no longer be used for mint/renew.
    function disableToken(address token) external onlyOwner {
        tokenConfigs[token].enabled = false;
        emit TokenDisabled(token);
    }

    function setTreasury(address newTreasury) external onlyOwner {
        if (newTreasury == address(0)) revert ZeroAddress();
        treasury = newTreasury;
        emit TreasuryUpdated(newTreasury);
    }

    function pause()   external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    // ── Internal ─────────────────────────────────────────────────────────────

    function _setTokenConfig(InitialTokenConfig memory cfg) internal {
        if (cfg.token == address(0)) revert ZeroAddress();

        tokenConfigs[cfg.token] = TokenConfig({
            mintPrice:    cfg.mintPrice,
            monthlyPrice: cfg.monthlyPrice,
            yearlyPrice:  cfg.yearlyPrice,
            enabled:      true
        });

        // Track address only if not already in the list.
        bool found = false;
        for (uint256 i = 0; i < _acceptedTokens.length; i++) {
            if (_acceptedTokens[i] == cfg.token) { found = true; break; }
        }
        if (!found) _acceptedTokens.push(cfg.token);

        emit TokenConfigSet(cfg.token, cfg.mintPrice, cfg.monthlyPrice, cfg.yearlyPrice);
    }

    function _periodDuration(Period period) internal pure returns (uint256) {
        return period == Period.Monthly ? MONTHLY_PERIOD : YEARLY_PERIOD;
    }

    // ── Soulbound enforcement ────────────────────────────────────────────────

    /// @dev Block transfers if soulbound. Minting (from==0) and burning (to==0) always allowed.
    function _update(address to, uint256 tokenId, address auth)
        internal
        override
        returns (address)
    {
        address from = _ownerOf(tokenId);
        if (soulbound && from != address(0) && to != address(0)) {
            revert SoulboundToken();
        }

        // Sync tokenIdOf on transfer (non-soulbound path)
        if (from != address(0) && to != address(0)) {
            tokenIdOf[from] = 0;
            tokenIdOf[to]   = tokenId;
        }
        // On burn, clear the mapping
        if (to == address(0)) {
            tokenIdOf[from] = 0;
        }

        return super._update(to, tokenId, auth);
    }
}
