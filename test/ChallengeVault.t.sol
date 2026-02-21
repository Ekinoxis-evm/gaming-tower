// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import "../src/challenges/ChallengeVault.sol";
import "../src/challenges/VaultFactory.sol";
import "./mocks/MockERC20.sol";
import "./mocks/MockIdentityNFT.sol";

contract ChallengeVaultTest is Test {
    MockERC20       public oneUp;
    MockERC20       public usdc;
    MockIdentityNFT public identity;
    VaultFactory    public factory;
    ChallengeVault  public vault;

    address admin    = makeAddr("admin");
    address resolver = makeAddr("resolver");
    address player1  = makeAddr("player1");
    address player2  = makeAddr("player2");

    uint256 constant STAKE    = 100e18;
    uint256 constant DURATION = 1 days;

    function setUp() public {
        oneUp    = new MockERC20();
        usdc     = new MockERC20();
        identity = new MockIdentityNFT();

        // Both players have active identities
        identity.setValid(player1, true);
        identity.setValid(player2, true);

        address[] memory tokens = new address[](1);
        tokens[0] = address(oneUp);

        vm.prank(admin);
        factory = new VaultFactory(tokens, resolver, address(identity));

        // player1 creates a challenge vault
        vm.prank(player1);
        address vaultAddr = factory.createChallenge(address(oneUp), STAKE, DURATION, "ipfs://challenge");
        vault = ChallengeVault(vaultAddr);

        // Fund both players
        oneUp.mint(player1, 1000e18);
        oneUp.mint(player2, 1000e18);
    }

    // ── Initialization ───────────────────────────────────────────────────────

    function testInitialization() public view {
        assertEq(vault.player1(),             player1);
        assertEq(address(vault.player2()),    address(0));
        assertEq(vault.stakeAmount(),         STAKE);
        assertEq(vault.challengeDuration(),   DURATION);
        assertEq(uint8(vault.state()),        uint8(ChallengeVault.State.OPEN));
        assertEq(address(vault.asset()),      address(oneUp));
        assertEq(address(vault.identityNFT()), address(identity));
    }

    function testFactoryTracking() public view {
        assertEq(factory.getVaultCount(), 1);
        assertTrue(factory.isVault(address(vault)));
        assertEq(factory.getVaultsByCreator(player1)[0], address(vault));
    }

    // ── Deposits / Join ──────────────────────────────────────────────────────

    function testPlayer1Joins() public {
        vm.prank(player1);
        oneUp.approve(address(vault), STAKE);

        vm.prank(player1);
        vault.deposit(STAKE, player1);

        assertEq(vault.balanceOf(player1), STAKE);
        assertEq(uint8(vault.state()), uint8(ChallengeVault.State.OPEN));
    }

    function testPlayer2JoinsActivatesChallenge() public {
        _bothJoin();

        assertEq(uint8(vault.state()), uint8(ChallengeVault.State.ACTIVE));
        assertGt(vault.endTime(), block.timestamp);
        assertEq(vault.player2(), player2);
    }

    function testRevertJoinWithoutIdentity() public {
        address noIdentityPlayer = makeAddr("noIdentity");
        oneUp.mint(noIdentityPlayer, 1000e18);
        // noIdentityPlayer has NO valid identity (identity.isValid returns false)

        vm.prank(player1);
        oneUp.approve(address(vault), STAKE);
        vm.prank(player1);
        vault.deposit(STAKE, player1);

        vm.prank(noIdentityPlayer);
        oneUp.approve(address(vault), STAKE);

        vm.expectRevert(ChallengeVault.NoActiveIdentity.selector);
        vm.prank(noIdentityPlayer);
        vault.deposit(STAKE, noIdentityPlayer);
    }

    function testRevertJoinWithExpiredIdentity() public {
        // player2 had an identity that expired
        identity.setValid(player2, false);

        vm.prank(player1);
        oneUp.approve(address(vault), STAKE);
        vm.prank(player1);
        vault.deposit(STAKE, player1);

        vm.prank(player2);
        oneUp.approve(address(vault), STAKE);

        vm.expectRevert(ChallengeVault.NoActiveIdentity.selector);
        vm.prank(player2);
        vault.deposit(STAKE, player2);
    }

    function testPlayer1CanJoinWithoutIdentityCheck() public {
        // Player1's identity was verified at vault creation (VaultFactory).
        // Even if identity is revoked after creation, player1 can still deposit.
        identity.setValid(player1, false);

        vm.prank(player1);
        oneUp.approve(address(vault), STAKE);

        vm.prank(player1);
        vault.deposit(STAKE, player1); // no revert — player1 slot skips identity check

        assertEq(vault.balanceOf(player1), STAKE);
    }

    function testRevertWrongStakeAmount() public {
        vm.prank(player1);
        oneUp.approve(address(vault), STAKE * 2);

        // ERC4626 fires ERC4626ExceededMaxDeposit (maxDeposit=STAKE) before _deposit runs
        vm.expectRevert();
        vm.prank(player1);
        vault.deposit(STAKE + 1, player1);
    }

    function testRevertDoubleJoin() public {
        vm.prank(player1);
        oneUp.approve(address(vault), STAKE * 2);

        vm.prank(player1);
        vault.deposit(STAKE, player1);

        // maxDeposit(player1) is now 0 → ERC4626ExceededMaxDeposit fires before _deposit
        vm.expectRevert();
        vm.prank(player1);
        vault.deposit(STAKE, player1);
    }

    function testRevertThirdPlayerJoin() public {
        _bothJoin();

        address player3 = makeAddr("player3");
        oneUp.mint(player3, 1000e18);
        identity.setValid(player3, true);

        vm.prank(player3);
        oneUp.approve(address(vault), STAKE);

        // maxDeposit returns 0 when ACTIVE → ERC4626ExceededMaxDeposit fires before _deposit
        vm.expectRevert();
        vm.prank(player3);
        vault.deposit(STAKE, player3);
    }

    function testSharesNonTransferable() public {
        _bothJoin();

        vm.expectRevert(ChallengeVault.SharesNonTransferable.selector);
        vm.prank(player1);
        vault.transfer(player2, STAKE);
    }

    // ── submitNumber / auto-resolve ───────────────────────────────────────────

    function testAutoResolvePlayer1WinsHigherNumber() public {
        _bothJoin();
        vm.warp(vault.endTime() + 1);

        uint256 p1BalBefore = oneUp.balanceOf(player1);

        vm.prank(player1);
        vault.submitNumber(100);

        vm.prank(player2);
        vault.submitNumber(50); // player1 wins (100 > 50)

        assertEq(uint8(vault.state()), uint8(ChallengeVault.State.RESOLVED));
        assertEq(vault.winner(), player1);
        assertEq(oneUp.balanceOf(player1), p1BalBefore + 2 * STAKE);
        assertEq(vault.totalSupply(), 0); // all shares burned
    }

    function testAutoResolvePlayer2WinsHigherNumber() public {
        _bothJoin();
        vm.warp(vault.endTime() + 1);

        uint256 p2BalBefore = oneUp.balanceOf(player2);

        vm.prank(player1);
        vault.submitNumber(30);

        vm.prank(player2);
        vault.submitNumber(99);

        assertEq(uint8(vault.state()), uint8(ChallengeVault.State.RESOLVED));
        assertEq(vault.winner(), player2);
        assertEq(oneUp.balanceOf(player2), p2BalBefore + 2 * STAKE);
    }

    function testTieDoesNotAutoResolve() public {
        _bothJoin();
        vm.warp(vault.endTime() + 1);

        vm.prank(player1);
        vault.submitNumber(42);

        vm.prank(player2);
        vault.submitNumber(42); // tie — no auto-resolve

        assertEq(uint8(vault.state()), uint8(ChallengeVault.State.ACTIVE));
    }

    function testEmitNumberSubmitted() public {
        _bothJoin();
        vm.warp(vault.endTime() + 1);

        vm.expectEmit(true, false, false, true);
        emit ChallengeVault.NumberSubmitted(player1, 77);

        vm.prank(player1);
        vault.submitNumber(77);
    }

    function testRevertSubmitNumberBeforeEndTime() public {
        _bothJoin();
        // endTime not reached yet

        vm.expectRevert(ChallengeVault.NotAfterEndTime.selector);
        vm.prank(player1);
        vault.submitNumber(5);
    }

    function testRevertSubmitNumberNotPlayer() public {
        _bothJoin();
        vm.warp(vault.endTime() + 1);

        address random = makeAddr("random");
        vm.expectRevert(ChallengeVault.NotPlayer.selector);
        vm.prank(random);
        vault.submitNumber(10);
    }

    function testRevertSubmitNumberTwice() public {
        _bothJoin();
        vm.warp(vault.endTime() + 1);

        vm.prank(player1);
        vault.submitNumber(10);

        vm.expectRevert(ChallengeVault.AlreadySubmitted.selector);
        vm.prank(player1);
        vault.submitNumber(20);
    }

    function testRevertSubmitNumberWhenNotActive() public {
        // Only player1 joined — vault is still OPEN
        vm.prank(player1);
        oneUp.approve(address(vault), STAKE);
        vm.prank(player1);
        vault.deposit(STAKE, player1);

        vm.expectRevert(ChallengeVault.WrongState.selector);
        vm.prank(player1);
        vault.submitNumber(5);
    }

    // ── Dispute resolution (ties) ─────────────────────────────────────────────

    function testResolverBreaksTie() public {
        _bothJoin();
        vm.warp(vault.endTime() + 1);

        // Both submit the same number (tie)
        vm.prank(player1);
        vault.submitNumber(42);
        vm.prank(player2);
        vault.submitNumber(42);

        assertEq(uint8(vault.state()), uint8(ChallengeVault.State.ACTIVE));

        uint256 p2BalBefore = oneUp.balanceOf(player2);

        vm.prank(resolver);
        vault.resolveDispute(player2);

        assertEq(uint8(vault.state()), uint8(ChallengeVault.State.RESOLVED));
        assertEq(vault.winner(), player2);
        assertEq(oneUp.balanceOf(player2), p2BalBefore + 2 * STAKE);
    }

    function testRevertResolveDisputeBeforeBothSubmit() public {
        _bothJoin();
        vm.warp(vault.endTime() + 1);

        // Only player1 submitted
        vm.prank(player1);
        vault.submitNumber(42);

        vm.expectRevert(ChallengeVault.BothMustSubmit.selector);
        vm.prank(resolver);
        vault.resolveDispute(player1);
    }

    function testRevertResolveDisputeOnNonTie() public {
        _bothJoin();
        vm.warp(vault.endTime() + 1);

        vm.prank(player1);
        vault.submitNumber(10);
        vm.prank(player2);
        vault.submitNumber(20); // already auto-resolved — player2 wins

        // State is RESOLVED so this should revert with WrongState
        vm.expectRevert(ChallengeVault.WrongState.selector);
        vm.prank(resolver);
        vault.resolveDispute(player1);
    }

    function testRevertNonResolverCannotBreakTie() public {
        _bothJoin();
        vm.warp(vault.endTime() + 1);

        vm.prank(player1);
        vault.submitNumber(5);
        vm.prank(player2);
        vault.submitNumber(5); // tie

        vm.expectRevert(ChallengeVault.NotResolver.selector);
        vm.prank(player1);
        vault.resolveDispute(player1);
    }

    // ── maxDeposit ───────────────────────────────────────────────────────────

    function testMaxDepositBeforeJoin() public view {
        assertEq(vault.maxDeposit(player1), STAKE);
        assertEq(vault.maxDeposit(player2), STAKE);
    }

    function testMaxDepositAfterBothJoined() public {
        _bothJoin();
        assertEq(vault.maxDeposit(player1), 0);
        assertEq(vault.maxDeposit(player2), 0);
    }

    // ── Helpers ──────────────────────────────────────────────────────────────

    function _bothJoin() internal {
        vm.prank(player1);
        oneUp.approve(address(vault), STAKE);
        vm.prank(player1);
        vault.deposit(STAKE, player1);

        vm.prank(player2);
        oneUp.approve(address(vault), STAKE);
        vm.prank(player2);
        vault.deposit(STAKE, player2);
    }
}

contract VaultFactoryTest is Test {
    MockERC20       public oneUp;
    MockERC20       public usdc;
    MockIdentityNFT public identity;
    VaultFactory    public factory;

    address admin    = makeAddr("admin");
    address resolver = makeAddr("resolver");
    address creator  = makeAddr("creator");

    function setUp() public {
        oneUp    = new MockERC20();
        usdc     = new MockERC20();
        identity = new MockIdentityNFT();
        identity.setValid(creator, true);

        address[] memory tokens = new address[](1);
        tokens[0] = address(oneUp);

        vm.prank(admin);
        factory = new VaultFactory(tokens, resolver, address(identity));
    }

    function testInitialization() public view {
        assertTrue(factory.isAcceptedToken(address(oneUp)));
        assertEq(address(factory.identityNFT()), address(identity));
        assertEq(factory.resolver(),             resolver);
        assertEq(factory.owner(),                admin);
        assertEq(factory.getVaultCount(),        0);
    }

    function testCreateChallenge() public {
        vm.prank(creator);
        address vault = factory.createChallenge(address(oneUp), 50e18, 2 days, "ipfs://test");

        assertTrue(factory.isVault(vault));
        assertEq(factory.getVaultCount(), 1);
        assertEq(factory.getAllVaults()[0], vault);
        assertEq(factory.getVaultsByCreator(creator)[0], vault);
    }

    function testRevertCreateChallengeNoIdentity() public {
        address noId = makeAddr("noIdentity");

        vm.expectRevert(VaultFactory.NoActiveIdentity.selector);
        vm.prank(noId);
        factory.createChallenge(address(oneUp), 50e18, 1 days, "ipfs://x");
    }

    function testRevertCreateChallengeExpiredIdentity() public {
        identity.setValid(creator, false);

        vm.expectRevert(VaultFactory.NoActiveIdentity.selector);
        vm.prank(creator);
        factory.createChallenge(address(oneUp), 50e18, 1 days, "ipfs://x");
    }

    function testRevertZeroStake() public {
        vm.expectRevert(VaultFactory.ZeroStake.selector);
        vm.prank(creator);
        factory.createChallenge(address(oneUp), 0, 1 days, "ipfs://x");
    }

    function testRevertZeroDuration() public {
        vm.expectRevert(VaultFactory.ZeroDuration.selector);
        vm.prank(creator);
        factory.createChallenge(address(oneUp), 50e18, 0, "ipfs://x");
    }

    function testRevertCreateChallengeWithNonWhitelistedToken() public {
        vm.expectRevert(abi.encodeWithSelector(VaultFactory.TokenNotAccepted.selector, address(usdc)));
        vm.prank(creator);
        factory.createChallenge(address(usdc), 50e18, 1 days, "ipfs://x");
    }

    function testWhitelistToken() public {
        assertFalse(factory.isAcceptedToken(address(usdc)));

        vm.prank(admin);
        factory.whitelistToken(address(usdc));

        assertTrue(factory.isAcceptedToken(address(usdc)));
    }

    function testRemoveToken() public {
        assertTrue(factory.isAcceptedToken(address(oneUp)));

        vm.prank(admin);
        factory.removeToken(address(oneUp));

        assertFalse(factory.isAcceptedToken(address(oneUp)));
    }

    function testGetAcceptedTokens() public view {
        address[] memory tokens = factory.getAcceptedTokens();
        assertEq(tokens.length, 1);
        assertEq(tokens[0], address(oneUp));
    }

    function testCreateChallengeWithSecondToken() public {
        vm.prank(admin);
        factory.whitelistToken(address(usdc));

        vm.prank(creator);
        address vaultAddr = factory.createChallenge(address(usdc), 50e6, 1 days, "ipfs://usdc");

        ChallengeVault v = ChallengeVault(vaultAddr);
        assertEq(address(v.asset()), address(usdc));
    }

    function testRevertWhitelistZeroAddress() public {
        vm.expectRevert(VaultFactory.ZeroAddress.selector);
        vm.prank(admin);
        factory.whitelistToken(address(0));
    }

    function testRevertZeroAddressIdentity() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(oneUp);

        vm.expectRevert(VaultFactory.ZeroAddress.selector);
        new VaultFactory(tokens, resolver, address(0));
    }

    function testRevertZeroAddressResolver() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(oneUp);

        vm.expectRevert(VaultFactory.ZeroAddress.selector);
        new VaultFactory(tokens, address(0), address(identity));
    }

    function testSetResolver() public {
        address newResolver = makeAddr("newResolver");
        vm.prank(admin);
        factory.setResolver(newResolver);
        assertEq(factory.resolver(), newResolver);
    }

    function testRevertSetResolverNonOwner() public {
        vm.expectRevert();
        vm.prank(creator);
        factory.setResolver(makeAddr("x"));
    }
}
