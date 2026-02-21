// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/// @dev Minimal IdentityNFT mock for tests.
///      Call setValid(user, true/false) to control isValid() responses.
contract MockIdentityNFT {
    mapping(address => bool) private _valid;

    function setValid(address user, bool valid) external {
        _valid[user] = valid;
    }

    function isValid(address user) external view returns (bool) {
        return _valid[user];
    }
}
