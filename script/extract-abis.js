#!/usr/bin/env node

/**
 * extract-abis.js
 * ---------------
 * Reads compiled Foundry artifacts from out/ and writes clean ABI JSON files
 * to deployments/abi/. Run this after `forge build`.
 *
 * Usage:
 *   node script/extract-abis.js
 */

'use strict';

const fs   = require('fs');
const path = require('path');

// ── Contracts to extract ──────────────────────────────────────────────────────
const CONTRACTS = [
  'IdentityNFTFactory', // factory — admin creates city collections from frontend
  'IdentityNFT',        // individual city collection (ABI needed by frontend)
  'VaultFactory',
  'ChallengeVault',
  'CourseFactory',
  'CourseNFT',
];

// ── Paths ─────────────────────────────────────────────────────────────────────
const ROOT    = path.resolve(__dirname, '..');
const OUT_DIR = path.join(ROOT, 'out');
const ABI_DIR = path.join(ROOT, 'deployments', 'abi');

// ── Main ──────────────────────────────────────────────────────────────────────
function main() {
  fs.mkdirSync(ABI_DIR, { recursive: true });

  let ok   = 0;
  let skip = 0;

  for (const name of CONTRACTS) {
    const artifactPath = path.join(OUT_DIR, `${name}.sol`, `${name}.json`);

    if (!fs.existsSync(artifactPath)) {
      console.warn(`  skip  ${name}  (artifact not found — run: forge build)`);
      skip++;
      continue;
    }

    const artifact  = JSON.parse(fs.readFileSync(artifactPath, 'utf8'));
    const outputPath = path.join(ABI_DIR, `${name}.json`);
    fs.writeFileSync(outputPath, JSON.stringify(artifact.abi, null, 2));

    console.log(`  ok    deployments/abi/${name}.json`);
    ok++;
  }

  console.log(`\n${ok} ABI(s) extracted${skip ? `, ${skip} skipped` : ''}.`);
}

main();
