# Frontend Integration Guide — Gaming Tower + Courses NFT

Complete guide for building a frontend that interacts with all platform contracts.

> `ChallengeVault` and `IdentityNFT` use **ERC-20 tokens** (1UP, USDC, EUROC — whitelisted per deployment).
> `CourseNFT` uses **ETH (native)**. Always handle the two flows separately.
> A valid (active, non-suspended) **IdentityNFT** is the only gate to create or join challenges.
> Deployed addresses are in [`deployments/addresses.json`](../deployments/addresses.json).

---

## Table of Contents

1. [Setup](#1-setup)
2. [ERC-20 Token Approvals](#2-erc-20-token-approvals)
3. [IdentityNFT — Mint, Renew & Profile](#3-identitynft--mint-renew--profile)
4. [ChallengeVault — Challenge Flow](#4-challengevault--challenge-flow)
5. [CourseNFT — Courses (ETH)](#5-coursenft--courses-eth)
6. [Access-Control Checks](#6-access-control-checks)
7. [Error Handling Reference](#7-error-handling-reference)
8. [Best Practices](#8-best-practices)

---

## 1. Setup

### Install dependencies

```bash
npm install ethers viem wagmi @tanstack/react-query @rainbow-me/rainbowkit
```

### Contract addresses config

Load addresses from the auto-generated deployment file:

```typescript
// config/contracts.ts
import addresses from '@/deployments/addresses.json';

export const CHAIN_ID = '84532'; // Base Sepolia

const chain = addresses[CHAIN_ID];

export const ADDRESSES = {
  IDENTITY_NFT:   chain.contracts.IdentityNFT   ?? '',
  VAULT_FACTORY:  chain.contracts.VaultFactory   ?? '',
  COURSE_FACTORY: chain.contracts.CourseFactory  ?? '',
};

export const RPC = chain.explorer; // or use your own RPC endpoint
```

### Shared provider helpers

```typescript
// utils/provider.ts
import { ethers } from 'ethers';

const RPC_URL = 'https://sepolia.base.org';

export const getProvider = () =>
  typeof window !== 'undefined' && (window as any).ethereum
    ? new ethers.BrowserProvider((window as any).ethereum)
    : new ethers.JsonRpcProvider(RPC_URL);

export const getSigner = async () => {
  const provider = getProvider() as ethers.BrowserProvider;
  return provider.getSigner();
};
```

---

## 2. ERC-20 Token Approvals

All gaming contracts pull ERC-20 tokens from the user via `transferFrom`. The user must `approve` before any paid action.

```typescript
import { ethers } from 'ethers';
import ERC20_ABI from '../abi/ERC20.json'; // standard ERC-20 ABI

export const approveToken = async (tokenAddress: string, spender: string, amount: bigint) => {
  const signer = await getSigner();
  const token = new ethers.Contract(tokenAddress, ERC20_ABI, signer);
  const tx = await token.approve(spender, amount);
  await tx.wait();
};

export const getTokenBalance = async (tokenAddress: string, user: string): Promise<bigint> => {
  const provider = getProvider();
  const token = new ethers.Contract(tokenAddress, ERC20_ABI, provider);
  return token.balanceOf(user);
};

export const getTokenAllowance = async (
  tokenAddress: string,
  owner: string,
  spender: string
): Promise<bigint> => {
  const provider = getProvider();
  const token = new ethers.Contract(tokenAddress, ERC20_ABI, provider);
  return token.allowance(owner, spender);
};
```

**Pattern for every ERC-20-paying action:**

```typescript
// 1. Check current allowance
const allowance = await getTokenAllowance(TOKEN_ADDRESS, userAddress, contractAddress);

// 2. Approve if insufficient
if (allowance < requiredAmount) {
  await approveToken(TOKEN_ADDRESS, contractAddress, requiredAmount);
}

// 3. Call the contract function
await contract.mint(...);
```

### Display prices in COP

```typescript
// 1 1UP = 1000 COP (platform convention)
export const formatOneUpToCOP = (amountWei: bigint): string => {
  const oneUp = Number(ethers.formatEther(amountWei));
  return (oneUp * 1000).toLocaleString('es-CO', { style: 'currency', currency: 'COP' });
};
```

---

## 3. IdentityNFT — Mint, Renew & Profile

Users need a valid IdentityNFT to access the gaming tower. Cards are subscription-based. Each deployment is city-specific and accepts one or more ERC-20 tokens, each with independent pricing.

### Period enum values (match contract)

```typescript
export const Period = { Monthly: 0, Yearly: 1 } as const;
export type PeriodValue = typeof Period[keyof typeof Period];
```

```typescript
import IdentityNFTABI from '../abi/IdentityNFT.json';
import { ADDRESSES } from '../config/contracts';

const getIdentityContract = async (write = false) => {
  const runner = write ? await getSigner() : getProvider();
  return new ethers.Contract(ADDRESSES.IDENTITY_NFT, IdentityNFTABI, runner);
};

// ── Read ─────────────────────────────────────────────────────────────────────

export const isIdentityValid = async (user: string): Promise<boolean> => {
  const contract = await getIdentityContract();
  return contract.isValid(user);
};

export const getIdentityExpiry = async (user: string): Promise<bigint> => {
  const contract = await getIdentityContract();
  return contract.expiryOfUser(user);
};

export const getIdentityStatus = async (tokenId: bigint): Promise<number> => {
  // Returns 0 = Active, 1 = Expired, 2 = Suspended
  const contract = await getIdentityContract();
  return contract.statusOf(tokenId);
};

export const getIdentityCreatedAt = async (tokenId: bigint): Promise<bigint> => {
  const contract = await getIdentityContract();
  return contract.createdAt(tokenId);
};

export const getIdentityTokenURI = async (tokenId: bigint): Promise<string> => {
  const contract = await getIdentityContract();
  return contract.tokenURI(tokenId);
};

export const getTokenConfig = async (tokenAddress: string) => {
  const contract = await getIdentityContract();
  // Returns { mintPrice, monthlyPrice, yearlyPrice, enabled }
  return contract.tokenConfigs(tokenAddress);
};

export const getAcceptedTokens = async (): Promise<string[]> => {
  const contract = await getIdentityContract();
  return contract.getAcceptedTokens();
};

export const getTokenIdOf = async (user: string): Promise<bigint> => {
  const contract = await getIdentityContract();
  return contract.tokenIdOf(user);
};

export const getCity = async (): Promise<string> => {
  const contract = await getIdentityContract();
  return contract.city();
};

// ── Write ─────────────────────────────────────────────────────────────────────

/**
 * Mint a new identity card.
 * @param metadataURI  IPFS URI for the profile metadata.
 * @param period       Period.Monthly or Period.Yearly.
 * @param tokenAddress ERC-20 token to use for payment.
 */
export const mintIdentity = async (
  metadataURI: string,
  period: PeriodValue,
  tokenAddress: string
): Promise<ethers.ContractTransactionReceipt> => {
  const contract = await getIdentityContract(true);
  const signer   = await getSigner();
  const userAddress = await signer.getAddress();

  const cfg = await contract.tokenConfigs(tokenAddress);
  const mintPrice: bigint = cfg.mintPrice;

  if (mintPrice > 0n) {
    const allowance = await getTokenAllowance(tokenAddress, userAddress, ADDRESSES.IDENTITY_NFT);
    if (allowance < mintPrice) {
      await approveToken(tokenAddress, ADDRESSES.IDENTITY_NFT, mintPrice);
    }
  }

  const tx = await contract.mint(metadataURI, period, tokenAddress);
  return tx.wait();
};

/**
 * Renew an identity card subscription.
 * @param tokenId      Token to renew.
 * @param period       Period.Monthly or Period.Yearly.
 * @param tokenAddress ERC-20 token to use for payment (can differ from mint token).
 */
export const renewIdentity = async (
  tokenId: bigint,
  period: PeriodValue,
  tokenAddress: string
): Promise<ethers.ContractTransactionReceipt> => {
  const contract = await getIdentityContract(true);
  const signer   = await getSigner();
  const userAddress = await signer.getAddress();

  const cfg   = await contract.tokenConfigs(tokenAddress);
  const price: bigint = period === Period.Monthly ? cfg.monthlyPrice : cfg.yearlyPrice;

  if (price > 0n) {
    const allowance = await getTokenAllowance(tokenAddress, userAddress, ADDRESSES.IDENTITY_NFT);
    if (allowance < price) {
      await approveToken(tokenAddress, ADDRESSES.IDENTITY_NFT, price);
    }
  }

  const tx = await contract.renew(tokenId, period, tokenAddress);
  return tx.wait();
};

export const updateIdentityMetadata = async (
  tokenId: bigint,
  newURI: string
): Promise<ethers.ContractTransactionReceipt> => {
  const contract = await getIdentityContract(true);
  const tx = await contract.updateMetadata(tokenId, newURI);
  return tx.wait();
};
```

### Status labels helper

```typescript
export const STATUS_LABELS = ['Active', 'Expired', 'Suspended'] as const;

export const getStatusLabel = (status: number): string =>
  STATUS_LABELS[status] ?? 'Unknown';
```

### React component example — IdentityCard

```tsx
import { useEffect, useState } from 'react';
import {
  isIdentityValid, getIdentityExpiry, getIdentityStatus,
  getIdentityCreatedAt, mintIdentity, renewIdentity,
  Period, getStatusLabel, getAcceptedTokens, getTokenConfig,
} from '../utils/identity';

const ONE_UP_SEPOLIA = '0x05cb1e3ba6102b097c0ad913c8b82ac76e7df73f';

export const IdentityCard = ({
  userAddress,
  tokenId,
}: {
  userAddress: string;
  tokenId: bigint;
}) => {
  const [valid, setValid]     = useState(false);
  const [status, setStatus]   = useState<string>('Unknown');
  const [expiry, setExpiry]   = useState<Date | null>(null);
  const [created, setCreated] = useState<Date | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    (async () => {
      const [v, exp, s, cr] = await Promise.all([
        isIdentityValid(userAddress),
        getIdentityExpiry(userAddress),
        getIdentityStatus(tokenId),
        getIdentityCreatedAt(tokenId),
      ]);
      setValid(v);
      setStatus(getStatusLabel(Number(s)));
      if (exp > 0n)  setExpiry(new Date(Number(exp) * 1000));
      if (cr > 0n)   setCreated(new Date(Number(cr) * 1000));
      setLoading(false);
    })();
  }, [userAddress, tokenId]);

  if (loading) return <p>Loading identity...</p>;

  return (
    <div>
      <p>Status: {status}</p>
      {created && <p>Member since: {created.toLocaleDateString()}</p>}
      {expiry  && <p>Expires: {expiry.toLocaleDateString()}</p>}

      {!valid && (
        <div>
          <button onClick={() => mintIdentity('ipfs://your-metadata', Period.Monthly, ONE_UP_SEPOLIA)}>
            Mint Monthly
          </button>
          <button onClick={() => mintIdentity('ipfs://your-metadata', Period.Yearly, ONE_UP_SEPOLIA)}>
            Mint Yearly
          </button>
        </div>
      )}

      {valid && (
        <div>
          <button onClick={() => renewIdentity(tokenId, Period.Monthly, ONE_UP_SEPOLIA)}>
            Renew Monthly
          </button>
          <button onClick={() => renewIdentity(tokenId, Period.Yearly, ONE_UP_SEPOLIA)}>
            Renew Yearly
          </button>
        </div>
      )}
    </div>
  );
};
```

---

## 4. ChallengeVault — Challenge Flow

### 4a. Create a challenge

```typescript
import VaultFactoryABI  from '../abi/VaultFactory.json';
import ChallengeVaultABI from '../abi/ChallengeVault.json';
import { ADDRESSES } from '../config/contracts';

const getVaultFactoryContract = async (write = false) => {
  const runner = write ? await getSigner() : getProvider();
  return new ethers.Contract(ADDRESSES.VAULT_FACTORY, VaultFactoryABI, runner);
};

const getVaultContract = async (vaultAddress: string, write = false) => {
  const runner = write ? await getSigner() : getProvider();
  return new ethers.Contract(vaultAddress, ChallengeVaultABI, runner);
};

/**
 * Deploy a new ChallengeVault.
 * Caller must have a valid IdentityNFT.
 * After this call: approve stakeAmount of token to vault, then call deposit().
 */
export const createChallenge = async (
  tokenAddress: string,
  stakeAmountWei: bigint,
  durationSeconds: bigint,
  metadataURI: string
): Promise<string> => {
  const factory = await getVaultFactoryContract(true);
  const tx = await factory.createChallenge(tokenAddress, stakeAmountWei, durationSeconds, metadataURI);
  const receipt = await tx.wait();
  const event = receipt.logs.find((l: any) => l.fragment?.name === 'VaultCreated');
  return event?.args.vault; // vault address
};
```

### 4b. Join a challenge (deposit tokens)

```typescript
/**
 * Join an existing ChallengeVault by depositing the stake.
 * Player2 must have a valid IdentityNFT.
 */
export const joinChallenge = async (
  vaultAddress: string,
  tokenAddress: string
): Promise<ethers.ContractTransactionReceipt> => {
  const vault = await getVaultContract(vaultAddress, true);
  const signer = await getSigner();
  const userAddress = await signer.getAddress();

  const stakeAmount: bigint = await vault.stakeAmount();

  const allowance = await getTokenAllowance(tokenAddress, userAddress, vaultAddress);
  if (allowance < stakeAmount) {
    await approveToken(tokenAddress, vaultAddress, stakeAmount);
  }

  const tx = await vault.deposit(stakeAmount, userAddress);
  return tx.wait();
};
```

### 4c. Submit a number (after endTime)

```typescript
/**
 * Submit your number after the challenge window ends.
 * Highest number wins. Call after block.timestamp >= vault.endTime().
 */
export const submitNumber = async (
  vaultAddress: string,
  number: bigint
): Promise<ethers.ContractTransactionReceipt> => {
  const vault = await getVaultContract(vaultAddress, true);
  const tx = await vault.submitNumber(number);
  return tx.wait();
};
```

### 4d. Read vault state

```typescript
export interface VaultState {
  player1: string;
  player2: string;
  stakeAmount: bigint;
  state: number;        // 0=OPEN, 1=ACTIVE, 2=RESOLVED
  endTime: bigint;
  winner: string;
  hasPlayer1Submitted: boolean;
  hasPlayer2Submitted: boolean;
  player1Number: bigint;
  player2Number: bigint;
}

export const STATE_LABELS = ['OPEN', 'ACTIVE', 'RESOLVED'];

export const getVaultState = async (vaultAddress: string): Promise<VaultState> => {
  const vault = await getVaultContract(vaultAddress);
  const [player1, player2, stakeAmount, state, endTime, winner] = await Promise.all([
    vault.player1(),
    vault.player2(),
    vault.stakeAmount(),
    vault.state(),
    vault.endTime(),
    vault.winner(),
  ]);

  const [hasP1, hasP2] = await Promise.all([
    vault.hasSubmitted(player1),
    player2 !== ethers.ZeroAddress ? vault.hasSubmitted(player2) : Promise.resolve(false),
  ]);

  const [n1, n2] = await Promise.all([
    hasP1 ? vault.submittedNumber(player1) : Promise.resolve(0n),
    hasP2 ? vault.submittedNumber(player2) : Promise.resolve(0n),
  ]);

  return {
    player1, player2, stakeAmount,
    state: Number(state), endTime, winner,
    hasPlayer1Submitted: hasP1,
    hasPlayer2Submitted: hasP2,
    player1Number: n1,
    player2Number: n2,
  };
};
```

### 4e. Full challenge flow diagram

> **Identity requirement:** Both Creator and Player 2 must hold a valid (active, non-suspended) IdentityNFT. Creator's identity is checked at step 1; Player 2's identity is checked at step 5.

```
Creator                                  Player 2
   │                                        │
   │ 0. mint/renew IdentityNFT              │ 0. mint/renew IdentityNFT
   │                                        │
   │ 1. createChallenge(token, stake, dur, uri)
   │    → identity check on caller          │
   │    → vault deployed                    │
   │                                        │
   │ 2. approve token → vault               │
   │ 3. vault.deposit(stake, self)          │
   │    → OPEN + player1 joined             │
   │                                        │
   │ share vault address ─────────────────► │
   │                                        │ 4. approve token → vault
   │                                        │ 5. vault.deposit(stake, self)
   │                                        │    → identity check on player2
   │                                        │    → ACTIVE, endTime set
   │                                        │
   │ ◄──── wait for endTime ──────────────► │
   │                                        │
   │ 6. vault.submitNumber(myNumber)        │ 6. vault.submitNumber(myNumber)
   │                                        │
   │    → highest number wins automatically  │
   │    → tie: resolver calls resolveDispute │
   │    → state: RESOLVED, prize transferred │
```

---

## 5. CourseNFT — Courses (ETH)

CourseNFT uses ETH, not ERC-20 tokens. No `approve` step needed.

```typescript
import CourseNFTABI     from '../abi/CourseNFT.json';
import CourseFactoryABI from '../abi/CourseFactory.json';
import { ADDRESSES } from '../config/contracts';

const getCourseFactoryContract = async (write = false) => {
  const runner = write ? await getSigner() : getProvider();
  return new ethers.Contract(ADDRESSES.COURSE_FACTORY, CourseFactoryABI, runner);
};

const getCourseNFTContract = async (courseAddress: string, write = false) => {
  const runner = write ? await getSigner() : getProvider();
  return new ethers.Contract(courseAddress, CourseNFTABI, runner);
};

// ── Read ─────────────────────────────────────────────────────────────────────

export const getAllCourses = async (): Promise<string[]> => {
  const factory = await getCourseFactoryContract();
  return factory.getAllCourses();
};

export const getCoursesByCreator = async (creator: string): Promise<string[]> => {
  const factory = await getCourseFactoryContract();
  return factory.getCoursesByCreator(creator);
};

export const getCourseDetails = async (courseAddress: string) => {
  const course = await getCourseNFTContract(courseAddress);
  const [name, symbol, mintPrice, maxSupply, totalSupply, canMint] = await Promise.all([
    course.name(),
    course.symbol(),
    course.mintPrice(),
    course.maxSupply(),
    course.totalSupply(),
    course.canMint(),
  ]);
  return { address: courseAddress, name, symbol, mintPrice, maxSupply, totalSupply, canMint };
};

/**
 * Fetch the private course content URI.
 * Reverts NotTokenHolder if the caller does not own the token.
 */
export const getCourseContent = async (courseAddress: string, tokenId: bigint): Promise<string> => {
  const course = await getCourseNFTContract(courseAddress, true);
  return course.getCourseContent(tokenId);
};

// ── Write ─────────────────────────────────────────────────────────────────────

/**
 * Mint a course NFT to the caller. Sends exactly mintPrice ETH.
 */
export const mintCourse = async (
  courseAddress: string
): Promise<ethers.ContractTransactionReceipt> => {
  const course = await getCourseNFTContract(courseAddress, true);
  const mintPrice: bigint = await course.mintPrice();
  const tx = await course.mint({ value: mintPrice });
  return tx.wait();
};

/**
 * Mint a course NFT to a recipient. Caller pays.
 */
export const mintCourseTo = async (
  courseAddress: string,
  recipient: string
): Promise<ethers.ContractTransactionReceipt> => {
  const course = await getCourseNFTContract(courseAddress, true);
  const mintPrice: bigint = await course.mintPrice();
  const tx = await course.mintTo(recipient, { value: mintPrice });
  return tx.wait();
};
```

---

## 6. Access-Control Checks

Gate UI features behind on-chain checks. A valid IdentityNFT is the only requirement to create or join a challenge.

```typescript
export interface UserAccess {
  hasValidIdentity: boolean;
  identityExpiry: Date | null;
  identityStatus: string;      // 'Active' | 'Expired' | 'Suspended' | 'None'
  identityTokenId: bigint;
}

export const getUserAccess = async (userAddress: string): Promise<UserAccess> => {
  const contract = await getIdentityContract();

  const tokenId: bigint = await contract.tokenIdOf(userAddress);

  if (tokenId === 0n) {
    return {
      hasValidIdentity: false,
      identityExpiry:   null,
      identityStatus:   'None',
      identityTokenId:  0n,
    };
  }

  const [hasValidIdentity, expiryTs, statusNum] = await Promise.all([
    contract.isValid(userAddress),
    contract.expiryOfUser(userAddress),
    contract.statusOf(tokenId),
  ]);

  return {
    hasValidIdentity,
    identityExpiry:  expiryTs > 0n ? new Date(Number(expiryTs) * 1000) : null,
    identityStatus:  getStatusLabel(Number(statusNum)),
    identityTokenId: tokenId,
  };
};
```

### Guard component

```tsx
import { useEffect, useState } from 'react';
import { isIdentityValid } from '../utils/identity';

export const RequiresIdentity = ({ children, userAddress }: {
  children: React.ReactNode;
  userAddress: string;
}) => {
  const [valid, setValid] = useState<boolean | null>(null);

  useEffect(() => {
    if (!userAddress) return;
    isIdentityValid(userAddress).then(setValid);
  }, [userAddress]);

  if (valid === null) return <p>Checking identity...</p>;
  if (!valid) return <p>You need a valid Identity NFT to access this feature.</p>;
  return <>{children}</>;
};
```

---

## 7. Error Handling Reference

Map contract custom errors to user-friendly messages:

```typescript
const CONTRACT_ERRORS: Record<string, string> = {
  // CourseNFT
  IncorrectPayment:   'Wrong ETH amount. Check the course price.',
  MaxSupplyReached:   'This course is sold out.',
  NotTokenHolder:     'You do not own this NFT.',
  WithdrawalFailed:   'ETH withdrawal failed.',

  // ChallengeVault / VaultFactory
  NotPlayer:             'You are not a player in this challenge.',
  WrongState:            'Action not allowed in the current challenge state.',
  AlreadyJoined:         'You already joined this challenge.',
  WrongStakeAmount:      'Stake amount must match exactly.',
  SharesNonTransferable: 'Challenge shares cannot be transferred.',
  NotResolver:           'Only the resolver can call this function.',
  NoActiveIdentity:      'You need an active, non-suspended Identity NFT.',
  NotAfterEndTime:       'The challenge window has not ended yet.',
  AlreadySubmitted:      'You already submitted your number.',
  BothMustSubmit:        'Both players must submit before resolving a tie.',
  ZeroStake:             'Stake amount cannot be zero.',
  ZeroDuration:          'Challenge duration cannot be zero.',
  TokenNotAccepted:      'This token is not accepted for payment.',

  // IdentityNFT
  AlreadyHasIdentity: 'You already have an identity NFT.',
  NoIdentityFound:    'Identity token does not exist.',
  NotTokenOwner:      'Only the token owner can update metadata.',
  SoulboundToken:     'This identity NFT cannot be transferred.',

  // General
  ZeroAddress: 'Address cannot be zero.',
};

export const parseContractError = (error: any): string => {
  const msg: string = error?.message ?? '';
  for (const [key, label] of Object.entries(CONTRACT_ERRORS)) {
    if (msg.includes(key)) return label;
  }
  if (error?.code === 'ACTION_REJECTED') return 'Transaction rejected.';
  return 'Transaction failed. Check console for details.';
};
```

---

## 8. Best Practices

### Network check

```typescript
export const ensureBaseSepolia = async () => {
  const provider = getProvider() as ethers.BrowserProvider;
  const network  = await provider.getNetwork();
  if (network.chainId !== 84532n) {
    throw new Error('Please switch to Base Sepolia (chain 84532)');
  }
};
```

### Wait for confirmations

```typescript
// Development: 1 confirmation
const receipt = await tx.wait(1);

// Production: 2+ confirmations
const receipt = await tx.wait(2);
```

### IPFS loading

```typescript
export const ipfsToHTTP = (uri: string, gateway = 'https://ipfs.io/ipfs/'): string =>
  uri.replace('ipfs://', gateway);

export const fetchIPFSMetadata = async (uri: string) => {
  const url = ipfsToHTTP(uri);
  const res = await fetch(url);
  return res.json();
};
```

### Check endTime before submitNumber

```typescript
export const canSubmitNumber = async (vaultAddress: string): Promise<boolean> => {
  const vault = await getVaultContract(vaultAddress);
  const [state, endTime] = await Promise.all([vault.state(), vault.endTime()]);
  const nowSec = BigInt(Math.floor(Date.now() / 1000));
  return Number(state) === 1 /* ACTIVE */ && nowSec >= endTime;
};
```

### App file structure

```
src/
├── config/
│   └── contracts.ts          # Addresses loaded from deployments/addresses.json
├── abi/
│   ├── IdentityNFT.json
│   ├── VaultFactory.json
│   ├── ChallengeVault.json
│   ├── CourseFactory.json
│   └── CourseNFT.json
├── utils/
│   ├── provider.ts           # Provider / signer helpers
│   ├── token.ts              # ERC-20 approve / balance / allowance
│   ├── identity.ts           # IdentityNFT read/write
│   ├── vault.ts              # ChallengeVault read/write
│   └── courseNFT.ts          # CourseNFT read/write
├── hooks/
│   ├── useIdentity.ts
│   └── useChallenges.ts
└── pages/
    ├── TowerPage.tsx          # Requires active IdentityNFT
    ├── ChallengePage.tsx      # Create/join/submit challenges
    └── CoursesPage.tsx        # Browse & mint courses
```

### Deployment checklist

- [ ] Deploy IdentityNFT first, then VaultFactory (order matters)
- [ ] Run `node script/extract-abis.js` after `forge build`
- [ ] Run `node script/extract-addresses.js <chainId>` after each deployment
- [ ] Load `ADDRESSES` from `deployments/addresses.json` — never hardcode in source
- [ ] Gate challenge UI behind `isValid(userAddress)` check
- [ ] Test on Base Sepolia before mainnet
- [ ] Handle `ACTION_REJECTED` (user cancel) gracefully
- [ ] Check `canMint()` before showing mint button on CourseNFT
- [ ] Check `canSubmitNumber()` before showing submit button on ChallengeVault
- [ ] Show spinner between tx submission and confirmation
- [ ] Refresh state after successful transactions
- [ ] Display 1UP amounts in both 1UP and COP (1 1UP = 1 000 COP)

---

**Resources**

- Ethers.js: https://docs.ethers.org/
- Wagmi: https://wagmi.sh/
- Base docs: https://docs.base.org/
- IPFS: https://docs.ipfs.tech/
