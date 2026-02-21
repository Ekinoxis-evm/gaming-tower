// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import "../src/IdentityNFT.sol";
import "./mocks/MockERC20.sol";

contract IdentityNFTTest is Test {
    MockERC20   public oneUp;
    MockERC20   public usdc;
    IdentityNFT public identity;

    address admin    = makeAddr("admin");
    address treasury = makeAddr("treasury");
    address user1    = makeAddr("user1");
    address user2    = makeAddr("user2");

    uint256 constant MINT_PRICE    = 50e18;
    uint256 constant MONTHLY_PRICE = 20e18;
    uint256 constant YEARLY_PRICE  = 200e18;

    // USDC uses 6 decimals
    uint256 constant USDC_MINT_PRICE    = 50e6;
    uint256 constant USDC_MONTHLY_PRICE = 20e6;
    uint256 constant USDC_YEARLY_PRICE  = 200e6;

    function setUp() public {
        oneUp = new MockERC20();
        usdc  = new MockERC20();

        IdentityNFT.InitialTokenConfig[] memory tokens = new IdentityNFT.InitialTokenConfig[](1);
        tokens[0] = IdentityNFT.InitialTokenConfig({
            token:        address(oneUp),
            mintPrice:    MINT_PRICE,
            monthlyPrice: MONTHLY_PRICE,
            yearlyPrice:  YEARLY_PRICE
        });

        vm.prank(admin);
        identity = new IdentityNFT(
            "Gaming Identity",
            "GID",
            "Global",
            treasury,
            false, // not soulbound by default
            tokens
        );

        oneUp.mint(user1, 10_000e18);
        oneUp.mint(user2, 10_000e18);
    }

    // ── Initialization ────────────────────────────────────────────────────────

    function testInitialization() public view {
        assertEq(identity.name(),           "Gaming Identity");
        assertEq(identity.symbol(),         "GID");
        assertEq(identity.city(),           "Global");
        assertEq(identity.treasury(),       treasury);
        assertEq(identity.soulbound(),      false);
        assertEq(identity.totalSupply(),    0);
        assertEq(identity.MONTHLY_PERIOD(), 30 days);
        assertEq(identity.YEARLY_PERIOD(),  365 days);

        (uint256 mp, uint256 mop, uint256 yp, bool en) =
            _tokenConfig(address(oneUp));
        assertEq(mp,  MINT_PRICE);
        assertEq(mop, MONTHLY_PRICE);
        assertEq(yp,  YEARLY_PRICE);
        assertTrue(en);
    }

    // ── Minting — Monthly ─────────────────────────────────────────────────────

    function testMintMonthly() public {
        uint256 tokenId = _mintMonthly(user1);

        assertEq(tokenId,                     1);
        assertEq(identity.ownerOf(tokenId),   user1);
        assertEq(identity.tokenIdOf(user1),   1);
        assertEq(identity.totalSupply(),       1);
        assertEq(oneUp.balanceOf(treasury),    MINT_PRICE);
        assertEq(identity.createdAt(tokenId),  block.timestamp);
        assertEq(identity.expiryOf(tokenId),   block.timestamp + 30 days);
    }

    function testMintMonthlyTokenURI() public {
        uint256 tokenId = _mintMonthly(user1);
        assertEq(identity.tokenURI(tokenId), "ipfs://profile");
    }

    function testMintMonthlyIsValid() public {
        _mintMonthly(user1);
        assertTrue(identity.isValid(user1));
    }

    function testMintMonthlyStatusActive() public {
        uint256 tokenId = _mintMonthly(user1);
        assertEq(uint8(identity.statusOf(tokenId)), uint8(IdentityNFT.Status.Active));
    }

    // ── Minting — Yearly ──────────────────────────────────────────────────────

    function testMintYearly() public {
        uint256 tokenId = _mintYearly(user1);

        assertEq(identity.expiryOf(tokenId),  block.timestamp + 365 days);
        assertEq(identity.createdAt(tokenId), block.timestamp);
        assertEq(oneUp.balanceOf(treasury),   MINT_PRICE);
    }

    function testMintYearlyIsValid() public {
        _mintYearly(user1);
        assertTrue(identity.isValid(user1));
    }

    // ── Minting — General ─────────────────────────────────────────────────────

    function testIsInvalidWithoutMint() public view {
        assertFalse(identity.isValid(user1));
    }

    function testCreatedAtIsImmutable() public {
        uint256 tokenId = _mintMonthly(user1);
        uint256 created = identity.createdAt(tokenId);

        // Renew should NOT change createdAt
        vm.warp(block.timestamp + 15 days);
        _renewMonthly(user1, tokenId);

        assertEq(identity.createdAt(tokenId), created);
    }

    function testRevertDoubleMin() public {
        _mintMonthly(user1);

        vm.prank(user1);
        oneUp.approve(address(identity), MINT_PRICE);

        vm.expectRevert(IdentityNFT.AlreadyHasIdentity.selector);
        vm.prank(user1);
        identity.mint("ipfs://profile2", IdentityNFT.Period.Monthly, address(oneUp));
    }

    function testEmitIdentityMinted() public {
        vm.prank(user1);
        oneUp.approve(address(identity), MINT_PRICE);

        vm.expectEmit(true, true, false, true);
        emit IdentityNFT.IdentityMinted(user1, 1, IdentityNFT.Period.Monthly, block.timestamp + 30 days);

        vm.prank(user1);
        identity.mint("ipfs://profile", IdentityNFT.Period.Monthly, address(oneUp));
    }

    function testRevertMintWhenPaused() public {
        vm.prank(admin);
        identity.pause();

        vm.prank(user1);
        oneUp.approve(address(identity), MINT_PRICE);

        vm.expectRevert();
        vm.prank(user1);
        identity.mint("ipfs://profile", IdentityNFT.Period.Monthly, address(oneUp));
    }

    // ── Multi-token minting ───────────────────────────────────────────────────

    function testMintWithUsdcToken() public {
        // Add USDC config (6 decimals)
        vm.prank(admin);
        identity.setTokenConfig(address(usdc), USDC_MINT_PRICE, USDC_MONTHLY_PRICE, USDC_YEARLY_PRICE);

        usdc.mint(user1, 1_000e6);

        uint256 treasuryUsdcBefore = usdc.balanceOf(treasury);

        vm.prank(user1);
        usdc.approve(address(identity), USDC_MINT_PRICE);
        vm.prank(user1);
        identity.mint("ipfs://profile", IdentityNFT.Period.Monthly, address(usdc));

        assertEq(usdc.balanceOf(treasury), treasuryUsdcBefore + USDC_MINT_PRICE);
        assertTrue(identity.isValid(user1));
    }

    function testRevertMintWithUnacceptedToken() public {
        address fakeToken = makeAddr("fakeToken");

        vm.expectRevert(abi.encodeWithSelector(IdentityNFT.TokenNotAccepted.selector, fakeToken));
        vm.prank(user1);
        identity.mint("ipfs://profile", IdentityNFT.Period.Monthly, fakeToken);
    }

    function testRevertMintWithDisabledToken() public {
        vm.prank(admin);
        identity.disableToken(address(oneUp));

        vm.prank(user1);
        oneUp.approve(address(identity), MINT_PRICE);

        vm.expectRevert(abi.encodeWithSelector(IdentityNFT.TokenNotAccepted.selector, address(oneUp)));
        vm.prank(user1);
        identity.mint("ipfs://profile", IdentityNFT.Period.Monthly, address(oneUp));
    }

    // ── Renewal — Monthly ─────────────────────────────────────────────────────

    function testRenewMonthlyExtendsFromExpiry() public {
        uint256 tokenId = _mintMonthly(user1);
        uint256 originalExpiry = identity.expiryOf(tokenId);

        // Renew early (still active) — extends without gap
        _renewMonthly(user1, tokenId);

        assertEq(identity.expiryOf(tokenId), originalExpiry + 30 days);
    }

    function testRenewMonthlyTransfersCost() public {
        uint256 tokenId = _mintMonthly(user1);
        uint256 balBefore = oneUp.balanceOf(treasury);

        _renewMonthly(user1, tokenId);

        assertEq(oneUp.balanceOf(treasury), balBefore + MONTHLY_PRICE);
    }

    function testRenewMonthlyAfterExpiry() public {
        uint256 tokenId = _mintMonthly(user1);

        // Warp past expiry
        vm.warp(block.timestamp + 31 days);
        assertFalse(identity.isValid(user1));

        _renewMonthly(user1, tokenId);

        // Fresh start from block.timestamp — no grace, no backward extension
        assertEq(identity.expiryOf(tokenId), block.timestamp + 30 days);
        assertTrue(identity.isValid(user1));
    }

    // ── Renewal — Yearly ──────────────────────────────────────────────────────

    function testRenewYearlyExtendsFromExpiry() public {
        uint256 tokenId = _mintMonthly(user1);
        uint256 originalExpiry = identity.expiryOf(tokenId);

        _renewYearly(user1, tokenId);

        assertEq(identity.expiryOf(tokenId), originalExpiry + 365 days);
    }

    function testRenewYearlyTransfersCost() public {
        uint256 tokenId = _mintMonthly(user1);
        uint256 balBefore = oneUp.balanceOf(treasury);

        _renewYearly(user1, tokenId);

        assertEq(oneUp.balanceOf(treasury), balBefore + YEARLY_PRICE);
    }

    function testRenewYearlyAfterExpiry() public {
        uint256 tokenId = _mintMonthly(user1);

        vm.warp(block.timestamp + 31 days);

        _renewYearly(user1, tokenId);

        assertEq(identity.expiryOf(tokenId), block.timestamp + 365 days);
        assertTrue(identity.isValid(user1));
    }

    // ── Renewal with different token ──────────────────────────────────────────

    function testRenewWithDifferentTokenThanMint() public {
        // Add USDC config
        vm.prank(admin);
        identity.setTokenConfig(address(usdc), USDC_MINT_PRICE, USDC_MONTHLY_PRICE, USDC_YEARLY_PRICE);

        uint256 tokenId = _mintMonthly(user1); // minted with oneUp
        uint256 originalExpiry = identity.expiryOf(tokenId);

        usdc.mint(user1, 1_000e6);
        vm.prank(user1);
        usdc.approve(address(identity), USDC_MONTHLY_PRICE);
        vm.prank(user1);
        identity.renew(tokenId, IdentityNFT.Period.Monthly, address(usdc)); // renew with usdc

        assertEq(identity.expiryOf(tokenId), originalExpiry + 30 days);
        assertTrue(identity.isValid(user1));
        assertEq(usdc.balanceOf(treasury), USDC_MONTHLY_PRICE);
    }

    // ── No grace period ───────────────────────────────────────────────────────

    function testExpiredIsInvalidImmediately() public {
        uint256 tokenId = _mintMonthly(user1);
        vm.warp(block.timestamp + 30 days + 1);

        assertFalse(identity.isValid(user1));
        assertEq(uint8(identity.statusOf(tokenId)), uint8(IdentityNFT.Status.Expired));
    }

    function testRenewAfterExpiryDoesNotBackfill() public {
        uint256 tokenId = _mintMonthly(user1);

        // Expire and wait extra days
        vm.warp(block.timestamp + 60 days);

        _renewMonthly(user1, tokenId);

        // New expiry = now + 30 days, NOT original expiry + 30 days
        assertEq(identity.expiryOf(tokenId), block.timestamp + 30 days);
    }

    // ── Renewal — Sponsorship ─────────────────────────────────────────────────

    function testUser2SponsorRenewalForUser1() public {
        uint256 tokenId = _mintMonthly(user1);
        uint256 originalExpiry = identity.expiryOf(tokenId);

        vm.prank(user2);
        oneUp.approve(address(identity), MONTHLY_PRICE);
        vm.prank(user2);
        identity.renew(tokenId, IdentityNFT.Period.Monthly, address(oneUp));

        assertEq(identity.expiryOf(tokenId), originalExpiry + 30 days);
        assertTrue(identity.isValid(user1));
    }

    // ── Renewal — Reverts ─────────────────────────────────────────────────────

    function testRevertRenewNonExistent() public {
        vm.prank(user1);
        oneUp.approve(address(identity), MONTHLY_PRICE);

        vm.expectRevert(IdentityNFT.NoIdentityFound.selector);
        vm.prank(user1);
        identity.renew(99, IdentityNFT.Period.Monthly, address(oneUp));
    }

    function testEmitIdentityRenewed() public {
        uint256 tokenId = _mintMonthly(user1);

        vm.prank(user1);
        oneUp.approve(address(identity), MONTHLY_PRICE);

        vm.expectEmit(true, false, false, false);
        emit IdentityNFT.IdentityRenewed(tokenId, IdentityNFT.Period.Monthly, 0);

        vm.prank(user1);
        identity.renew(tokenId, IdentityNFT.Period.Monthly, address(oneUp));
    }

    function testRevertRenewWhenPaused() public {
        uint256 tokenId = _mintMonthly(user1);

        vm.prank(admin);
        identity.pause();

        vm.prank(user1);
        oneUp.approve(address(identity), MONTHLY_PRICE);

        vm.expectRevert();
        vm.prank(user1);
        identity.renew(tokenId, IdentityNFT.Period.Monthly, address(oneUp));
    }

    // ── Suspend / Unsuspend ───────────────────────────────────────────────────

    function testSuspendBlocksIsValid() public {
        uint256 tokenId = _mintMonthly(user1);
        assertTrue(identity.isValid(user1));

        vm.prank(admin);
        identity.suspend(tokenId);

        assertFalse(identity.isValid(user1));
        assertEq(uint8(identity.statusOf(tokenId)), uint8(IdentityNFT.Status.Suspended));
    }

    function testSuspendBlocksActiveToken() public {
        uint256 tokenId = _mintYearly(user1); // still active for 365 days
        assertTrue(identity.isValid(user1));

        vm.prank(admin);
        identity.suspend(tokenId);

        assertFalse(identity.isValid(user1)); // suspended overrides active
    }

    function testUnsuspendRestoresAccess() public {
        uint256 tokenId = _mintMonthly(user1);

        vm.prank(admin);
        identity.suspend(tokenId);
        assertFalse(identity.isValid(user1));

        vm.prank(admin);
        identity.unsuspend(tokenId);

        assertTrue(identity.isValid(user1));
        assertEq(uint8(identity.statusOf(tokenId)), uint8(IdentityNFT.Status.Active));
    }

    function testSuspendedUserCanStillRenew() public {
        uint256 tokenId = _mintMonthly(user1);

        vm.prank(admin);
        identity.suspend(tokenId);

        // Renewal still works (payment accepted) but isValid remains false until unsuspended
        _renewMonthly(user1, tokenId);
        assertFalse(identity.isValid(user1));

        vm.prank(admin);
        identity.unsuspend(tokenId);
        assertTrue(identity.isValid(user1));
    }

    function testRevertSuspendNonExistent() public {
        vm.expectRevert(IdentityNFT.NoIdentityFound.selector);
        vm.prank(admin);
        identity.suspend(99);
    }

    function testRevertNonOwnerSuspend() public {
        uint256 tokenId = _mintMonthly(user1);

        vm.expectRevert();
        vm.prank(user1);
        identity.suspend(tokenId);
    }

    function testSuspendEmitsEvent() public {
        uint256 tokenId = _mintMonthly(user1);

        vm.expectEmit(true, false, false, false);
        emit IdentityNFT.Suspended(tokenId);

        vm.prank(admin);
        identity.suspend(tokenId);
    }

    function testUnsuspendEmitsEvent() public {
        uint256 tokenId = _mintMonthly(user1);
        vm.prank(admin);
        identity.suspend(tokenId);

        vm.expectEmit(true, false, false, false);
        emit IdentityNFT.Unsuspended(tokenId);

        vm.prank(admin);
        identity.unsuspend(tokenId);
    }

    // ── Metadata update ───────────────────────────────────────────────────────

    function testUpdateMetadata() public {
        uint256 tokenId = _mintMonthly(user1);

        vm.prank(user1);
        identity.updateMetadata(tokenId, "ipfs://newProfile");

        assertEq(identity.tokenURI(tokenId), "ipfs://newProfile");
    }

    function testRevertUpdateMetadataNotOwner() public {
        uint256 tokenId = _mintMonthly(user1);

        vm.expectRevert(IdentityNFT.NotTokenOwner.selector);
        vm.prank(user2);
        identity.updateMetadata(tokenId, "ipfs://hack");
    }

    function testUpdateMetadataEmitsEvent() public {
        uint256 tokenId = _mintMonthly(user1);

        vm.expectEmit(true, false, false, true);
        emit IdentityNFT.MetadataUpdated(tokenId, "ipfs://newProfile");

        vm.prank(user1);
        identity.updateMetadata(tokenId, "ipfs://newProfile");
    }

    function testUpdateMetadataMultipleTimes() public {
        uint256 tokenId = _mintMonthly(user1);

        vm.prank(user1);
        identity.updateMetadata(tokenId, "ipfs://v2");
        vm.prank(user1);
        identity.updateMetadata(tokenId, "ipfs://v3");

        assertEq(identity.tokenURI(tokenId), "ipfs://v3");
    }

    // ── statusOf ──────────────────────────────────────────────────────────────

    function testStatusExpiredAfterMonthlyPeriod() public {
        uint256 tokenId = _mintMonthly(user1);

        vm.warp(block.timestamp + 30 days + 1);

        assertEq(uint8(identity.statusOf(tokenId)), uint8(IdentityNFT.Status.Expired));
    }

    function testStatusActiveAfterYearlyMint() public {
        uint256 tokenId = _mintYearly(user1);

        vm.warp(block.timestamp + 364 days);

        assertEq(uint8(identity.statusOf(tokenId)), uint8(IdentityNFT.Status.Active));
    }

    function testStatusExpiredAfterYearlyPeriod() public {
        uint256 tokenId = _mintYearly(user1);

        vm.warp(block.timestamp + 365 days + 1);

        assertEq(uint8(identity.statusOf(tokenId)), uint8(IdentityNFT.Status.Expired));
    }

    function testStatusSuspendedOverridesActive() public {
        uint256 tokenId = _mintYearly(user1); // active for 365 days

        vm.prank(admin);
        identity.suspend(tokenId);

        assertEq(uint8(identity.statusOf(tokenId)), uint8(IdentityNFT.Status.Suspended));
    }

    // ── expiryOfUser ──────────────────────────────────────────────────────────

    function testExpiryOfUser() public {
        uint256 tokenId = _mintMonthly(user1);
        assertEq(identity.expiryOfUser(user1), identity.expiryOf(tokenId));
    }

    function testExpiryOfUserNoIdentity() public view {
        assertEq(identity.expiryOfUser(user2), 0);
    }

    // ── Transfers (non-soulbound) ─────────────────────────────────────────────

    function testTransferUpdatesTokenIdMapping() public {
        uint256 tokenId = _mintMonthly(user1);

        vm.prank(user1);
        identity.transferFrom(user1, user2, tokenId);

        assertEq(identity.tokenIdOf(user1), 0);
        assertEq(identity.tokenIdOf(user2), tokenId);
    }

    function testTransferPreservesExpiry() public {
        uint256 tokenId = _mintYearly(user1);
        uint256 expiry = identity.expiryOf(tokenId);

        vm.prank(user1);
        identity.transferFrom(user1, user2, tokenId);

        assertEq(identity.expiryOf(tokenId), expiry);
    }

    // ── Soulbound ─────────────────────────────────────────────────────────────

    function testSoulboundBlocksTransfer() public {
        IdentityNFT.InitialTokenConfig[] memory tokens = new IdentityNFT.InitialTokenConfig[](1);
        tokens[0] = IdentityNFT.InitialTokenConfig({
            token:        address(oneUp),
            mintPrice:    MINT_PRICE,
            monthlyPrice: MONTHLY_PRICE,
            yearlyPrice:  YEARLY_PRICE
        });

        vm.prank(admin);
        IdentityNFT soulId = new IdentityNFT(
            "Soul ID", "SID", "Global", treasury, true, tokens
        );

        oneUp.mint(user1, MINT_PRICE);
        vm.prank(user1);
        oneUp.approve(address(soulId), MINT_PRICE);
        vm.prank(user1);
        soulId.mint("ipfs://soul", IdentityNFT.Period.Monthly, address(oneUp));

        vm.expectRevert(IdentityNFT.SoulboundToken.selector);
        vm.prank(user1);
        soulId.transferFrom(user1, user2, 1);
    }

    // ── Token config admin ────────────────────────────────────────────────────

    function testSetTokenConfig() public {
        vm.prank(admin);
        identity.setTokenConfig(address(usdc), USDC_MINT_PRICE, USDC_MONTHLY_PRICE, USDC_YEARLY_PRICE);

        (uint256 mp, uint256 mop, uint256 yp, bool en) =
            _tokenConfig(address(usdc));
        assertEq(mp,  USDC_MINT_PRICE);
        assertEq(mop, USDC_MONTHLY_PRICE);
        assertEq(yp,  USDC_YEARLY_PRICE);
        assertTrue(en);
    }

    function testSetTokenConfigUpdatesExisting() public {
        vm.prank(admin);
        identity.setTokenConfig(address(oneUp), 100e18, 40e18, 400e18);

        (uint256 mp, uint256 mop, uint256 yp, bool en) =
            _tokenConfig(address(oneUp));
        assertEq(mp,  100e18);
        assertEq(mop, 40e18);
        assertEq(yp,  400e18);
        assertTrue(en);

        // acceptedTokens list should not have duplicates
        address[] memory accepted = identity.getAcceptedTokens();
        assertEq(accepted.length, 1);
    }

    function testGetAcceptedTokens() public {
        address[] memory tokens = identity.getAcceptedTokens();
        assertEq(tokens.length, 1);
        assertEq(tokens[0], address(oneUp));

        vm.prank(admin);
        identity.setTokenConfig(address(usdc), USDC_MINT_PRICE, USDC_MONTHLY_PRICE, USDC_YEARLY_PRICE);

        tokens = identity.getAcceptedTokens();
        assertEq(tokens.length, 2);
    }

    function testDisableTokenPreventsUse() public {
        vm.prank(admin);
        identity.disableToken(address(oneUp));

        (, , , bool en) = _tokenConfig(address(oneUp));
        assertFalse(en);
    }

    function testReenableTokenViaSetTokenConfig() public {
        vm.prank(admin);
        identity.disableToken(address(oneUp));

        vm.prank(admin);
        identity.setTokenConfig(address(oneUp), MINT_PRICE, MONTHLY_PRICE, YEARLY_PRICE);

        (, , , bool en) = _tokenConfig(address(oneUp));
        assertTrue(en);
    }

    function testSetTreasury() public {
        address newTreasury = makeAddr("newTreasury");
        vm.prank(admin);
        identity.setTreasury(newTreasury);
        assertEq(identity.treasury(), newTreasury);
    }

    function testRevertSetTreasuryZeroAddress() public {
        vm.expectRevert(IdentityNFT.ZeroAddress.selector);
        vm.prank(admin);
        identity.setTreasury(address(0));
    }

    function testRevertNonOwnerSetTokenConfig() public {
        vm.expectRevert();
        vm.prank(user1);
        identity.setTokenConfig(address(usdc), 1e18, 1e18, 1e18);
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    function _mintMonthly(address who) internal returns (uint256) {
        vm.prank(who);
        oneUp.approve(address(identity), MINT_PRICE);
        vm.prank(who);
        return identity.mint("ipfs://profile", IdentityNFT.Period.Monthly, address(oneUp));
    }

    function _mintYearly(address who) internal returns (uint256) {
        vm.prank(who);
        oneUp.approve(address(identity), MINT_PRICE);
        vm.prank(who);
        return identity.mint("ipfs://profile", IdentityNFT.Period.Yearly, address(oneUp));
    }

    function _renewMonthly(address who, uint256 tokenId) internal {
        vm.prank(who);
        oneUp.approve(address(identity), MONTHLY_PRICE);
        vm.prank(who);
        identity.renew(tokenId, IdentityNFT.Period.Monthly, address(oneUp));
    }

    function _renewYearly(address who, uint256 tokenId) internal {
        vm.prank(who);
        oneUp.approve(address(identity), YEARLY_PRICE);
        vm.prank(who);
        identity.renew(tokenId, IdentityNFT.Period.Yearly, address(oneUp));
    }

    /// @dev Helper to unpack the TokenConfig tuple from the public mapping.
    function _tokenConfig(address token)
        internal
        view
        returns (uint256 mintPrice, uint256 monthlyPrice, uint256 yearlyPrice, bool enabled)
    {
        (mintPrice, monthlyPrice, yearlyPrice, enabled) = identity.tokenConfigs(token);
    }
}
