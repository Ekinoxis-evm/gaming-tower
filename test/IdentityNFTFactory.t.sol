// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import "../src/IdentityNFTFactory.sol";
import "../src/IdentityNFT.sol";
import "./mocks/MockERC20.sol";

contract IdentityNFTFactoryTest is Test {
    IdentityNFTFactory public factory;
    MockERC20          public oneUp;

    address admin    = makeAddr("admin");
    address treasury = makeAddr("treasury");
    address user1    = makeAddr("user1");
    address nonOwner = makeAddr("nonOwner");

    uint256 constant MINT_PRICE    = 50e18;
    uint256 constant MONTHLY_PRICE = 20e18;
    uint256 constant YEARLY_PRICE  = 200e18;

    function setUp() public {
        oneUp = new MockERC20();

        vm.prank(admin);
        factory = new IdentityNFTFactory();
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    function _buildTokens() internal view returns (IdentityNFT.InitialTokenConfig[] memory tokens) {
        tokens = new IdentityNFT.InitialTokenConfig[](1);
        tokens[0] = IdentityNFT.InitialTokenConfig({
            token:        address(oneUp),
            mintPrice:    MINT_PRICE,
            monthlyPrice: MONTHLY_PRICE,
            yearlyPrice:  YEARLY_PRICE
        });
    }

    // ── Tests ─────────────────────────────────────────────────────────────────

    function testDeployCollection() public {
        vm.prank(admin);
        address collection = factory.deployCollection(
            "Gaming Identity - Medellin",
            "GIM",
            "Medellin",
            treasury,
            false,
            _buildTokens()
        );

        assertTrue(factory.isCollection(collection));
        assertEq(factory.getCollectionCount(), 1);
        assertEq(factory.allCollections(0), collection);

        IdentityNFT nft = IdentityNFT(collection);
        assertEq(nft.name(),   "Gaming Identity - Medellin");
        assertEq(nft.symbol(), "GIM");
        assertEq(nft.city(),   "Medellin");
    }

    function testCollectionOwnerIsFactoryOwner() public {
        vm.prank(admin);
        address collection = factory.deployCollection(
            "Gaming Identity - Bogota",
            "GIB",
            "Bogota",
            treasury,
            false,
            _buildTokens()
        );

        IdentityNFT nft = IdentityNFT(collection);
        // Owner must be admin (factory.owner()), NOT the factory address itself
        assertEq(nft.owner(), admin);
        assertTrue(nft.owner() != address(factory));
    }

    function testDeployMultipleCollections() public {
        vm.startPrank(admin);
        address col1 = factory.deployCollection(
            "Gaming Identity - Medellin", "GIM", "Medellin", treasury, false, _buildTokens()
        );
        address col2 = factory.deployCollection(
            "Gaming Identity - Bogota", "GIB", "Bogota", treasury, false, _buildTokens()
        );
        vm.stopPrank();

        assertEq(factory.getCollectionCount(), 2);

        address[] memory all = factory.getAllCollections();
        assertEq(all.length, 2);
        assertEq(all[0], col1);
        assertEq(all[1], col2);

        assertTrue(factory.isCollection(col1));
        assertTrue(factory.isCollection(col2));
    }

    function testCollectionIsFullyFunctional() public {
        vm.prank(admin);
        address collection = factory.deployCollection(
            "Gaming Identity - Cali",
            "GIC",
            "Cali",
            treasury,
            false,
            _buildTokens()
        );

        IdentityNFT nft = IdentityNFT(collection);

        // Admin can call admin functions directly on the collection
        address usdc = makeAddr("usdc");
        vm.prank(admin);
        nft.setTokenConfig(usdc, 50e6, 20e6, 200e6);

        // Users can mint
        oneUp.mint(user1, MINT_PRICE);
        vm.prank(user1);
        oneUp.approve(collection, MINT_PRICE);
        vm.prank(user1);
        uint256 tokenId = nft.mint("ipfs://profile", IdentityNFT.Period.Monthly, address(oneUp));

        assertEq(tokenId, 1);
        assertTrue(nft.isValid(user1));
        assertEq(nft.totalSupply(), 1);
    }

    function testEmitCollectionDeployed() public {
        IdentityNFT.InitialTokenConfig[] memory tokens = _buildTokens();

        vm.prank(admin);
        // We can't predict address ahead of time, so just check non-indexed fields + partial match
        vm.expectEmit(false, true, false, true);
        emit IdentityNFTFactory.CollectionDeployed(
            address(0), // collection — unknown, use false for indexed check
            "Gaming Identity - Pereira",
            "GIP",
            "Pereira",
            treasury
        );

        factory.deployCollection(
            "Gaming Identity - Pereira",
            "GIP",
            "Pereira",
            treasury,
            false,
            tokens
        );
    }

    function testRevertDeployCollectionNonOwner() public {
        vm.expectRevert();
        vm.prank(nonOwner);
        factory.deployCollection(
            "Gaming Identity - Cali",
            "GIC",
            "Cali",
            treasury,
            false,
            _buildTokens()
        );
    }

    function testRevertDeployCollectionZeroTreasury() public {
        vm.expectRevert(IdentityNFT.ZeroAddress.selector);
        vm.prank(admin);
        factory.deployCollection(
            "Gaming Identity - Cali",
            "GIC",
            "Cali",
            address(0), // zero treasury — IdentityNFT constructor reverts
            false,
            _buildTokens()
        );
    }
}
