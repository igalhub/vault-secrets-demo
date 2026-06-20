#!/usr/bin/env bash
# Re-unseal Vault after a restart. Reads the unseal key from .vault-init.json.
# All Vault commands run via `docker exec` — no host Vault CLI required.
set -euo pipefail

CONTAINER="vault"
INIT_FILE=".vault-init.json"

if [ ! -f "$INIT_FILE" ]; then
  echo "ERROR: ${INIT_FILE} not found." >&2
  echo "       Run scripts/init.sh first to initialize Vault." >&2
  exit 1
fi

if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
  echo "ERROR: container '${CONTAINER}' is not running." >&2
  echo "       Run: docker compose up vault -d" >&2
  exit 1
fi

UNSEAL_KEY=$(awk -F'"' '/"unseal_key"/ {print $4}' "$INIT_FILE")

if [ -z "$UNSEAL_KEY" ]; then
  echo "ERROR: could not read unseal_key from ${INIT_FILE}." >&2
  exit 1
fi

echo "==> Unsealing Vault..."
docker exec \
  -e VAULT_ADDR="http://127.0.0.1:8200" \
  "$CONTAINER" vault operator unseal "$UNSEAL_KEY" > /dev/null

echo "✅ Vault unsealed."
