#!/usr/bin/env bash
# Bootstrap a fresh Vault instance: init, unseal, KV v2, policy, AppRole, seed secrets.
# All Vault commands run via `docker exec` — no host Vault CLI required.
set -euo pipefail

CONTAINER="vault"
INIT_FILE=".vault-init.json"

vault_exec() {
  docker exec \
    -e VAULT_ADDR="http://127.0.0.1:8200" \
    "$CONTAINER" vault "$@"
}

vault_exec_root() {
  docker exec \
    -e VAULT_ADDR="http://127.0.0.1:8200" \
    -e VAULT_TOKEN="$ROOT_TOKEN" \
    "$CONTAINER" vault "$@"
}

# ── Prerequisites ──────────────────────────────────────────────────────────────

if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
  echo "ERROR: container '${CONTAINER}' is not running." >&2
  echo "       Run: docker compose up vault -d" >&2
  exit 1
fi

# Idempotent guard: exit clearly rather than corrupting an existing Vault
status_output=$(vault_exec status 2>&1 || true)
if echo "$status_output" | grep -q "Initialized.*true"; then
  echo "ERROR: Vault is already initialized." >&2
  echo "       To start fresh: docker compose down -v && docker compose up vault -d" >&2
  exit 1
fi

# ── Initialize ─────────────────────────────────────────────────────────────────

echo "==> Initializing Vault (1 unseal key, threshold 1 — appropriate for a demo)..."
# Using -key-shares=1 -key-threshold=1 to keep unseal simple for a single-node demo.
# A production deployment would use a higher shares/threshold (e.g. 5/3).
init_output=$(vault_exec operator init -key-shares=1 -key-threshold=1 2>&1)

UNSEAL_KEY=$(echo "$init_output" | awk '/^Unseal Key 1:/ {print $NF}')
ROOT_TOKEN=$(echo "$init_output"  | awk '/^Initial Root Token:/ {print $NF}')

if [ -z "$UNSEAL_KEY" ] || [ -z "$ROOT_TOKEN" ]; then
  echo "ERROR: failed to parse init output. Raw output:" >&2
  echo "$init_output" >&2
  exit 1
fi

# ── Unseal ─────────────────────────────────────────────────────────────────────

echo "==> Unsealing..."
vault_exec operator unseal "$UNSEAL_KEY" > /dev/null

# ── KV v2 ──────────────────────────────────────────────────────────────────────

echo "==> Enabling KV v2 at secret/..."
vault_exec_root secrets enable -path=secret kv-v2

# ── Policy ─────────────────────────────────────────────────────────────────────

echo "==> Writing demo-app-policy..."
# Read-only access scoped to the five demo paths — nothing else in Vault.
docker exec -i \
  -e VAULT_ADDR="http://127.0.0.1:8200" \
  -e VAULT_TOKEN="$ROOT_TOKEN" \
  "$CONTAINER" vault policy write demo-app-policy - <<'EOF'
path "secret/data/demo-*" {
  capabilities = ["read"]
}
EOF

# ── AppRole ────────────────────────────────────────────────────────────────────

echo "==> Enabling AppRole auth method..."
vault_exec_root auth enable approle

echo "==> Creating demo-app role..."
vault_exec_root write auth/approle/role/demo-app \
  token_policies=demo-app-policy \
  token_ttl=1h \
  token_max_ttl=4h \
  secret_id_ttl=0

# ── Seed secrets ───────────────────────────────────────────────────────────────

echo "==> Seeding demo secrets..."
# None of these values use real provider key formats (no AKIA, sk-ant-, ghp_,
# etc.) to avoid triggering GitHub's automated secret-scanning on push — even
# fake values with those prefixes are flagged. The restriction applies only to
# what ships in this repo; users can store real credentials in their own
# running Vault instance without limitation (those values never touch git).

vault_exec_root kv put secret/demo-db \
  username="demo_user" \
  password="demo-not-real-CHANGE-ME"

vault_exec_root kv put secret/demo-api-key \
  value="demo-fake-api-key-do-not-use-000111222"

vault_exec_root kv put secret/demo-connection-string \
  value="postgresql://demo_user:demo-pass@localhost:5432/demo_db"

vault_exec_root kv put secret/demo-signing-key \
  value="demo-fake-jwt-signing-secret-xyz789"

vault_exec_root kv put secret/demo-webhook \
  value="https://hooks.example.invalid/services/DEMO/FAKE/0000"

# ── AppRole credentials ────────────────────────────────────────────────────────

echo "==> Fetching AppRole credentials..."
ROLE_ID=$(vault_exec_root read -field=role_id auth/approle/role/demo-app/role-id)
SECRET_ID=$(vault_exec_root write -field=secret_id -f auth/approle/role/demo-app/secret-id)

# ── Write gitignored credentials file ─────────────────────────────────────────

cat > "$INIT_FILE" <<EOF
{
  "unseal_key": "${UNSEAL_KEY}",
  "root_token": "${ROOT_TOKEN}",
  "role_id": "${ROLE_ID}",
  "secret_id": "${SECRET_ID}"
}
EOF

echo ""
echo "✅ Vault initialized and configured."
echo "   Credentials written to ${INIT_FILE} (gitignored — back this file up;"
echo "   losing it means starting over with a fresh volume)."
echo ""
echo "   To verify: docker exec -e VAULT_ADDR=http://127.0.0.1:8200 vault vault status"
echo "   Next step: docker compose up -d  (starts consumer-app once VSD-005 is done)"
