## Plan: Secure EIP-4626 Challenge Vaults & NFT Access System (with 1UP Token Integration)

This architecture enables secure, tokenized gaming challenges and access control using EIP-4626 vaults, renewable identity NFTs, and the 1UP token as the exclusive payment/staking currency.

### Steps

1. **ChallengeVault (EIP-4626)**
   - Escrow contract for two players, each staking 1UP tokens.
   - Parameters: 1UP token address, stake amount, challenge duration, metadata URI.
   - Both must agree on result; winner gets both stakes.
   - Early close by mutual agreement; fallback resolver if no agreement.
   - Only 1UP token (0x05cb1e3ba6102b097c0ad913c8b82ac76e7df73f, Base Sepolia) is accepted.
   - Only players with an active IdentityNFT can create or join challenges.

2. **VaultFactory**
   - Deploys new ChallengeVaults per challenge.
   - Only allows 1UP for staking.
   - Tracks all active/completed challenges.
   - Gates `createChallenge` with `identityNFT.isValid(msg.sender)`.

3. **IdentityNFT (Subscription Profile Card)**
   - Each user mints a unique NFT profile (soulbound or transferable).
   - One-time mint fee in 1UP; renewable monthly (30 days) or yearly (365 days).
   - Metadata per token: profile image, background, social links — stored on IPFS.
   - `createdAt` stored on-chain; `expiryOf` updated on each payment.
   - Status is derived: Active / Expired / Suspended.
   - Admin can suspend any token for misbehaviour regardless of payment status.
   - **A valid (active, non-suspended) IdentityNFT is the only requirement to join challenges.**

4. **CourseNFT & CourseFactory**
   - ERC-721 course NFT with token-gated private content and ERC-2981 royalties.
   - Paid in ETH (not 1UP). Independent of the gaming tower access model.

5. **Backend Integration**
   - Pinata upload for public/private metadata (API keys managed securely).
   - SMTP/email integration for renewal reminders and notifications.

6. **Frontend Integration**
   - Show public/private metadata based on NFT ownership.
   - Display identity card: status, createdAt, expiry, pfp, background, socials.
   - Allow users to renew IdentityNFT (monthly or yearly).
   - Gate challenge entry on `isValid(user)` only.
   - Display all prices in 1UP and COP equivalent (1UP = 1000 COP).

### Further Considerations

1. **Pricing:** All gaming prices (challenge staking, identity mint/renewal) are set in 1UP.
2. **Challenge Resolution:** Manual agreement, oracle, or dispute resolver for finalizing results.
3. **Access Control:** Active IdentityNFT is the single gate — no per-game tickets required.
4. **Security:** Use OpenZeppelin contracts, reentrancy guards, pausable, and access control.
5. **Extensibility:** Keep logic flexible for future token whitelisting or new game types.

---

**Status:** IdentityNFT implemented. Next: add identity gate to VaultFactory + ChallengeVault.
