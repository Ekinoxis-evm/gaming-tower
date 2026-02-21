# Gaming Tower + Courses NFT

> A decentralized gaming and education platform on Base.
> Players stake tokens to compete in number-submission challenges and maintain renewable identity profiles. Course creators monetize content through ETH-priced ERC-721 NFTs.

[![Solidity](https://img.shields.io/badge/Solidity-0.8.27-363636?logo=solidity)](https://soliditylang.org/)
[![Foundry](https://img.shields.io/badge/Built%20with-Foundry-000000)](https://getfoundry.sh/)
[![Base](https://img.shields.io/badge/Deployed%20on-Base%20Sepolia%20%7C%20Mainnet-0052FF)](https://docs.base.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

---

## Architecture

```
Gaming Tower
├── IdentityNFTFactory ──deploys──► IdentityNFT  (city collection, subscription card, multi-token)
├── VaultFactory       ──deploys──► ChallengeVault (EIP-4626, token escrow, 2-player number game)

Courses Platform
└── CourseFactory      ──deploys──► CourseNFT    (ERC-721, ETH payment, ERC-2981 royalties)
```

### Key rules

- Gaming actions (challenge staking, identity mint/renewal) are paid in **whitelisted ERC-20 tokens** (1UP, USDC, EUROC — configured per deployment).
- ETH is used only by **CourseNFT**.
- A valid (active, non-suspended) **IdentityNFT** is the only requirement to create or join a challenge.
- Each **IdentityNFT** collection is city-specific (e.g. "Medellín", "Bogotá") and is deployed on-chain via `IdentityNFTFactory.deployCollection()`.
- 1 1UP = 1 000 COP (platform display convention).

---

## Contracts

| Contract | Description | Payment |
|----------|-------------|---------|
| `IdentityNFTFactory` | Admin-only factory — deploys city IdentityNFT collections on-chain | — |
| `IdentityNFT` | Subscription profile card — city-based, monthly/yearly renewal, multi-token, admin suspend | ERC-20 token (per-token config) |
| `ChallengeVault` | EIP-4626 escrow for two-player number-submission challenges | ERC-20 token (whitelisted) |
| `VaultFactory` | Deploys & tracks ChallengeVaults; gates creation on IdentityNFT | — |
| `CourseNFT` | ERC-721 course NFT with token-gated content + ERC-2981 royalties | ETH |
| `CourseFactory` | Deploys & tracks CourseNFT contracts | — |

---

## Token Addresses

| Token | Network | Address |
|-------|---------|---------|
| 1UP | Base Sepolia | `0x05cb1e3ba6102b097c0ad913c8b82ac76e7df73f` |
| 1UP | Base Mainnet | `0x036CbD53842c5426634e7929541eC2318f3dCF7e` |
| USDC | Base Mainnet | `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` |
| EUROC | Base Mainnet | `0x60a3E35Cc302bFA44Cb288Bc5a4F316Fdb1adb42` |

---

## Deployed Addresses

Contract addresses per network live in [`deployments/addresses.json`](deployments/addresses.json). This file is updated automatically after each deploy step.

---

## Quick Start

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Wallet with Base Sepolia ETH (testnet) or ETH + payment tokens (mainnet)
- Node.js ≥ 18 (for the extraction scripts)

### 1. Install

```bash
git clone https://github.com/yourusername/courses_nft.git
cd courses_nft
forge install
```

### 2. Configure

```bash
cp .env.example .env
```

Fill `.env` — key variables:

```env
PRIVATE_KEY=0x...
BASESCAN_API_KEY=your_key

# Network RPC
BASE_SEPOLIA_RPC_URL=https://sepolia.base.org
BASE_RPC_URL=https://mainnet.base.org

# Shared
DEFAULT_TREASURY=0xYourTreasury
RESOLVER_ADDRESS=0xYourResolver

# Payment tokens for VaultFactory staking (ACCEPTED_TOKEN_1 required)
ACCEPTED_TOKEN_1=0x05cb1e3ba6102b097c0ad913c8b82ac76e7df73f

# Filled in after each deploy step:
# IDENTITY_NFT_FACTORY=0x...
# IDENTITY_NFT=0x...          (address of first city collection)
# VAULT_FACTORY_ADDRESS=0x...
# FACTORY_ADDRESS=0x...
```

### 3. Test

```bash
forge test -vvv
forge coverage
forge test --gas-report
```

---

## Deploy & Verify

### Deploy order

```
IdentityNFTFactory  →  (deployCollection via frontend/cast)  →  VaultFactory  →  CourseFactory
```

Infrastructure contracts are deployed once per network using `deploy.sh`. City IdentityNFT collections are deployed on-chain by the admin calling `IdentityNFTFactory.deployCollection()` — no CLI script needed per city.

---

### Step 0 — Build & extract ABIs

```bash
source .env      # load vars into shell (required for CLI flags)
forge build
node script/extract-abis.js
```

> `source .env` must be run in every new terminal session. Foundry loads `.env` automatically for `vm.env*()` inside scripts, but **not** for CLI flags (`--rpc-url`, `--private-key`, `--etherscan-api-key`).

---

### Step 1 — Deploy IdentityNFTFactory

Deployed once. After this, city collections are created from the frontend or via `cast`.

```bash
./script/deploy.sh base-sepolia --step identity-factory
# or for mainnet:
./script/deploy.sh base --step identity-factory
```

Set the printed address in `.env`:

```env
IDENTITY_NFT_FACTORY=0x<printed address>
```

---

### Step 1b — Deploy first city collection

Call `IdentityNFTFactory.deployCollection()` from the admin frontend panel, or via `cast`:

```bash
cast send $IDENTITY_NFT_FACTORY \
  "deployCollection(string,string,string,address,bool,(address,uint256,uint256,uint256)[])" \
  "Entry - Medellín" "EMDE" "Medellín" $DEFAULT_TREASURY false \
  "[(0x05cb1e3ba6102b097c0ad913c8b82ac76e7df73f,50000000000000000000,20000000000000000000,200000000000000000000)]" \
  --private-key $PRIVATE_KEY --rpc-url $BASE_SEPOLIA_RPC_URL
```

Set the deployed collection address in `.env`:

```env
IDENTITY_NFT=0x<collection address>
```

---

### Step 2 — Deploy VaultFactory

Requires `IDENTITY_NFT` and `ACCEPTED_TOKEN_1` in `.env`.

```bash
./script/deploy.sh base-sepolia --step vault-factory
```

Set the printed address in `.env`:

```env
VAULT_FACTORY_ADDRESS=0x<printed address>
```

---

### Step 3 — Deploy CourseFactory

```bash
./script/deploy.sh base-sepolia --step course-factory
```

Set the printed address in `.env`:

```env
FACTORY_ADDRESS=0x<printed address>
```

---

### Verifier options

The `deploy.sh` script uses Basescan (etherscan) by default. To use a different verifier, pass the forge flags directly:

#### Blockscout

```bash
forge script script/DeployIdentityNFTFactory.s.sol:DeployIdentityNFTFactory \
  --rpc-url $BASE_SEPOLIA_RPC_URL --private-key $PRIVATE_KEY \
  --broadcast --verify --verifier blockscout \
  --verifier-url https://base-sepolia.blockscout.com/api/
```

#### Sourcify

```bash
--verify --verifier sourcify
```

| Network | Basescan | Blockscout |
|---------|----------|------------|
| Base Sepolia | https://sepolia.basescan.org | https://base-sepolia.blockscout.com |
| Base Mainnet | https://basescan.org | https://base.blockscout.com |

---

## Deployment Artifacts

```
deployments/
├── addresses.json          # contract addresses per chain (auto-generated)
└── abi/
    ├── IdentityNFTFactory.json
    ├── IdentityNFT.json
    ├── VaultFactory.json
    ├── ChallengeVault.json
    ├── CourseFactory.json
    └── CourseNFT.json
```

### Extraction scripts

| Script | When to run | What it does |
|--------|-------------|--------------|
| `node script/extract-abis.js` | After `forge build` | Copies ABI arrays from `out/` → `deployments/abi/` |
| `node script/extract-addresses.js [chainId]` | After each deploy step | Reads `broadcast/` run files → merges into `deployments/addresses.json` |

The `deploy.sh` script runs `extract-addresses.js` automatically after each step.

### Frontend usage (viem / wagmi)

```typescript
import addresses            from '@/deployments/addresses.json';
import IdentityNFTFactoryAbi from '@/deployments/abi/IdentityNFTFactory.json';
import CourseFactoryAbi      from '@/deployments/abi/CourseFactory.json';

const chainId = '84532';
const { contracts } = addresses[chainId];

const { data } = useReadContract({
  address: contracts.CourseFactory,
  abi: CourseFactoryAbi,
  functionName: 'getCourseCount',
});
```

---

## Usage

### Identity flow

```
Admin (once per city):
  IdentityNFTFactory.deployCollection(name, symbol, city, treasury, soulbound, tokens)
  → new IdentityNFT collection, owned by factory admin

User:
  1. Approve ERC-20 token to IdentityNFT contract
  2. IdentityNFT.mint(metadataURI, period, token)
     → one card per address, subscription window starts (30 or 365 days)
  3. IdentityNFT.renew(tokenId, period, token) before expiry
     → active: extends from current expiry (paid days preserved)
     → expired: restarts from block.timestamp
```

### Challenge flow

```
1. Creator (with valid IdentityNFT) calls:
   VaultFactory.createChallenge(token, stake, duration, metadataURI)
   → ChallengeVault deployed, creator becomes player1

2. Creator approves token → vault address
   Creator calls vault.deposit(stake, self)           [state: OPEN]

3. Challenger (with valid IdentityNFT) approves token → vault address
   Challenger calls vault.deposit(stake, self)
   → vault activates, endTime set                    [state: ACTIVE]

4. After endTime: each player calls vault.submitNumber(number)
   → highest number wins automatically               [state: RESOLVED]

5. If both submit the same number (tie):
   resolver calls vault.resolveDispute(winnerAddress) [state: RESOLVED]
```

### Course flow

```
1. Creator calls CourseFactory.createCourse(
     name, symbol, mintPrice, maxSupply,
     baseURI, privateContentURI, treasury, royaltyBps
   ) → CourseNFT deployed, ownership transferred to creator

2. Student calls CourseNFT.mint{value: mintPrice}()

3. Student calls CourseNFT.getCourseContent(tokenId) → private IPFS URI
```

### Create a course via script

```bash
forge script script/MintCourse.s.sol:CreateCourse \
  --rpc-url $BASE_SEPOLIA_RPC_URL --private-key $PRIVATE_KEY --broadcast
```

---

## Project Structure

```
src/
├── IdentityNFTFactory.sol       # Admin factory — deploys city IdentityNFT collections
├── IdentityNFT.sol              # Subscription profile card (multi-token, city-based)
├── challenges/
│   ├── ChallengeVault.sol       # EIP-4626 2-player number game escrow
│   ├── VaultFactory.sol         # Deploys ChallengeVaults (identity-gated, token whitelist)
│   └── IIdentityNFT.sol         # Interface used by VaultFactory and ChallengeVault
└── courses/
    ├── CourseNFT.sol            # ERC-721 course + content gate (ETH, ERC-2981)
    └── CourseFactory.sol        # Deploys CourseNFTs

test/
├── ChallengeVault.t.sol
├── IdentityNFT.t.sol
├── CourseNFT.t.sol
└── mocks/
    ├── MockERC20.sol
    └── MockIdentityNFT.sol

script/
├── deploy.sh                        # One-command deploy helper (recommended)
├── DeployIdentityNFTFactory.s.sol   # Step 1: deploy IdentityNFTFactory
├── DeployVaultFactory.s.sol         # Step 2: deploy VaultFactory
├── DeployFactory.s.sol              # Step 3: deploy CourseFactory
├── MintCourse.s.sol                 # Create a course via script
├── extract-abis.js                  # Copies ABIs from out/ → deployments/abi/
└── extract-addresses.js             # Reads broadcast/ → deployments/addresses.json

deployments/
├── addresses.json               # Deployed addresses per chain (auto-generated)
└── abi/                         # Clean ABI files for frontend (auto-generated)

docs_contracts/
├── Technical-Reference.md
└── Frontend-Integration-Guide.md
```

---

## Networks

| Network | Chain ID | RPC | Explorer (Basescan) | Explorer (Blockscout) |
|---------|----------|-----|---------------------|-----------------------|
| Base Sepolia | 84532 | https://sepolia.base.org | [sepolia.basescan.org](https://sepolia.basescan.org) | [base-sepolia.blockscout.com](https://base-sepolia.blockscout.com) |
| Base Mainnet | 8453 | https://mainnet.base.org | [basescan.org](https://basescan.org) | [base.blockscout.com](https://base.blockscout.com) |

---

## Security

- ReentrancyGuard on all payment functions
- Pausable on all mints, renewals, and factory deployments
- ERC4626 `maxDeposit` enforces challenge deposit rules
- Soulbound shares in ChallengeVault (non-transferable)
- Soulbound option on IdentityNFT (configurable at deploy)
- Identity gate on challenge creation (VaultFactory) and joining (ChallengeVault)
- `IdentityNFTFactory.deployCollection()` restricted to owner
- Custom errors everywhere (no `require` strings)
- SafeERC20 for all token transfers

> Not professionally audited. Use on testnets or at your own risk.

---

## Documentation

| Document | Description |
|----------|-------------|
| [Technical Reference](docs_contracts/Technical-Reference.md) | Full API for all contracts |
| [Frontend Integration Guide](docs_contracts/Frontend-Integration-Guide.md) | ethers.js patterns for token approvals, challenge flow, identity, courses |

---

## Built With

- [Foundry](https://getfoundry.sh/) — Solidity testing & deployment
- [OpenZeppelin v5](https://www.openzeppelin.com/) — ERC4626, ERC721, ERC2981, Ownable, Pausable, ReentrancyGuard
- [Base](https://base.org/) — L2 on Ethereum

---

**License:** MIT
