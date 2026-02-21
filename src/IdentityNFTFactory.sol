// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IdentityNFT} from "./IdentityNFT.sol";

/// @title IdentityNFTFactory
/// @notice Deploys IdentityNFT city collections from a frontend wallet.
///         Only the protocol admin (owner) can deploy new collections.
///         Each deployed collection's ownership is immediately transferred to
///         factory.owner() so the admin can manage collections directly.
contract IdentityNFTFactory is Ownable {
    address[] public allCollections;
    mapping(address => bool) public isCollection;

    event CollectionDeployed(
        address indexed collection,
        string name,
        string symbol,
        string city,
        address indexed treasury
    );

    constructor() Ownable(msg.sender) {}

    /// @notice Deploy a new IdentityNFT city collection.
    ///         Ownership is transferred to factory.owner() immediately after deployment
    ///         so the protocol admin can call admin functions directly on each collection.
    function deployCollection(
        string memory name,
        string memory symbol,
        string memory city,
        address treasury,
        bool soulbound,
        IdentityNFT.InitialTokenConfig[] memory initialTokens
    ) external onlyOwner returns (address collection) {
        IdentityNFT nft = new IdentityNFT(
            name, symbol, city, treasury, soulbound, initialTokens
        );
        // factory is msg.sender → owns the nft; transfer to factory owner
        nft.transferOwnership(owner());

        collection = address(nft);
        allCollections.push(collection);
        isCollection[collection] = true;

        emit CollectionDeployed(collection, name, symbol, city, treasury);
    }

    function getAllCollections() external view returns (address[] memory) {
        return allCollections;
    }

    function getCollectionCount() external view returns (uint256) {
        return allCollections.length;
    }
}
