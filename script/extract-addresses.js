#!/usr/bin/env node

/**
 * extract-addresses.js
 * --------------------
 * Reads Foundry broadcast files from broadcast/ and merges deployed contract
 * addresses into deployments/addresses.json. Run this after each forge deploy.
 *
 * Forge writes each script's broadcast to:
 *   broadcast/<ScriptFile.s.sol>/<chainId>/run-latest.json
 *
 * Usage:
 *   node script/extract-addresses.js          # scan all known chains
 *   node script/extract-addresses.js 84532    # Base Sepolia only
 *   node script/extract-addresses.js 8453     # Base Mainnet only
 */

'use strict';

const fs   = require('fs');
const path = require('path');

// ── Chain registry ────────────────────────────────────────────────────────────
const CHAINS = {
  '84532': { chainName: 'Base Sepolia', explorer: 'https://base-sepolia.blockscout.com' },
  '8453':  { chainName: 'Base Mainnet', explorer: 'https://base.blockscout.com' },
};

// ── Deploy scripts and the contracts they create ──────────────────────────────
// Forge writes each script's broadcast to broadcast/<file>/<chainId>/run-latest.json
// Individual IdentityNFT city collections are deployed on-chain via IdentityNFTFactory
// from the frontend — they do not appear in forge broadcast files.
const DEPLOY_SCRIPTS = [
  { file: 'DeployIdentityNFTFactory.s.sol', contracts: ['IdentityNFTFactory'] },
  { file: 'DeployVaultFactory.s.sol',       contracts: ['VaultFactory']       },
  { file: 'DeployFactory.s.sol',            contracts: ['CourseFactory']      },
];

// ── Paths ─────────────────────────────────────────────────────────────────────
const ROOT          = path.resolve(__dirname, '..');
const BROADCAST_DIR = path.join(ROOT, 'broadcast');
const ADDRESSES     = path.join(ROOT, 'deployments', 'addresses.json');

// ── Helpers ───────────────────────────────────────────────────────────────────
function loadAddresses() {
  return fs.existsSync(ADDRESSES)
    ? JSON.parse(fs.readFileSync(ADDRESSES, 'utf8'))
    : {};
}

function parseContracts(broadcastPath, allowedContracts) {
  if (!fs.existsSync(broadcastPath)) return null;

  const { transactions } = JSON.parse(fs.readFileSync(broadcastPath, 'utf8'));
  const found = {};

  for (const tx of transactions) {
    if (tx.transactionType === 'CREATE' && allowedContracts.includes(tx.contractName)) {
      found[tx.contractName] = tx.contractAddress;
    }
  }

  return Object.keys(found).length ? found : null;
}

function extractChain(chainId, existing) {
  const chainInfo = CHAINS[chainId];
  const contracts = { ...(existing[chainId]?.contracts ?? {}) };
  let   updated   = false;

  for (const { file, contracts: allowed } of DEPLOY_SCRIPTS) {
    const broadcastPath = path.join(BROADCAST_DIR, file, chainId, 'run-latest.json');
    const found         = parseContracts(broadcastPath, allowed);

    if (found) {
      Object.assign(contracts, found);
      for (const [name, address] of Object.entries(found)) {
        console.log(`  ${chainInfo.chainName}  ${name}: ${address}`);
      }
      updated = true;
    }
  }

  if (!updated) {
    console.log(`  no broadcasts found for chain ${chainId} (${chainInfo.chainName})`);
    return false;
  }

  existing[chainId] = {
    chainId:   parseInt(chainId),
    chainName: chainInfo.chainName,
    explorer:  chainInfo.explorer,
    timestamp: new Date().toISOString(),
    contracts,
  };

  return true;
}

// ── Main ──────────────────────────────────────────────────────────────────────
function main() {
  const arg     = process.argv[2];
  const targets = arg ? [arg] : Object.keys(CHAINS);

  if (arg && !CHAINS[arg]) {
    console.error(`Unknown chain: ${arg}`);
    console.error(`Available chains: ${Object.keys(CHAINS).join(', ')}`);
    process.exit(1);
  }

  fs.mkdirSync(path.dirname(ADDRESSES), { recursive: true });

  const existing = loadAddresses();
  let   updated  = false;

  for (const chainId of targets) {
    if (extractChain(chainId, existing)) updated = true;
  }

  if (updated) {
    fs.writeFileSync(ADDRESSES, JSON.stringify(existing, null, 2));
    console.log('\nSaved -> deployments/addresses.json');
  } else {
    console.log('\nNo new deployments found.');
  }
}

main();
