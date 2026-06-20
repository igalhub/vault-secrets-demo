#!/usr/bin/env bash
# Re-issue a fresh AppRole secret_id for the existing demo-app role and
# write .env.consumer. Use this when .env.consumer is missing or stale
# without needing to wipe and re-initialize Vault.
#
# Requires: initialized + unsealed Vault, .vault-init.json present.
# All Vault commands run via `docker exec` — no host Vault CLI required.
set -euo pipefail

CONTAINER="vault"
INIT_FILE=".vault-init.json"

# ── Prerequisites ──────────────────────────────────────────────────────────────

if [ ! -f "$INIT_FILE" ]; then
  echo "ERROR: ${INIT_FILE} not found." >&2
  echo "       Run scripts/init.sh against a fresh Vault first." >&2
  exit 1
fi

if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
  echo "ERROR: container '${CONTAINER}' is not running." >&2
  echo "       Run: docker compose up vault -d && bash scripts/unseal.sh" >&2
  exit 1
fi

sealed_output=$(docker exec -e VAULT_ADDR="http://127.0.0.1:8200" "$CONTAINER" vault status 2>&1 || true)
if echo "$sealed_output" | grep -q "Sealed.*true"; then
  echo "ERROR: Vault is sealed." >&2
  echo "       Run: bash scripts/unseal.sh" >&2
  exit 1
fi

ROOT_TOKEN=$(awk -F'"' '/"root_token"/ {print $4}' "$INIT_FILE")
ROLE_ID=$(awk -F'"' '/"role_id"/ {print $4}' "$INIT_FILE")

if [ -z "$ROOT_TOKEN" ] || [ -z "$ROLE_ID" ]; then
  echo "ERROR: could not parse root_token or role_id from ${INIT_FILE}." >&2
  exit 1
fi

# ── Issue fresh secret_id ──────────────────────────────────────────────────────

echo "==> Issuing fresh AppRole secret_id for demo-app role..."
SECRET_ID=$(docker exec \
  -e VAULT_ADDR="http://127.0.0.1:8200" \
  -e VAULT_TOKEN="$ROOT_TOKEN" \
  "$CONTAINER" vault write -field=secret_id -f auth/approle/role/demo-app/secret-id)

# ── Write .env.consumer ────────────────────────────────────────────────────────

cat > ".env.consumer" <<EOF
VAULT_ADDR=http://vault:8200
VAULT_ROLE_ID=${ROLE_ID}
VAULT_SECRET_ID=${SECRET_ID}
EOF

echo "✅ .env.consumer written with a fresh secret_id."
echo "   Run: docker compose up consumer-app -d"
echo "   Verify: curl http://localhost:8000/status"
