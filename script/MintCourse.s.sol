// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script, console} from "forge-std/Script.sol";
import {CourseFactory} from "../src/courses/CourseFactory.sol";

/// @notice Creates a new CourseNFT via CourseFactory.
///
/// Required env vars:
///   PRIVATE_KEY           – creator private key
///   FACTORY_ADDRESS       – deployed CourseFactory address
///   COURSE_NAME           – ERC-721 name  (e.g. "Python 101")
///   COURSE_SYMBOL         – ERC-721 symbol (e.g. "PY101")
///   MINT_PRICE            – price per NFT in wei (ETH)
///   MAX_SUPPLY            – max tokens (0 = unlimited)
///   BASE_URI              – public IPFS metadata URI
///   PRIVATE_CONTENT_URI   – token-gated IPFS content URI
///
/// Optional env vars:
///   TREASURY_ADDRESS      – override DEFAULT_TREASURY for this course (default: address(0) → uses factory default)
///   ROYALTY_FEE_BPS       – royalty in basis points (default: 500 = 5%)
contract CreateCourse is Script {
    function run() external {
        uint256 creatorKey   = vm.envUint("PRIVATE_KEY");
        address factoryAddr  = vm.envAddress("FACTORY_ADDRESS");

        string  memory name             = vm.envString("COURSE_NAME");
        string  memory symbol           = vm.envString("COURSE_SYMBOL");
        uint256        mintPrice        = vm.envUint("MINT_PRICE");
        uint256        maxSupply        = vm.envUint("MAX_SUPPLY");
        string  memory baseURI          = vm.envString("BASE_URI");
        string  memory privateContentURI = vm.envString("PRIVATE_CONTENT_URI");
        address        treasury         = vm.envOr("TREASURY_ADDRESS", address(0));
        uint96         royaltyFeeBps    = uint96(vm.envOr("ROYALTY_FEE_BPS", uint256(500)));

        CourseFactory factory = CourseFactory(factoryAddr);

        vm.startBroadcast(creatorKey);

        address courseAddress = factory.createCourse(
            name,
            symbol,
            mintPrice,
            maxSupply,
            baseURI,
            privateContentURI,
            treasury,
            royaltyFeeBps
        );

        vm.stopBroadcast();

        console.log("=== CourseNFT Created ===");
        console.log("Course address: ", courseAddress);
        console.log("Name:           ", name);
        console.log("Symbol:         ", symbol);
        console.log("Mint price:     ", mintPrice);
        console.log("Max supply:     ", maxSupply);
        console.log("Royalty bps:    ", royaltyFeeBps);
    }
}
