# Technical Reference — Gaming Tower + Courses NFT

> Solidity `^0.8.27` · OpenZeppelin v5
> Networks: Base Sepolia (84532) / Base Mainnet (8453)
> Deployed addresses: [`deployments/addresses.json`](../deployments/addresses.json)

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [IdentityNFTFactory](#2-identitynftfactory)
3. [IdentityNFT](#3-identitynft)
4. [ChallengeVault](#4-challengevault)
5. [VaultFactory](#5-vaultfactory)
6. [CourseNFT](#6-coursenft)
7. [CourseFactory](#7-coursefactory)
8. [Deploy Commands](#8-deploy-commands)

---

## 1. Architecture Overview

```
Gaming Tower + Courses NFT Platform
│
├── IdentityNFTFactory ──deploys──► IdentityNFT  (city collection, subscription card)
│
├── VaultFactory       ──deploys──► ChallengeVault (token escrow, EIP-4626, number game)
│
└── CourseFactory      ──deploys──► CourseNFT (ERC-721, ETH payments, ERC-2981 royalties)
```

**Payment currencies:**
- `IdentityNFT` — any whitelisted ERC-20 token (1UP, USDC, EUROC — configured per collection)
- `ChallengeVault` — whitelisted ERC-20 token chosen at challenge creation
- `CourseNFT` — ETH (native)

**Access control:** A valid (active, non-suspended) IdentityNFT is the only gate to create or join a challenge.

**City collections:** Each `IdentityNFT` is an independent city-specific collection (e.g. "Medellín"). The admin deploys them on-chain via `IdentityNFTFactory.deployCollection()` — no per-city CLI script needed.

**Factory pattern:** `IdentityNFTFactory` keeps ownership of collections with the protocol admin. `CourseFactory` and `VaultFactory` transfer ownership of each child to the caller on creation.

**Challenge resolution:** Players submit a number after the challenge window ends. Highest number wins. Resolver breaks ties.

---

## 2. IdentityNFTFactory

**File:** `src/IdentityNFTFactory.sol`
**Inherits:** `Ownable`

Admin-only factory that deploys `IdentityNFT` city collections on-chain. Deployed once per network. Non-technical admins can then call `deployCollection()` from a frontend wallet to spin up new city collections without running CLI scripts. Ownership of each deployed collection is transferred immediately to `factory.owner()` (the protocol admin), so all admin functions on every collection are accessible through a single wallet.

### Constructor

```solidity
constructor()
```

Sets `msg.sender` as the owner (protocol admin).

### State Variables

| Variable | Type | Description |
|----------|------|-------------|
| `allCollections` | `address[]` | All deployed IdentityNFT collection addresses |
| `isCollection` | `mapping(address => bool)` | True for factory-deployed collections |

---

### Read Functions

#### `getAllCollections() → address[]`

Returns all IdentityNFT collection addresses deployed by this factory.

---

#### `getCollectionCount() → uint256`

Returns the total number of collections deployed.

---

#### `isCollection(address) → bool`

Returns `true` if the address was deployed by this factory.

---

### Write Functions

#### `deployCollection(string name, string symbol, string city, address treasury, bool soulbound, IdentityNFT.InitialTokenConfig[] initialTokens) → address collection`

Deploy a new `IdentityNFT` city collection. Restricted to the factory owner.

**Parameters:**

| Parameter | Description |
|-----------|-------------|
| `name` | ERC-721 name (e.g. `"Entry - Medellín"`) |
| `symbol` | ERC-721 symbol (e.g. `"EMDE"`) |
| `city` | City label stored on-chain (e.g. `"Medellín"`) |
| `treasury` | Address that receives all mint and renewal fees |
| `soulbound` | If `true`: tokens in this collection are non-transferable |
| `initialTokens` | Array of `{ token, mintPrice, monthlyPrice, yearlyPrice }` — at least one required |

**Flow:**
1. Deploys a new `IdentityNFT(name, symbol, city, treasury, soulbound, initialTokens)`.
2. Transfers ownership of the collection to `factory.owner()` (the protocol admin).
3. Registers the address in `allCollections` and `isCollection`.
4. Emits `CollectionDeployed`.
5. Returns the collection address.

**Access:** `onlyOwner`

---

### Events

```solidity
event CollectionDeployed(
    address indexed collection,
    string  name,
    string  symbol,
    string  city,
    address indexed treasury
);
```

---

## 3. IdentityNFT

**File:** `src/IdentityNFT.sol`
**Inherits:** `ERC721`, `Ownable`, `Pausable`, `ReentrancyGuard`

Renewable subscription-based profile NFT ("Identity Card") for the gaming tower. One card per address. Each deployment is city-specific. Payments are accepted in any configured ERC-20 token, each with its own price schedule. Admin can suspend any card regardless of payment status. Can be configured as soulbound (non-transferable).

Deployed via `IdentityNFTFactory.deployCollection()`. Owned by the protocol admin (factory owner).

### Constructor

```solidity
constructor(
    string  memory _name,
    string  memory _symbol,
    string  memory _city,           // City label stored on-chain
    address        _treasury,       // Receives all mint and renewal fees
    bool           _soulbound,      // If true: tokens cannot be transferred
    InitialTokenConfig[] memory _initialTokens
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
enum Period { Monthly, Yearly }            // Chosen at mint and every renewal
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

- `tokenIdOf[user] != 0` (card exists)
- `!suspended[tokenId]` (not admin-suspended)
- `expiryOf[tokenId] >= block.timestamp` (subscription active)

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

Returns the stored per-token IPFS metadata URI. Reverts if token does not exist.

---

#### `totalSupply() → uint256`

Total identity cards minted in this collection.

---

#### `getAcceptedTokens() → address[]`

Returns all token addresses that have ever been configured (enabled or disabled).

---

#### `tokenConfigs(address token) → TokenConfig`

Returns the full price schedule for a given payment token.

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

**Requires:** caller has approved at least `mintPrice` of `token` to this contract.
**Guard:** `whenNotPaused`, `nonReentrant`

---

#### `renew(uint256 tokenId, Period period, address token)`

Renew a subscription. Anyone can pay (sponsorship supported).

**Renewal logic:**
- Still active → `newExpiry = expiryOf[tokenId] + period` (paid days preserved)
- Already expired → `newExpiry = block.timestamp + period` (fresh start, no grace period)

1. Reverts `NoIdentityFound` if token does not exist.
2. Reverts `TokenNotAccepted` if `token` is not enabled.
3. Pulls renewal price from caller → treasury.
4. Updates `expiryOf[tokenId]`.
5. Emits `IdentityRenewed`.

**Note:** The token used for renewal may differ from the token used at mint.
**Guard:** `whenNotPaused`, `nonReentrant`

---

#### `updateMetadata(uint256 tokenId, string newURI)`

Update the IPFS metadata URI. Only the token owner can call this.
Reverts `NotTokenOwner`. Emits `MetadataUpdated`.

---

### Admin Functions (onlyOwner)

#### `suspend(uint256 tokenId)`

Immediately blocks platform access regardless of payment. Reverts `NoIdentityFound`. Emits `Suspended`.

#### `unsuspend(uint256 tokenId)`

Restores a suspended card. Emits `Unsuspended`.

#### `setTokenConfig(address token, uint256 mintPrice, uint256 monthlyPrice, uint256 yearlyPrice)`

Add or update a payment token. Re-enables a previously disabled token. Reverts `ZeroAddress`. Emits `TokenConfigSet`.

#### `disableToken(address token)`

Disable a payment token. Disabled tokens cannot be used for new payments. Emits `TokenDisabled`.

#### `setTreasury(address newTreasury)`

Update the treasury address. Reverts `ZeroAddress`. Emits `TreasuryUpdated`.

#### `pause() / unpause()`

Emergency pause — blocks `mint` and `renew`.

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
error AlreadyHasIdentity();
error NoIdentityFound();
error NotTokenOwner();
error SoulboundToken();
error ZeroAddress();
error TokenNotAccepted(address token);
```

---

## 4. ChallengeVault

**File:** `src/challenges/ChallengeVault.sol`
**Inherits:** `ERC4626`, `ERC20`, `Ownable`, `Pausable`, `ReentrancyGuard`

EIP-4626 escrow vault for a single two-player challenge. Players stake equal amounts of an ERC-20 token. After the challenge duration ends, each player submits a number — the higher number wins. In case of a tie, the resolver decides. Shares are non-transferable (soulbound). Withdrawals are disabled; funds are released only through resolution.

### State Machine

```
OPEN ──(player2 deposits)──► ACTIVE ──(both submit numbers, highest wins)──► RESOLVED
                                │
                                └──(both submit same number → resolver)──► RESOLVED
```

### Constructor

```solidity
constructor(
    IERC20  _token,
    uint256 _stakeAmount,    // Exact amount each player must deposit (token wei)
    uint256 _duration,       // Challenge window in seconds (starts when ACTIVE)
    string  memory _metadataURI,
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
| `identityNFT` | `IIdentityNFT immutable` | Identity contract — checked when player2 deposits |
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

- `0` if state is not `OPEN`
- `0` if `account == player1` and player1 already deposited
- `0` if `account != player1` and player2 slot is taken
- `stakeAmount` otherwise

#### `maxMint(address account) → uint256`

Identical to `maxDeposit` (1:1 share/asset ratio).

#### `maxWithdraw(address) → uint256`

Always `0`. Use `submitNumber` to resolve.

#### `maxRedeem(address) → uint256`

Always `0`.

---

### Write Functions

#### `deposit(uint256 assets, address receiver) → uint256 shares`

Join the challenge by depositing exactly `stakeAmount` tokens.

**Player1 path (`receiver == player1`):**
1. Reverts `WrongState` if not OPEN.
2. Reverts `WrongStakeAmount` if `assets != stakeAmount`.
3. Reverts `AlreadyJoined` if player1 already deposited.
4. Transfers tokens, mints shares, emits `PlayerJoined`.

**Player2 path (`receiver != player1`):**
1. Same state and amount checks.
2. Reverts `NoActiveIdentity` if `identityNFT.isValid(receiver)` is false.
3. Reverts `AlreadyJoined` if player2 slot is already taken.
4. Sets `player2 = receiver`.
5. Once both players deposited: sets `state = ACTIVE`, `endTime = now + challengeDuration`, emits `ChallengeActivated`.

**Requires:** caller has approved at least `stakeAmount` to this vault.
**Guard:** `nonReentrant`, `whenNotPaused`

---

#### `submitNumber(uint256 number)`

Submit your number after the challenge window ends. Callable once per player.

1. Reverts `WrongState` if not ACTIVE.
2. Reverts `NotAfterEndTime` if `block.timestamp < endTime`.
3. Reverts `NotPlayer` if caller is not player1 or player2.
4. Reverts `AlreadySubmitted` if caller already submitted.
5. Records number and submission flag. Emits `NumberSubmitted`.
6. If both submitted:
   - `n1 > n2` → player1 wins
   - `n2 > n1` → player2 wins
   - Tie → state stays ACTIVE, resolver must call `resolveDispute`

**On win:** Burns both players' shares, transfers full prize (`stakeAmount × 2`) to winner. Emits `ChallengeResolved`.

---

#### `resolveDispute(address _winner)`

Resolver-only. Breaks a tie — callable only when both players submitted the same number.

1. Reverts `NotResolver` if caller is not `resolver`.
2. Reverts `WrongState` if not ACTIVE.
3. Reverts `BothMustSubmit` if either player has not submitted.
4. Reverts `"Not a tie"` if numbers differ.
5. Resolves and transfers prize to `_winner`.

---

### Admin Functions (onlyOwner)

#### `setResolver(address _resolver)`

Update the resolver. Emits `ResolverUpdated`.

#### `pause() / unpause()`

Emergency pause — blocks `deposit`.

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
error NotPlayer();
error WrongState();
error AlreadyJoined();
error WrongStakeAmount();
error SharesNonTransferable();
error NotResolver();
error NoActiveIdentity();
error NotAfterEndTime();
error AlreadySubmitted();
error BothMustSubmit();
```

---

## 5. VaultFactory

**File:** `src/challenges/VaultFactory.sol`
**Inherits:** `Ownable`, `Pausable`

Deploys and tracks `ChallengeVault` contracts. Accepts a whitelist of ERC-20 tokens as valid staking assets. Callers must hold a valid IdentityNFT to create a challenge. Player2 identity is verified at deposit time inside the vault.

### Constructor

```solidity
constructor(
    address[] memory _initialTokens,  // Initial ERC-20 token whitelist
    address          _resolver,       // Default resolver for all vaults
    address          _identityNFT     // IdentityNFT contract — callers must pass isValid()
)
```

### State Variables

| Variable | Type | Description |
|----------|------|-------------|
| `identityNFT` | `IIdentityNFT immutable` | Checked at `createChallenge` |
| `resolver` | `address` | Default resolver passed to new vaults |
| `allVaults` | `address[]` | All vault addresses deployed by this factory |
| `isVault` | `mapping(address => bool)` | True for factory-deployed vaults |
| `vaultsByCreator` | `mapping(address => address[])` | Vaults per creator |

---

### Read Functions

#### `getAllVaults() → address[]`

All vault addresses deployed by this factory.

#### `getVaultsByCreator(address creator) → address[]`

Vaults deployed by a specific creator.

#### `getVaultCount() → uint256`

Total vaults deployed.

#### `isAcceptedToken(address token) → bool`

True if `token` is in the active whitelist.

#### `getAcceptedTokens() → address[]`

All currently whitelisted token addresses.

#### `isVault(address vault) → bool`

True if `vault` was deployed by this factory.

---

### Write Functions

#### `createChallenge(address token, uint256 stakeAmount, uint256 duration, string metadataURI) → address vault`

Deploy a new `ChallengeVault`. Caller becomes player1.

1. Reverts `TokenNotAccepted` if `token` is not whitelisted.
2. Reverts `NoActiveIdentity` if caller lacks a valid IdentityNFT.
3. Reverts `ZeroStake` if `stakeAmount == 0`.
4. Reverts `ZeroDuration` if `duration == 0`.
5. Deploys vault, registers it, emits `VaultCreated`, returns vault address.

**After calling:** approve `stakeAmount` of `token` to the vault, then call `vault.deposit(stakeAmount, self)` to join as player1.
**Guard:** `whenNotPaused`

---

### Admin Functions (onlyOwner)

#### `whitelistToken(address token)`

Add a token to the whitelist. Reverts `ZeroAddress`. Emits `TokenWhitelisted`.

#### `removeToken(address token)`

Remove a token from the whitelist. Existing vaults are unaffected. Emits `TokenRemovedFromWhitelist`.

#### `setResolver(address _resolver)`

Update the default resolver for future vaults. Reverts `ZeroAddress`. Emits `ResolverUpdated`.

#### `pause() / unpause()`

Emergency pause — blocks `createChallenge`.

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
error ZeroAddress();
error ZeroStake();
error ZeroDuration();
error NoActiveIdentity();
error TokenNotAccepted(address token);
```

---

## 6. CourseNFT

**File:** `src/courses/CourseNFT.sol`
**Inherits:** `ERC721`, `ERC2981`, `Ownable`, `Pausable`, `ReentrancyGuard`

ERC-721 contract for a single course. Each token grants the holder access to private course content via a token-gated view. Payments are in ETH. EIP-2981 royalties are configured for secondary sales.

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
| `baseTokenURI` | `string` | Base URI for public metadata |
| `privateContentURI` | `string` | Private content URI — only token holders can read |
| `treasury` | `address` | Receives ETH on `withdraw` |

---

### Read Functions

#### `totalSupply() → uint256`

Tokens minted so far.

#### `canMint() → bool`

True if not paused and supply is not exhausted.

#### `getCourseContent(uint256 tokenId) → string`

Returns `privateContentURI`. Reverts `NotTokenHolder` if caller does not own the token.

---

### Write Functions

#### `mint() → uint256 tokenId`

Mint to `msg.sender`. Requires exactly `mintPrice` ETH.
Reverts `IncorrectPayment` or `MaxSupplyReached`. Emits `Minted`.
**Guard:** `whenNotPaused`, `nonReentrant`

#### `mintTo(address recipient) → uint256 tokenId`

Mint to `recipient`. Caller pays. Same rules as `mint`. Emits `MintedTo`.
**Guard:** `whenNotPaused`, `nonReentrant`

---

### Admin Functions (onlyOwner)

#### `setMintPrice(uint256 newPrice)` — Emits `MintPriceUpdated`
#### `setPrivateContentURI(string newURI)` — Emits `PrivateContentUpdated` (affects all existing holders immediately)
#### `setBaseURI(string newURI)` — Emits `BaseURIUpdated`
#### `setTreasury(address newTreasury)` — Reverts `ZeroAddress`. Emits `TreasuryUpdated`
#### `setRoyalty(address receiver, uint96 feeBps)` — Updates EIP-2981 default royalty
#### `withdraw()` — Sweeps ETH balance to treasury. Guard: `nonReentrant`
#### `pause() / unpause()` — Blocks `mint` and `mintTo`

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
error IncorrectPayment();
error MaxSupplyReached();
error NotTokenHolder();
error WithdrawalFailed();
error ZeroAddress();
```

---

## 7. CourseFactory

**File:** `src/courses/CourseFactory.sol`
**Inherits:** `Ownable`

Deploys `CourseNFT` contracts and tracks them. Ownership of each deployed course is transferred to the caller immediately after deployment.

### Constructor

```solidity
constructor(address _defaultTreasury)
```

### State Variables

| Variable | Type | Description |
|----------|------|-------------|
| `defaultTreasury` | `address` | Fallback treasury when creator passes `address(0)` |
| `isDeployedCourse` | `mapping(address => bool)` | True for factory-deployed CourseNFTs |

---

### Read Functions

#### `getAllCourses() → address[]`

All deployed course addresses.

#### `getCoursesByCreator(address creator) → address[]`

Courses deployed by a specific creator.

#### `getCourseCount() → uint256`

Total courses deployed.

#### `getCourseAtIndex(uint256 index) → address`

Course at index. Reverts `IndexOutOfBounds` if out of range.

#### `isDeployedCourse(address course) → bool`

True if deployed by this factory.

---

### Write Functions

#### `createCourse(string name, string symbol, uint256 mintPrice, uint256 maxSupply, string baseURI, string privateContentURI, address treasury, uint96 royaltyFeeBps) → address`

Deploy a new `CourseNFT` and transfer ownership to `msg.sender`.

| Parameter | Description |
|-----------|-------------|
| `name` | ERC-721 name |
| `symbol` | ERC-721 symbol |
| `mintPrice` | ETH price per token in wei |
| `maxSupply` | Max token supply; `0` = unlimited |
| `baseURI` | Public IPFS metadata base URI |
| `privateContentURI` | Private IPFS content URI (token-gated) |
| `treasury` | ETH recipient; `address(0)` uses `defaultTreasury` |
| `royaltyFeeBps` | EIP-2981 royalty in basis points (e.g. `500` = 5%) |

Emits `CourseCreated`.

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

## 8. Deploy Commands

### Prerequisites

```bash
cp .env.example .env
# Fill: PRIVATE_KEY, BASE_SEPOLIA_RPC_URL, BASESCAN_API_KEY,
#       DEFAULT_TREASURY, RESOLVER_ADDRESS, ACCEPTED_TOKEN_1
source .env
```

### Build & Test

```bash
forge build --sizes
forge test -vvv
forge coverage
forge test --gas-report
```

### Deploy to Base Sepolia (recommended — using deploy.sh)

```bash
# Step 1: IdentityNFTFactory (once)
./script/deploy.sh base-sepolia --step identity-factory
# → set IDENTITY_NFT_FACTORY=<address> in .env
# → call deployCollection() from admin frontend to create first city
# → set IDENTITY_NFT=<collection address> in .env

# Step 2: VaultFactory
./script/deploy.sh base-sepolia --step vault-factory
# → set VAULT_FACTORY_ADDRESS=<address> in .env

# Step 3: CourseFactory
./script/deploy.sh base-sepolia --step course-factory
# → set FACTORY_ADDRESS=<address> in .env
```

Each step runs `node script/extract-addresses.js <chainId>` automatically.

### Deploy a new city collection (after IdentityNFTFactory is live)

Via `cast` (or from the admin frontend panel):

```bash
cast send $IDENTITY_NFT_FACTORY \
  "deployCollection(string,string,string,address,bool,(address,uint256,uint256,uint256)[])" \
  "Entry - Medellín" "EMDE" "Medellín" $DEFAULT_TREASURY false \
  "[(0x05cb1e3ba6102b097c0ad913c8b82ac76e7df73f,50000000000000000000,20000000000000000000,200000000000000000000)]" \
  --private-key $PRIVATE_KEY --rpc-url $BASE_SEPOLIA_RPC_URL
```

### Useful cast commands

```bash
# Check identity validity
cast call $IDENTITY_NFT "isValid(address)" $USER_ADDRESS \
  --rpc-url $BASE_SEPOLIA_RPC_URL

# Create a challenge vault (after identity approval + staking token approval)
cast send $VAULT_FACTORY_ADDRESS \
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
