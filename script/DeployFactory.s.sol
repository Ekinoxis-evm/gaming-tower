// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script, console} from "forge-std/Script.sol";
import {CourseFactory} from "../src/courses/CourseFactory.sol";

/// @notice Deploys the CourseFactory contract.
///         Courses are priced in ETH — no payment token required here.
///
/// Required env vars:
///   PRIVATE_KEY        – deployer private key
///   DEFAULT_TREASURY   – default address that receives ETH course proceeds
///
/// Verification (choose one at CLI):
///   --verifier etherscan  --etherscan-api-key $BASESCAN_API_KEY
///   --verifier blockscout --verifier-url https://base-sepolia.blockscout.com/api/
///   --verifier sourcify
contract DeployFactory is Script {
    function run() external {
        uint256 deployerKey    = vm.envUint("PRIVATE_KEY");
        address defaultTreasury = vm.envAddress("DEFAULT_TREASURY");

        vm.startBroadcast(deployerKey);

        CourseFactory factory = new CourseFactory(defaultTreasury);

        vm.stopBroadcast();

        console.log("=== CourseFactory Deployed ===");
        console.log("Address:          ", address(factory));
        console.log("Default treasury: ", defaultTreasury);
        console.log("");
        console.log("Next step: set FACTORY_ADDRESS=", address(factory), "in .env");
    }
}
