// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script, console} from "forge-std/Script.sol";
import {VaultFactory} from "../src/challenges/VaultFactory.sol";

/// @notice Deploys the VaultFactory contract.
///         Deploy IdentityNFT first and set IDENTITY_NFT in .env.
///
/// Required env vars:
///   PRIVATE_KEY          – deployer private key
///   ACCEPTED_TOKEN_1     – first whitelisted token address (e.g. 1UP)
///   RESOLVER_ADDRESS     – address that resolves disputed challenges
///   IDENTITY_NFT         – deployed IdentityNFT address
///
/// Optional env vars:
///   ACCEPTED_TOKEN_2     – second whitelisted token (e.g. USDC)
///   ACCEPTED_TOKEN_3     – third whitelisted token (e.g. EUROC)
///
/// Verification (choose one at CLI):
///   --verifier etherscan  --etherscan-api-key $BASESCAN_API_KEY
///   --verifier blockscout --verifier-url https://base-sepolia.blockscout.com/api/
///   --verifier sourcify
contract DeployVaultFactory is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address resolver    = vm.envAddress("RESOLVER_ADDRESS");
        address identityNFT = vm.envAddress("IDENTITY_NFT");

        // ── Build token whitelist ─────────────────────────────────────────────
        address token1 = vm.envAddress("ACCEPTED_TOKEN_1");
        address token2 = vm.envOr("ACCEPTED_TOKEN_2", address(0));
        address token3 = vm.envOr("ACCEPTED_TOKEN_3", address(0));

        uint256 tokenCount = 1;
        if (token2 != address(0)) tokenCount++;
        if (token3 != address(0)) tokenCount++;

        address[] memory tokens = new address[](tokenCount);
        tokens[0] = token1;
        if (token2 != address(0)) tokens[1] = token2;
        if (token3 != address(0)) tokens[2] = token3;

        // ── Deploy ────────────────────────────────────────────────────────────
        vm.startBroadcast(deployerKey);

        VaultFactory factory = new VaultFactory(tokens, resolver, identityNFT);

        vm.stopBroadcast();

        // ── Logs ──────────────────────────────────────────────────────────────
        console.log("=== VaultFactory Deployed ===");
        console.log("Address:       ", address(factory));
        console.log("Resolver:      ", resolver);
        console.log("IdentityNFT:   ", identityNFT);
        console.log("Accepted token 1: ", token1);
        if (token2 != address(0)) console.log("Accepted token 2: ", token2);
        if (token3 != address(0)) console.log("Accepted token 3: ", token3);
        console.log("");
        console.log("Next step: set VAULT_FACTORY_ADDRESS=", address(factory), "in .env");
    }
}
