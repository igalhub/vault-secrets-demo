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

# Print Vault status so CI logs show exactly what state we're operating against.
echo "==> Vault status before init:"
vault_exec status 2>&1 || true

echo "==> Initializing Vault (1 unseal key, threshold 1 — appropriate for a demo)..."
# Using -key-shares=1 -key-threshold=1 to keep unseal simple for a single-node demo.
# A production deployment would use a higher shares/threshold (e.g. 5/3).
#
# Retried up to 3 times: the Docker healthcheck can pass while Vault's internal
# storage layer is still settling, causing the first init attempt to fail in CI.
# Stderr is NOT redirected so Vault's error messages always appear in the log.
init_output=""
init_rc=0
for attempt in 1 2 3; do
  set +e
  init_output=$(vault_exec operator init -key-shares=1 -key-threshold=1)
  init_rc=$?
  set -e
  [ "$init_rc" -eq 0 ] && break
  if [ "$attempt" -eq 3 ]; then
    echo "ERROR: vault operator init failed after 3 attempts (last exit code: ${init_rc})." >&2
    exit 1
  fi
  echo "   Attempt ${attempt} failed (exit ${init_rc}), retrying in 3s..." >&2
  sleep 3
done

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

# The approle mount defaults to a 32-day max_lease_ttl, which silently caps
# any role's secret_id_ttl above that — so demo-app's 90d setting below
# would otherwise be issued as 32 days without this tune (VSD-011). This
# raises the ceiling for every role on this mount, including any other
# project's role that shares this same Vault instance (e.g. expiry-watcher,
# see docs/HOMELAB_DEPLOYMENT.md) — but it's a maximum, not a forced value,
# so a role that already requests a shorter TTL is unaffected.
vault_exec_root auth tune -max-lease-ttl=90d approle

echo "==> Creating demo-app role..."
# secret_id_ttl=90d: finite so the credential is rotatable/revocable in
# practice (VSD-011) — long enough that no CI run or normal dev cycle
# ever hits it, short enough to not be security theater.
vault_exec_root write auth/approle/role/demo-app \
  token_policies=demo-app-policy \
  token_ttl=1h \
  token_max_ttl=4h \
  secret_id_ttl=90d

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

# ── Write consumer-app env file ────────────────────────────────────────────────
# VAULT_ADDR uses the Docker service name so the container can reach Vault
# over the internal compose network — not localhost.

cat > ".env.consumer" <<EOF
VAULT_ADDR=http://vault:8200
VAULT_ROLE_ID=${ROLE_ID}
VAULT_SECRET_ID=${SECRET_ID}
EOF

echo ""
echo "✅ Vault initialized and configured."
echo "   ${INIT_FILE}   — full credentials (unseal key + root token + AppRole)"
echo "   .env.consumer  — AppRole creds for docker compose (both gitignored)"
echo ""
echo "   Lose either file and you will need a fresh volume to recover."
echo ""
echo "   Next step: docker compose up -d"
echo "   Verify:    curl http://localhost:8000/status"
