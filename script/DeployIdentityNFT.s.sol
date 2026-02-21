// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script, console} from "forge-std/Script.sol";
import {IdentityNFT} from "../src/IdentityNFT.sol";

/// @notice Deploys an IdentityNFT collection.
///         Each city / collection is an independent deployment.
///
/// Required env vars:
///   PRIVATE_KEY              – deployer private key
///   IDENTITY_NAME            – ERC-721 name  (e.g. "Entry - Medellín")
///   IDENTITY_SYMBOL          – ERC-721 symbol (e.g. "EMDE")
///   IDENTITY_CITY            – city label stored on-chain (e.g. "Medellín")
///   DEFAULT_TREASURY         – address that receives mint and renewal fees
///   TOKEN_1                  – first accepted payment token address
///   TOKEN_1_MINT_PRICE       – one-time card creation fee in token wei
///   TOKEN_1_MONTHLY_PRICE    – 30-day renewal fee in token wei
///   TOKEN_1_YEARLY_PRICE     – 365-day renewal fee in token wei
///
/// Optional env vars:
///   IDENTITY_SOULBOUND       – true to make cards non-transferable (default: false)
///   TOKEN_2                  – second accepted payment token (e.g. USDC)
///   TOKEN_2_MINT_PRICE       – mint price for TOKEN_2
///   TOKEN_2_MONTHLY_PRICE    – monthly price for TOKEN_2
///   TOKEN_2_YEARLY_PRICE     – yearly price for TOKEN_2
///
/// Verification (choose one at CLI):
///   --verifier etherscan  --etherscan-api-key $BASESCAN_API_KEY
///   --verifier blockscout --verifier-url https://base-sepolia.blockscout.com/api/
///   --verifier sourcify
contract DeployIdentityNFT is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        string  memory name     = vm.envString("IDENTITY_NAME");
        string  memory symbol   = vm.envString("IDENTITY_SYMBOL");
        string  memory city     = vm.envString("IDENTITY_CITY");
        address treasury        = vm.envAddress("DEFAULT_TREASURY");
        bool    soulbound       = vm.envOr("IDENTITY_SOULBOUND", false);

        // ── Token 1 (required) ───────────────────────────────────────────────
        address token1           = vm.envAddress("TOKEN_1");
        uint256 token1MintPrice  = vm.envUint("TOKEN_1_MINT_PRICE");
        uint256 token1Monthly    = vm.envUint("TOKEN_1_MONTHLY_PRICE");
        uint256 token1Yearly     = vm.envUint("TOKEN_1_YEARLY_PRICE");

        // ── Token 2 (optional) ───────────────────────────────────────────────
        address token2 = vm.envOr("TOKEN_2", address(0));
        uint256 token2MintPrice;
        uint256 token2Monthly;
        uint256 token2Yearly;
        if (token2 != address(0)) {
            token2MintPrice = vm.envUint("TOKEN_2_MINT_PRICE");
            token2Monthly   = vm.envUint("TOKEN_2_MONTHLY_PRICE");
            token2Yearly    = vm.envUint("TOKEN_2_YEARLY_PRICE");
        }

        // ── Build InitialTokenConfig array ───────────────────────────────────
        uint256 tokenCount = token2 != address(0) ? 2 : 1;
        IdentityNFT.InitialTokenConfig[] memory tokens =
            new IdentityNFT.InitialTokenConfig[](tokenCount);

        tokens[0] = IdentityNFT.InitialTokenConfig({
            token:        token1,
            mintPrice:    token1MintPrice,
            monthlyPrice: token1Monthly,
            yearlyPrice:  token1Yearly
        });

        if (token2 != address(0)) {
            tokens[1] = IdentityNFT.InitialTokenConfig({
                token:        token2,
                mintPrice:    token2MintPrice,
                monthlyPrice: token2Monthly,
                yearlyPrice:  token2Yearly
            });
        }

        // ── Deploy ───────────────────────────────────────────────────────────
        vm.startBroadcast(deployerKey);

        IdentityNFT nft = new IdentityNFT(
            name,
            symbol,
            city,
            treasury,
            soulbound,
            tokens
        );

        vm.stopBroadcast();

        // ── Logs ─────────────────────────────────────────────────────────────
        console.log("=== IdentityNFT Deployed ===");
        console.log("Address:          ", address(nft));
        console.log("Name:             ", name);
        console.log("Symbol:           ", symbol);
        console.log("City:             ", city);
        console.log("Treasury:         ", treasury);
        console.log("Soulbound:        ", soulbound);
        console.log("--- Token 1 ---");
        console.log("Address:          ", token1);
        console.log("Mint price (wei): ", token1MintPrice);
        console.log("Monthly (wei):    ", token1Monthly);
        console.log("Yearly (wei):     ", token1Yearly);
        if (token2 != address(0)) {
            console.log("--- Token 2 ---");
            console.log("Address:          ", token2);
            console.log("Mint price (wei): ", token2MintPrice);
            console.log("Monthly (wei):    ", token2Monthly);
            console.log("Yearly (wei):     ", token2Yearly);
        }
        console.log("");
        console.log("Next step: set IDENTITY_NFT=", address(nft), "in .env, then deploy VaultFactory");
    }
}
