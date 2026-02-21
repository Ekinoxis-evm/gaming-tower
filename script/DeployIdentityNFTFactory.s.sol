// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script, console} from "forge-std/Script.sol";
import {IdentityNFTFactory} from "../src/IdentityNFTFactory.sol";

/// @notice Deploys the IdentityNFTFactory.
///         Deployed once by the protocol admin. Non-technical admins can then
///         call deployCollection() from a frontend wallet to spin up city collections.
///
/// Required env vars:
///   PRIVATE_KEY  – deployer / protocol admin private key
///
/// Verification (choose one at CLI):
///   --verifier etherscan  --etherscan-api-key $BASESCAN_API_KEY
///   --verifier blockscout --verifier-url https://base-sepolia.blockscout.com/api/
///   --verifier sourcify
contract DeployIdentityNFTFactory is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerKey);

        IdentityNFTFactory factory = new IdentityNFTFactory();

        vm.stopBroadcast();

        console.log("=== IdentityNFTFactory Deployed ===");
        console.log("Address: ", address(factory));
        console.log("Owner:   ", factory.owner());
        console.log("");
        console.log("Next step: set IDENTITY_NFT_FACTORY=", address(factory), "in .env");
    }
}
