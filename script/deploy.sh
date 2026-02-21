#!/usr/bin/env bash
# deploy.sh — Deploy infrastructure contracts on Base Sepolia or Base Mainnet.
#
# Deploy order (run once per network):
#   1. identity-factory  → IdentityNFTFactory  (admin deploys city collections from frontend)
#   2. vault-factory     → VaultFactory        (requires IDENTITY_NFT in .env)
#   3. course-factory    → CourseFactory
#
# After infrastructure is live, everything else happens on-chain via the frontend:
#   • Admin calls IdentityNFTFactory.deployCollection() to add a new city
#   • Operators call CourseFactory.createCourse() to publish a course
#   • Users call VaultFactory.createChallenge() to start a challenge
#   • Users call IdentityNFT.mint() / CourseNFT.mint() to get their tokens
#
# Networks:
#   base-sepolia   chain 84532
#   base           chain 8453

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$ROOT_DIR/.env"

# ── Load .env ─────────────────────────────────────────────────────────────────
if [ ! -f "$ENV_FILE" ]; then
  echo "Error: .env not found. Run: cp .env.example .env"
  exit 1
fi
set -a; source "$ENV_FILE"; set +a

# ── Parse arguments ───────────────────────────────────────────────────────────
NETWORK="${1:-}"
STEP=""

if [ -z "$NETWORK" ]; then
  echo "Usage: ./script/deploy.sh <network> --step <step>"
  echo ""
  echo "Networks:  base-sepolia | base"
  echo ""
  echo "Steps (run in order):"
  echo "  identity-factory   Deploy IdentityNFTFactory  (run once — admin creates cities from frontend)"
  echo "  vault-factory      Deploy VaultFactory         (requires IDENTITY_NFT in .env)"
  echo "  course-factory     Deploy CourseFactory        (run once)"
  echo ""
  echo "Examples:"
  echo "  ./script/deploy.sh base-sepolia --step identity-factory"
  echo "  ./script/deploy.sh base-sepolia --step vault-factory"
  echo "  ./script/deploy.sh base-sepolia --step course-factory"
  exit 0
fi

shift
while [[ $# -gt 0 ]]; do
  case "$1" in
    --step) STEP="$2"; shift 2 ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

if [ -z "$STEP" ]; then
  echo "Error: --step is required."
  exit 1
fi

# ── Resolve network ───────────────────────────────────────────────────────────
case "$NETWORK" in
  base-sepolia)
    RPC_URL="$BASE_SEPOLIA_RPC_URL"
    CHAIN_ID="84532"
    NETWORK_LABEL="Base Sepolia"
    ;;
  base)
    RPC_URL="$BASE_RPC_URL"
    CHAIN_ID="8453"
    NETWORK_LABEL="Base Mainnet"
    ;;
  *)
    echo "Unknown network: $NETWORK  (use: base-sepolia | base)"
    exit 1
    ;;
esac

# ── Validate required globals ─────────────────────────────────────────────────
missing=()
[ -z "${PRIVATE_KEY:-}"      ] && missing+=("PRIVATE_KEY")
[ -z "${RPC_URL:-}"          ] && missing+=("BASE_SEPOLIA_RPC_URL or BASE_RPC_URL")
[ -z "${BASESCAN_API_KEY:-}" ] && missing+=("BASESCAN_API_KEY")
[ -z "${DEFAULT_TREASURY:-}" ] && missing+=("DEFAULT_TREASURY")
if [ ${#missing[@]} -gt 0 ]; then
  echo "Error: missing variables in .env:"
  for v in "${missing[@]}"; do echo "  - $v"; done
  exit 1
fi

# ── Shared forge flags ────────────────────────────────────────────────────────
FORGE_FLAGS=(
  --rpc-url "$RPC_URL"
  --private-key "$PRIVATE_KEY"
  --broadcast
  --verify
  --verifier etherscan
  --etherscan-api-key "$BASESCAN_API_KEY"
)

# ── Extract addresses after deployment ───────────────────────────────────────
extract_addresses() {
  echo ""
  echo "  Extracting addresses → deployments/addresses.json ..."
  node "$SCRIPT_DIR/extract-addresses.js" "$CHAIN_ID"
}

# ── Steps ─────────────────────────────────────────────────────────────────────
echo ""
echo "Network : $NETWORK_LABEL (chain $CHAIN_ID)"
echo "Step    : $STEP"
echo ""

case "$STEP" in

  identity-factory)
    # Deployed once. Admin then calls deployCollection() from a frontend wallet
    # to spin up each new city collection — no CLI required for city collections.
    echo "Deploying IdentityNFTFactory ..."
    forge script script/DeployIdentityNFTFactory.s.sol:DeployIdentityNFTFactory "${FORGE_FLAGS[@]}"
    extract_addresses
    echo ""
    echo "Next: set IDENTITY_NFT_FACTORY=<printed address> in .env"
    echo "Then: use the frontend admin panel to deploy city collections via deployCollection()"
    echo "      After the first city is deployed, set IDENTITY_NFT=<city address> in .env"
    echo "      before running --step vault-factory"
    ;;

  vault-factory)
    [ -z "${RESOLVER_ADDRESS:-}"    ] && { echo "Error: RESOLVER_ADDRESS missing in .env"; exit 1; }
    [ -z "${ACCEPTED_TOKEN_1:-}"    ] && { echo "Error: ACCEPTED_TOKEN_1 missing in .env"; exit 1; }
    [ -z "${IDENTITY_NFT:-}"        ] && { echo "Error: IDENTITY_NFT missing in .env — deploy first city collection via IdentityNFTFactory first"; exit 1; }

    echo "Deploying VaultFactory ..."
    forge script script/DeployVaultFactory.s.sol:DeployVaultFactory "${FORGE_FLAGS[@]}"
    extract_addresses
    echo ""
    echo "Next: set VAULT_FACTORY_ADDRESS=<printed address> in .env"
    ;;

  course-factory)
    echo "Deploying CourseFactory ..."
    forge script script/DeployFactory.s.sol:DeployFactory "${FORGE_FLAGS[@]}"
    extract_addresses
    echo ""
    echo "Next: set FACTORY_ADDRESS=<printed address> in .env"
    ;;

  *)
    echo "Unknown step: $STEP"
    echo "Valid steps: identity-factory | vault-factory | course-factory"
    exit 1
    ;;
esac

echo ""
echo "Done."
