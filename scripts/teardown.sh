#!/usr/bin/env bash
# Full local-dev teardown: stop containers, clear vault/data/, remove
# credential files. Run this instead of bare `docker compose down` when you
# want a genuinely clean slate to re-run scripts/init.sh from scratch.
#
# Why not just `docker compose down -v`?
# vault/data/ is a bind mount, not a named Docker volume, so -v has no effect
# on it. The directory is owned by Vault's container-internal UID, so direct
# `rm -rf` on the host requires sudo. Instead, this script spins up a
# throw-away container with the same image — cleanup runs as the right UID,
# no sudo needed.
#
# All Vault commands run via `docker exec` — no host Vault CLI required.
set -euo pipefail

echo "==> Stopping containers..."
docker compose down

echo "==> Clearing vault/data/..."
if [ -d vault/data ] && [ -n "$(ls -A vault/data 2>/dev/null)" ]; then
  docker run --rm \
    -v "$(pwd)/vault/data:/vault/data" \
    --entrypoint sh \
    hashicorp/vault:1.17 \
    -c "find /vault/data -mindepth 1 -delete"
  echo "   vault/data/ cleared."
else
  echo "   vault/data/ already empty, skipping."
fi

echo "==> Removing credential files..."
rm -f .vault-init.json .env.consumer

echo ""
echo "✅ Teardown complete."
echo "   To start fresh: docker compose up vault -d && bash scripts/init.sh"
