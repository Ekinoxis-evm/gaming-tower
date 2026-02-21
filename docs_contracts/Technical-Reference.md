# Technical Reference — Gaming Tower + Courses NFT

> Solidity `^0.8.27` · OpenZeppelin v5
> Networks: Base Sepolia (84532) / Base Mainnet (8453)
> Deployed addresses: [`deployments/addresses.json`](../deployments/addresses.json)

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [IdentityNFT](#2-identitynft)
3. [ChallengeVault](#3-challengevault)
4. [VaultFactory](#4-vaultfactory)
5. [CourseNFT](#5-coursenft)
6. [CourseFactory](#6-coursefactory)
7. [Deploy Commands](#7-deploy-commands)

---

## 1. Architecture Overview

```
Gaming Tower + Courses NFT Platform
├── IdentityNFT    (subscription profile card — city-based, multi-token)
│
├── VaultFactory   ──deploys──► ChallengeVault (token escrow, EIP-4626, number game)
│
└── CourseFactory  ──deploys──► CourseNFT (ERC-721, ETH payments, ERC-2981 royalties)
```

**Payment currencies:**
- `IdentityNFT` — any whitelisted ERC-20 token (1UP, USDC, EUROC — configured per deployment)
- `ChallengeVault` — whitelisted ERC-20 token chosen at challenge creation
- `CourseNFT` — ETH (native)

**Access control:** A valid (active, non-suspended) IdentityNFT is the only gate to create or join a challenge.

**Factory pattern:** Each factory deploys child contracts and tracks them. Ownership of each child is transferred to the caller on creation.

**Challenge resolution:** Players submit a number after the challenge window ends. Highest number wins. Resolver breaks ties.

---

## 2. IdentityNFT

**File:** `src/IdentityNFT.sol`
**Inherits:** `ERC721`, `Ownable`, `Pausable`, `ReentrancyGuard`

Renewable subscription-based profile NFT ("Identity Card") for the gaming tower. One card per address. Each deployment is a city-specific collection (e.g. "Medellín", "Bogotá"). Payments are accepted in any configured ERC-20 token, each with its own price schedule. Admin can suspend any card regardless of payment status. Can be configured as soulbound (non-transferable).

### Constructor

```solidity
constructor(
    string  memory _name,           // ERC-721 name (e.g. "Entry - Medellín")
    string  memory _symbol,         // ERC-721 symbol (e.g. "EMDE")
    string  memory _city,           // City label stored on-chain
    address        _treasury,       // Receives all mint and renewal fees
    bool           _soulbound,      // If true: tokens cannot be transferred
    InitialTokenConfig[] memory _initialTokens  // Payment token configurations
)
```

### Structs

```solidity
struct TokenConfig {
    uint256 mintPrice;      // One-time card creation fee (token wei)
    uint256 monthlyPrice;   // 30-day renewal cost (token wei)
    uint256 yearlyPrice;    // 365-day renewal cost (token wei)
    bool    enabled;        // False = token disabled for new payments
}

struct InitialTokenConfig {
    address token;
    uint256 mintPrice;
    uint256 monthlyPrice;
    uint256 yearlyPrice;
}
```

### Constants

| Constant | Value | Description |
|----------|-------|-------------|
| `MONTHLY_PERIOD` | `30 days` | Duration of a monthly subscription |
| `YEARLY_PERIOD` | `365 days` | Duration of a yearly subscription |

### Enums

```solidity
enum Period { Monthly, Yearly }          // Chosen at mint and every renewal
enum Status { Active, Expired, Suspended } // Derived — never stored, always computed
```

### State Variables

| Variable | Type | Description |
|----------|------|-------------|
| `city` | `string` | City / collection label — set once at deploy |
| `soulbound` | `bool` | Blocks transfers when true |
| `treasury` | `address` | Receives all ERC-20 fees |
| `tokenConfigs` | `mapping(address => TokenConfig)` | Price schedule per accepted token |
| `createdAt` | `mapping(uint256 => uint256)` | `tokenId → mint timestamp` (immutable) |
| `expiryOf` | `mapping(uint256 => uint256)` | `tokenId → subscription expiry timestamp` |
| `suspended` | `mapping(uint256 => bool)` | `tokenId → admin suspension flag` |
| `tokenIdOf` | `mapping(address => uint256)` | `address → tokenId` (0 = no identity) |

---

### Read Functions

#### `isValid(address user) → bool`

Returns `true` if `user` holds an active, non-suspended identity card.

- Checks `tokenIdOf[user] != 0` (card exists)
- Checks `!suspended[tokenId]` (not admin-suspended)
- Checks `expiryOf[tokenId] >= block.timestamp` (subscription active)

This is the gate used by `VaultFactory` and `ChallengeVault`.

---

#### `statusOf(uint256 tokenId) → Status`

Returns the derived status of a token:

| Return | Condition |
|--------|-----------|
| `Status.Suspended` | `suspended[tokenId] == true` (takes priority) |
| `Status.Active` | `expiryOf[tokenId] >= block.timestamp` |
| `Status.Expired` | none of the above |

---

#### `expiryOfUser(address user) → uint256`

Returns the expiry timestamp for `user`'s token. Returns `0` if the user has no identity.

---

#### `tokenURI(uint256 tokenId) → string`

Returns the stored per-token IPFS metadata URI (pfp, background, socials, etc.). Reverts if token does not exist.

---

#### `totalSupply() → uint256`

Returns the total number of identity cards minted so far.

---

#### `getAcceptedTokens() → address[]`

Returns the list of all token addresses that have ever been configured (enabled or disabled). Use `tokenConfigs[token].enabled` to check active status.

---

#### `tokenConfigs(address token) → TokenConfig`

Returns the full price schedule for a given token address.

---

#### `tokenIdOf(address user) → uint256`

Returns the token ID owned by `user`. Returns `0` if the user has no identity.

---

### Write Functions

#### `mint(string metadataURI, Period period, address token) → uint256 tokenId`

Mint a new identity card. One per address.

**Flow:**
1. Reverts `AlreadyHasIdentity` if caller already has a card.
2. Reverts `TokenNotAccepted` if `token` is not enabled.
3. Pulls `tokenConfigs[token].mintPrice` from caller → treasury via `safeTransferFrom`.
4. Mints token, sets `createdAt`, `expiryOf` (now + period duration), and metadata URI.
5. Emits `IdentityMinted` and `MetadataUpdated`.

**Requires:** caller has approved at least `mintPrice` to this contract.
**Guard:** `whenNotPaused`, `nonReentrant`

---

#### `renew(uint256 tokenId, Period period, address token)`

Renew a subscription. Anyone can pay (e.g. a friend sponsors the renewal).

**Renewal logic:**
- Still active → `newExpiry = expiryOf[tokenId] + period` (paid days preserved)
- Already expired → `newExpiry = block.timestamp + period` (fresh start, no grace period)

**Flow:**
1. Reverts `NoIdentityFound` if token has no expiry (does not exist).
2. Reverts `TokenNotAccepted` if `token` is not enabled.
3. Pulls renewal price from caller → treasury.
4. Updates `expiryOf[tokenId]` per the renewal logic above.
5. Emits `IdentityRenewed`.

**Note:** The token used for renewal may differ from the token used at mint.
**Guard:** `whenNotPaused`, `nonReentrant`

---

#### `updateMetadata(uint256 tokenId, string newURI)`

Update the IPFS metadata URI for a card. Only the token owner can call this.

Reverts `NotTokenOwner` if `msg.sender != ownerOf(tokenId)`.
Emits `MetadataUpdated`.

---

### Admin Functions (onlyOwner)

#### `suspend(uint256 tokenId)`

Immediately blocks platform access for a card regardless of payment status. Use for misbehaviour enforcement. Reverts `NoIdentityFound` if token does not exist. Emits `Suspended`.

---

#### `unsuspend(uint256 tokenId)`

Restores a previously suspended card. Emits `Unsuspended`.

---

#### `setTokenConfig(address token, uint256 mintPrice, uint256 monthlyPrice, uint256 yearlyPrice)`

Add or update a payment token configuration. Re-calling with an existing token re-enables it if previously disabled. Reverts `ZeroAddress` if `token == address(0)`. Emits `TokenConfigSet`.

---

#### `disableToken(address token)`

Disable a payment token. Disabled tokens cannot be used for new mint or renewal calls. Emits `TokenDisabled`.

---

#### `setTreasury(address newTreasury)`

Update the treasury address. Reverts `ZeroAddress`. Emits `TreasuryUpdated`.

---

#### `pause() / unpause()`

Emergency pause — blocks `mint` and `renew`. Emits `Paused` / `Unpaused`.

---

### Events

```solidity
event IdentityMinted(address indexed to, uint256 indexed tokenId, Period period, uint256 expiry);
event IdentityRenewed(uint256 indexed tokenId, Period period, uint256 newExpiry);
event MetadataUpdated(uint256 indexed tokenId, string uri);
event Suspended(uint256 indexed tokenId);
event Unsuspended(uint256 indexed tokenId);
event TokenConfigSet(address indexed token, uint256 mintPrice, uint256 monthlyPrice, uint256 yearlyPrice);
event TokenDisabled(address indexed token);
event TreasuryUpdated(address indexed newTreasury);
```

### Custom Errors

```solidity
error AlreadyHasIdentity();         // Caller already owns an identity card
error NoIdentityFound();            // tokenId does not exist
error NotTokenOwner();              // Only the token owner can update metadata
error SoulboundToken();             // Transfer blocked (soulbound mode)
error ZeroAddress();                // Address parameter is zero
error TokenNotAccepted(address token); // Token not in the whitelist or disabled
```

---

## 3. ChallengeVault

**File:** `src/challenges/ChallengeVault.sol`
**Inherits:** `ERC4626`, `ERC20`, `Ownable`, `Pausable`, `ReentrancyGuard`

EIP-4626 escrow vault for a single two-player challenge. Players stake equal amounts of an ERC-20 token. After the challenge duration ends, each player submits a number — the higher number wins. In case of a tie, the resolver decides. Shares are non-transferable (soulbound to players). Withdrawals are disabled; funds are released only through the resolution mechanism.

### State Machine

```
OPEN ──(player2 deposits)──► ACTIVE ──(both submit numbers, highest wins)──► RESOLVED
                                │
                                └──(both submit same number → resolver)──► RESOLVED
```

### Constructor

```solidity
constructor(
    IERC20  _token,          // ERC-20 staking token
    uint256 _stakeAmount,    // Exact amount each player must deposit (token wei)
    uint256 _duration,       // Challenge window in seconds (starts when ACTIVE)
    string  memory _metadataURI,  // IPFS URI describing the challenge
    address _resolver,       // Trusted address that breaks ties
    address _player1,        // Challenge creator (set by VaultFactory)
    address _identityNFT     // IdentityNFT contract — player2 isValid() checked at deposit
)
```

### State Variables

| Variable | Type | Description |
|----------|------|-------------|
| `stakeAmount` | `uint256 immutable` | Token amount each player must deposit |
| `challengeDuration` | `uint256 immutable` | Duration in seconds from activation |
| `identityNFT` | `IIdentityNFT immutable` | Identity contract checked when player2 deposits |
| `metadataURI` | `string` | IPFS URI for challenge metadata |
| `resolver` | `address` | Trusted address for tie-breaking |
| `player1` | `address` | Challenge creator |
| `player2` | `address` | Second player (set when they deposit) |
| `state` | `State` | OPEN / ACTIVE / RESOLVED |
| `endTime` | `uint256` | `block.timestamp + challengeDuration` — set when ACTIVE |
| `winner` | `address` | Set on resolution |
| `submittedNumber` | `mapping(address => uint256)` | Number each player submitted |
| `hasSubmitted` | `mapping(address => bool)` | Whether each player has submitted |

---

### Read Functions

#### `maxDeposit(address account) → uint256`

Returns `stakeAmount` when a deposit slot is available for `account`, `0` otherwise.

Rules:
- Returns `0` if state is not `OPEN`
- Returns `0` if `account == player1` and player1 already deposited
- Returns `0` if `account != player1` and player2 slot is already taken
- Returns `stakeAmount` in all other valid cases

---

#### `maxMint(address account) → uint256`

Identical to `maxDeposit` (1:1 share/asset ratio).

---

#### `maxWithdraw(address) → uint256`

Always returns `0`. Withdrawals are disabled; use `submitNumber` to resolve.

---

#### `maxRedeem(address) → uint256`

Always returns `0`.

---

#### `state() → State`

Current challenge state: `OPEN` (0), `ACTIVE` (1), `RESOLVED` (2).

---

#### `submittedNumber(address player) → uint256`

The number submitted by `player`. Only meaningful after `hasSubmitted[player] == true`.

---

#### `hasSubmitted(address player) → bool`

Whether `player` has called `submitNumber`.

---

### Write Functions

#### `deposit(uint256 assets, address receiver) → uint256 shares`

Join the challenge by depositing exactly `stakeAmount` tokens.

**Player1 path (receiver == player1):**
1. Reverts `WrongState` if not OPEN.
2. Reverts `WrongStakeAmount` if `assets != stakeAmount`.
3. Reverts `AlreadyJoined` if player1 already deposited.
4. Transfers tokens from caller to vault, mints shares.
5. Emits `PlayerJoined`.

**Player2 path (receiver != player1):**
1. Same state and amount checks.
2. Reverts `NoActiveIdentity` if `identityNFT.isValid(receiver)` is false.
3. Reverts `AlreadyJoined` if player2 slot is already taken.
4. Sets `player2 = receiver`.
5. Once both players have deposited: sets `state = ACTIVE`, `endTime = block.timestamp + challengeDuration`.
6. Emits `PlayerJoined`, then `ChallengeActivated`.

**Requires:** caller has approved at least `stakeAmount` to this vault.
**Guard:** `nonReentrant`, `whenNotPaused`

---

#### `submitNumber(uint256 number)`

Submit your number after the challenge window ends. Callable once per player.

**Flow:**
1. Reverts `WrongState` if not ACTIVE.
2. Reverts `NotAfterEndTime` if `block.timestamp < endTime`.
3. Reverts `NotPlayer` if caller is not player1 or player2.
4. Reverts `AlreadySubmitted` if caller already submitted.
5. Records `submittedNumber[caller] = number`, `hasSubmitted[caller] = true`.
6. Emits `NumberSubmitted`.
7. If both players have submitted:
   - `n1 > n2` → player1 wins → `_resolveChallenge(player1)`
   - `n2 > n1` → player2 wins → `_resolveChallenge(player2)`
   - Tie → state stays ACTIVE, resolver must call `resolveDispute`

**Resolution internal flow (`_resolveChallenge`):** Burns both players' shares, transfers the full prize (`stakeAmount * 2`) to the winner, sets `state = RESOLVED`, emits `ChallengeResolved`.

---

#### `resolveDispute(address _winner)`

Resolver-only. Breaks a tie — callable only when both players have submitted the same number.

1. Reverts `NotResolver` if caller is not `resolver`.
2. Reverts `WrongState` if not ACTIVE.
3. Reverts `BothMustSubmit` if either player has not submitted.
4. Reverts with `"Not a tie"` if the numbers differ.
5. Calls `_resolveChallenge(_winner)`.

---

### Admin Functions (onlyOwner)

#### `setResolver(address _resolver)`

Update the resolver address. Emits `ResolverUpdated`.

---

#### `pause() / unpause()`

Emergency pause — blocks `deposit`. Emits `Paused` / `Unpaused`.

---

### Events

```solidity
event PlayerJoined(address indexed player);
event ChallengeActivated(uint256 endTime);
event NumberSubmitted(address indexed player, uint256 number);
event ChallengeResolved(address indexed winner, uint256 prize);
event ResolverUpdated(address indexed newResolver);
```

### Custom Errors

```solidity
error NotPlayer();               // Caller is not player1 or player2
error WrongState();              // Action not allowed in the current state
error AlreadyJoined();           // Deposit slot already taken
error WrongStakeAmount();        // assets != stakeAmount
error SharesNonTransferable();   // Share transfer attempted
error NotResolver();             // Only the resolver can call this
error NoActiveIdentity();        // player2 does not have a valid IdentityNFT
error NotAfterEndTime();         // Challenge window has not ended yet
error AlreadySubmitted();        // Player already called submitNumber
error BothMustSubmit();          // resolveDispute called before both submitted
```

---

## 4. VaultFactory

**File:** `src/challenges/VaultFactory.sol`
**Inherits:** `Ownable`, `Pausable`

Deploys and tracks `ChallengeVault` contracts. Accepts a whitelist of ERC-20 tokens as valid staking assets. Callers must hold a valid IdentityNFT to create a challenge. Player2 identity is verified at deposit time inside the vault.

### Constructor

```solidity
constructor(
    address[] memory _initialTokens,  // Initial whitelist of ERC-20 token addresses
    address          _resolver,       // Default resolver for all created vaults
    address          _identityNFT     // IdentityNFT contract — callers must pass isValid()
)
```

### State Variables

| Variable | Type | Description |
|----------|------|-------------|
| `identityNFT` | `IIdentityNFT immutable` | Identity contract — checked at `createChallenge` |
| `resolver` | `address` | Default resolver passed to new vaults |
| `allVaults` | `address[]` | All vault addresses deployed by this factory |
| `isVault` | `mapping(address => bool)` | True for factory-deployed vaults |
| `vaultsByCreator` | `mapping(address => address[])` | Vaults created by a specific address |

---

### Read Functions

#### `getAllVaults() → address[]`

Returns all vault addresses deployed by this factory.

---

#### `getVaultsByCreator(address creator) → address[]`

Returns all vaults created by `creator`.

---

#### `getVaultCount() → uint256`

Returns the total number of vaults deployed.

---

#### `isAcceptedToken(address token) → bool`

Returns `true` if `token` is in the active whitelist.

---

#### `getAcceptedTokens() → address[]`

Returns all currently whitelisted token addresses.

---

#### `isVault(address vault) → bool`

Returns `true` if `vault` was deployed by this factory.

---

### Write Functions

#### `createChallenge(address token, uint256 stakeAmount, uint256 duration, string metadataURI) → address vault`

Deploy a new ChallengeVault. Caller becomes player1.

**Flow:**
1. Reverts `TokenNotAccepted` if `token` is not in the whitelist.
2. Reverts `NoActiveIdentity` if caller does not have a valid IdentityNFT.
3. Reverts `ZeroStake` if `stakeAmount == 0`.
4. Reverts `ZeroDuration` if `duration == 0`.
5. Deploys a new `ChallengeVault(token, stakeAmount, duration, metadataURI, resolver, caller, identityNFT)`.
6. Registers the vault in `allVaults`, `isVault`, `vaultsByCreator`.
7. Emits `VaultCreated`.
8. Returns the vault address.

**After calling:** caller must separately approve `stakeAmount` of `token` to the vault address, then call `vault.deposit(stakeAmount, self)` to join as player1.

**Guard:** `whenNotPaused`

---

### Admin Functions (onlyOwner)

#### `whitelistToken(address token)`

Add a token to the accepted whitelist. Reverts `ZeroAddress`. Emits `TokenWhitelisted`.

---

#### `removeToken(address token)`

Remove a token from the accepted whitelist. Existing vaults using this token are unaffected. Emits `TokenRemovedFromWhitelist`.

---

#### `setResolver(address _resolver)`

Update the default resolver for future vaults. Reverts `ZeroAddress`. Emits `ResolverUpdated`.

---

#### `pause() / unpause()`

Emergency pause — blocks `createChallenge`. Emits `Paused` / `Unpaused`.

---

### Events

```solidity
event VaultCreated(
    address indexed vault,
    address indexed creator,
    address indexed token,
    uint256 stakeAmount,
    uint256 duration,
    string  metadataURI
);
event ResolverUpdated(address indexed newResolver);
event TokenWhitelisted(address indexed token);
event TokenRemovedFromWhitelist(address indexed token);
```

### Custom Errors

```solidity
error ZeroAddress();                    // Address parameter is zero
error ZeroStake();                      // stakeAmount is zero
error ZeroDuration();                   // duration is zero
error NoActiveIdentity();               // Caller lacks a valid IdentityNFT
error TokenNotAccepted(address token);  // Token not in the whitelist
```

---

## 5. CourseNFT

**File:** `src/courses/CourseNFT.sol`
**Inherits:** `ERC721`, `ERC2981`, `Ownable`, `Pausable`, `ReentrancyGuard`

ERC-721 contract for a single course. Each token grants the holder access to private course content via a token-gated view function. Payments are in ETH. EIP-2981 royalties are configured for secondary sales.

### Constructor

```solidity
constructor(
    string  memory name,
    string  memory symbol,
    uint256        _mintPrice,         // ETH price per token (wei)
    uint256        _maxSupply,         // 0 = unlimited
    string  memory _baseTokenURI,      // Public IPFS metadata base URI
    string  memory _privateContentURI, // Private IPFS content URI (token-gated)
    address        _treasury,          // ETH recipient
    uint96         royaltyFeeBps       // e.g. 500 = 5%
)
```

### State Variables

| Variable | Type | Description |
|----------|------|-------------|
| `mintPrice` | `uint256` | ETH price per token (wei) |
| `maxSupply` | `uint256` | Max tokens; 0 = unlimited |
| `baseTokenURI` | `string` | Base URI for public metadata (used by `tokenURI`) |
| `privateContentURI` | `string` | Private course content URI — only token holders can read |
| `treasury` | `address` | Receives ETH payments on `withdraw` |

---

### Read Functions

#### `totalSupply() → uint256`

Returns the number of tokens minted so far.

---

#### `canMint() → bool`

Returns `true` if minting is currently possible:
- Contract is not paused
- `maxSupply == 0` (unlimited) or `totalSupply < maxSupply`

---

#### `getCourseContent(uint256 tokenId) → string`

Returns `privateContentURI`. Reverts `NotTokenHolder` if `ownerOf(tokenId) != msg.sender`.

This is the content gate: only NFT holders can read the private course material.

---

#### `mintPrice() → uint256`

Current ETH mint price in wei.

---

#### `maxSupply() → uint256`

Maximum token supply. `0` means unlimited.

---

### Write Functions

#### `mint() → uint256 tokenId`

Mint to `msg.sender`. Requires exactly `mintPrice` ETH attached.

1. Reverts `IncorrectPayment` if `msg.value != mintPrice`.
2. Reverts `MaxSupplyReached` if supply is exhausted.
3. Mints token to caller, emits `Minted`.

**Guard:** `whenNotPaused`, `nonReentrant`

---

#### `mintTo(address recipient) → uint256 tokenId`

Mint to `recipient`. Caller pays. Same rules as `mint`.

Emits `MintedTo(payer, recipient, tokenId)`.

**Guard:** `whenNotPaused`, `nonReentrant`

---

### Admin Functions (onlyOwner)

#### `setMintPrice(uint256 newPrice)`

Update the ETH mint price. Emits `MintPriceUpdated`.

---

#### `setPrivateContentURI(string newURI)`

Update the private content URI. Affects all existing token holders immediately. Emits `PrivateContentUpdated`.

---

#### `setBaseURI(string newURI)`

Update the public metadata base URI. Emits `BaseURIUpdated`.

---

#### `setTreasury(address newTreasury)`

Update the treasury address. Reverts `ZeroAddress`. Emits `TreasuryUpdated`.

---

#### `setRoyalty(address receiver, uint96 feeBps)`

Update the EIP-2981 default royalty (receiver and percentage).

---

#### `withdraw()`

Sweep the full ETH balance of the contract to `treasury`. Reverts `WithdrawalFailed` on transfer failure. Guard: `nonReentrant`.

---

#### `pause() / unpause()`

Emergency pause — blocks `mint` and `mintTo`. Emits `Paused` / `Unpaused`.

---

### Events

```solidity
event Minted(address indexed to, uint256 indexed tokenId);
event MintedTo(address indexed payer, address indexed recipient, uint256 indexed tokenId);
event MintPriceUpdated(uint256 newPrice);
event PrivateContentUpdated(string newURI);
event BaseURIUpdated(string newURI);
event TreasuryUpdated(address indexed newTreasury);
```

### Custom Errors

```solidity
error IncorrectPayment();    // msg.value != mintPrice
error MaxSupplyReached();    // totalSupply >= maxSupply
error NotTokenHolder();      // Caller does not own the token
error WithdrawalFailed();    // ETH transfer to treasury failed
error ZeroAddress();         // treasury set to address(0)
```

---

## 6. CourseFactory

**File:** `src/courses/CourseFactory.sol`
**Inherits:** `Ownable`

Factory that deploys `CourseNFT` contracts and tracks them. Ownership of each deployed course is transferred to the caller immediately after deployment.

### Constructor

```solidity
constructor(address _defaultTreasury)
```

Reverts `ZeroAddress` if `_defaultTreasury == address(0)`.

### State Variables

| Variable | Type | Description |
|----------|------|-------------|
| `defaultTreasury` | `address` | Fallback treasury when course creator passes `address(0)` |
| `isDeployedCourse` | `mapping(address => bool)` | True for factory-deployed CourseNFT contracts |

---

### Read Functions

#### `getAllCourses() → address[]`

Returns all deployed course addresses.

---

#### `getCoursesByCreator(address creator) → address[]`

Returns all course addresses deployed by `creator`.

---

#### `getCourseCount() → uint256`

Returns the total number of courses deployed.

---

#### `getCourseAtIndex(uint256 index) → address`

Returns the course address at `index`. Reverts `IndexOutOfBounds` if out of range.

---

#### `isDeployedCourse(address course) → bool`

Returns `true` if `course` was deployed by this factory.

---

### Write Functions

#### `createCourse(string name, string symbol, uint256 mintPrice, uint256 maxSupply, string baseURI, string privateContentURI, address treasury, uint96 royaltyFeeBps) → address`

Deploy a new `CourseNFT` and transfer ownership to `msg.sender`.

**Parameters:**

| Parameter | Description |
|-----------|-------------|
| `name` | ERC-721 name (e.g. `"Python 101"`) |
| `symbol` | ERC-721 symbol (e.g. `"PY101"`) |
| `mintPrice` | ETH price per token in wei |
| `maxSupply` | Max token supply; `0` = unlimited |
| `baseURI` | Public IPFS metadata base URI |
| `privateContentURI` | Private IPFS content URI (token-gated) |
| `treasury` | ETH recipient; `address(0)` uses `defaultTreasury` |
| `royaltyFeeBps` | EIP-2981 royalty in basis points (e.g. `500` = 5%) |

**Flow:**
1. Uses `defaultTreasury` if `treasury == address(0)`.
2. Deploys `CourseNFT` with the provided parameters.
3. Transfers ownership to `msg.sender`.
4. Registers the address in `courses`, `coursesByCreator`, `isDeployedCourse`.
5. Emits `CourseCreated`.
6. Returns the course address.

---

### Admin Functions (onlyOwner)

#### `setDefaultTreasury(address newTreasury)`

Update the fallback treasury. Reverts `ZeroAddress`. Emits `DefaultTreasuryUpdated`.

---

### Events

```solidity
event CourseCreated(
    address indexed courseAddress,
    address indexed creator,
    string  name,
    string  symbol,
    uint256 mintPrice,
    uint256 maxSupply
);
event DefaultTreasuryUpdated(address indexed newTreasury);
```

### Custom Errors

```solidity
error ZeroAddress();
error IndexOutOfBounds(uint256 index, uint256 length);
```

---

## 7. Deploy Commands

### Prerequisites

```bash
cp .env.example .env
# Fill: PRIVATE_KEY, BASE_SEPOLIA_RPC_URL, BASESCAN_API_KEY,
#       DEFAULT_TREASURY, RESOLVER_ADDRESS,
#       IDENTITY_NAME, IDENTITY_SYMBOL, IDENTITY_CITY,
#       TOKEN_1 + prices, ACCEPTED_TOKEN_1
source .env
```

### Build & Test

```bash
forge build --sizes
forge test -vvv
forge coverage
forge test --gas-report
```

### Deploy to Base Sepolia

Deploy IdentityNFT first — VaultFactory needs its address.

```bash
# Step 1: IdentityNFT
forge script script/DeployIdentityNFT.s.sol:DeployIdentityNFT \
  --rpc-url $BASE_SEPOLIA_RPC_URL --private-key $PRIVATE_KEY \
  --broadcast --verify --verifier blockscout \
  --verifier-url https://base-sepolia.blockscout.com/api/

# Set IDENTITY_NFT=<address> in .env, then:

# Step 2: VaultFactory
forge script script/DeployVaultFactory.s.sol:DeployVaultFactory \
  --rpc-url $BASE_SEPOLIA_RPC_URL --private-key $PRIVATE_KEY \
  --broadcast --verify --verifier blockscout \
  --verifier-url https://base-sepolia.blockscout.com/api/

# Step 3: CourseFactory
forge script script/DeployFactory.s.sol:DeployFactory \
  --rpc-url $BASE_SEPOLIA_RPC_URL --private-key $PRIVATE_KEY \
  --broadcast --verify --verifier blockscout \
  --verifier-url https://base-sepolia.blockscout.com/api/

# Extract all addresses after deployment
node script/extract-addresses.js 84532
```

### Useful cast commands

```bash
# Mint an identity card (after token approval)
cast send $IDENTITY_NFT "mint(string,uint8,address)" \
  "ipfs://QmMetadata" 0 $TOKEN_1 \
  --private-key $PRIVATE_KEY --rpc-url $BASE_SEPOLIA_RPC_URL

# Check identity validity
cast call $IDENTITY_NFT "isValid(address)" $USER_ADDRESS \
  --rpc-url $BASE_SEPOLIA_RPC_URL

# Create a challenge vault (requires identity + token approval for staking later)
cast send $VAULT_FACTORY \
  "createChallenge(address,uint256,uint256,string)" \
  $ACCEPTED_TOKEN_1 $STAKE_AMOUNT 86400 "ipfs://QmChallenge" \
  --private-key $PRIVATE_KEY --rpc-url $BASE_SEPOLIA_RPC_URL

# Create a course
cast send $FACTORY_ADDRESS \
  "createCourse(string,string,uint256,uint256,string,string,address,uint96)" \
  "Python 101" "PY101" 100000000000000000 100 \
  "ipfs://QmPublic/" "ipfs://QmPrivate/" $DEFAULT_TREASURY 500 \
  --private-key $PRIVATE_KEY --rpc-url $BASE_SEPOLIA_RPC_URL
```

---

**Last Updated:** February 2026
**Solidity:** `^0.8.27`
**License:** MIT
