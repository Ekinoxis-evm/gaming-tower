// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/// @dev Minimal interface used by ChallengeVault and VaultFactory to gate
///      challenge creation and joining on an active IdentityNFT.
interface IIdentityNFT {
    function isValid(address user) external view returns (bool);
}
