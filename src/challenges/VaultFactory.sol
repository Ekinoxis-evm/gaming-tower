// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ChallengeVault} from "./ChallengeVault.sol";
import {IIdentityNFT} from "./IIdentityNFT.sol";

/// @title VaultFactory
/// @notice Deploys and tracks ChallengeVault contracts.
///         Accepts a whitelist of ERC-20 tokens as staking assets.
///         Callers must hold a valid (active, non-suspended) IdentityNFT to
///         create a challenge. Player2 identity is verified at deposit time
///         inside ChallengeVault.
contract VaultFactory is Ownable, Pausable {
    using EnumerableSet for EnumerableSet.AddressSet;

    // ── Storage ──────────────────────────────────────────────────────────────

    IIdentityNFT public immutable identityNFT;
    address      public resolver;

    EnumerableSet.AddressSet private _acceptedTokens;

    address[] public allVaults;
    mapping(address => bool)      public isVault;
    mapping(address => address[]) public vaultsByCreator;

    // ── Events ───────────────────────────────────────────────────────────────

    event VaultCreated(
        address indexed vault,
        address indexed creator,
        address indexed token,
        uint256 stakeAmount,
        uint256 duration,
        string  metadataURI
    );
    event ResolverUpdated(address indexed newResolver);
    event TokenWhitelisted(address indexed token);
    event TokenRemovedFromWhitelist(address indexed token);

    // ── Errors ───────────────────────────────────────────────────────────────

    error ZeroAddress();
    error ZeroStake();
    error ZeroDuration();
    error NoActiveIdentity();
    error TokenNotAccepted(address token);

    // ── Constructor ──────────────────────────────────────────────────────────

    /// @param _initialTokens  Initial whitelist of accepted ERC-20 token addresses.
    /// @param _resolver        Default resolver for dispute resolution.
    /// @param _identityNFT     IdentityNFT contract — callers must pass isValid().
    constructor(address[] memory _initialTokens, address _resolver, address _identityNFT)
        Ownable(msg.sender)
    {
        if (_resolver    == address(0)) revert ZeroAddress();
        if (_identityNFT == address(0)) revert ZeroAddress();

        resolver    = _resolver;
        identityNFT = IIdentityNFT(_identityNFT);

        for (uint256 i = 0; i < _initialTokens.length; i++) {
            if (_initialTokens[i] == address(0)) revert ZeroAddress();
            _acceptedTokens.add(_initialTokens[i]);
            emit TokenWhitelisted(_initialTokens[i]);
        }
    }

    // ── Core ─────────────────────────────────────────────────────────────────

    /// @notice Deploy a new ChallengeVault.
    ///         Caller must have an active, non-suspended IdentityNFT.
    ///         Caller becomes player1 and must separately approve + deposit
    ///         to the returned vault address.
    /// @param token        Whitelisted ERC-20 token for staking.
    /// @param stakeAmount  Tokens each player must stake (token wei).
    /// @param duration     Challenge duration in seconds.
    /// @param metadataURI  IPFS URI describing the challenge.
    /// @return vault Address of the newly deployed ChallengeVault.
    function createChallenge(
        address  token,
        uint256  stakeAmount,
        uint256  duration,
        string   calldata metadataURI
    ) external whenNotPaused returns (address vault) {
        if (!_acceptedTokens.contains(token)) revert TokenNotAccepted(token);
        if (!identityNFT.isValid(msg.sender)) revert NoActiveIdentity();
        if (stakeAmount == 0) revert ZeroStake();
        if (duration    == 0) revert ZeroDuration();

        ChallengeVault v = new ChallengeVault(
            IERC20(token),
            stakeAmount,
            duration,
            metadataURI,
            resolver,
            msg.sender,
            address(identityNFT)
        );

        vault = address(v);
        allVaults.push(vault);
        isVault[vault] = true;
        vaultsByCreator[msg.sender].push(vault);

        emit VaultCreated(vault, msg.sender, token, stakeAmount, duration, metadataURI);
    }

    // ── Views ─────────────────────────────────────────────────────────────────

    function getAllVaults() external view returns (address[] memory) {
        return allVaults;
    }

    function getVaultsByCreator(address creator) external view returns (address[] memory) {
        return vaultsByCreator[creator];
    }

    function getVaultCount() external view returns (uint256) {
        return allVaults.length;
    }

    function isAcceptedToken(address token) external view returns (bool) {
        return _acceptedTokens.contains(token);
    }

    function getAcceptedTokens() external view returns (address[] memory) {
        return _acceptedTokens.values();
    }

    // ── Admin ─────────────────────────────────────────────────────────────────

    function whitelistToken(address token) external onlyOwner {
        if (token == address(0)) revert ZeroAddress();
        _acceptedTokens.add(token);
        emit TokenWhitelisted(token);
    }

    function removeToken(address token) external onlyOwner {
        _acceptedTokens.remove(token);
        emit TokenRemovedFromWhitelist(token);
    }

    function setResolver(address _resolver) external onlyOwner {
        if (_resolver == address(0)) revert ZeroAddress();
        resolver = _resolver;
        emit ResolverUpdated(_resolver);
    }

    function pause()   external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }
}
