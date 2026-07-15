#!/usr/bin/env bash
# Project-specific service health checks.
# Each check prints: SERVICE_NAME | STATUS | detail
# STATUS: UP or DOWN

set -uo pipefail

if docker ps --format '{{.Names}}' | grep -qx "vault"; then
  status_output=$(docker exec -e VAULT_ADDR="http://127.0.0.1:8200" vault vault status 2>&1 || true)
  if echo "$status_output" | grep -q "Sealed.*false"; then
    echo "vault | UP | container running, unsealed"
  elif echo "$status_output" | grep -q "Sealed.*true"; then
    echo "vault | DOWN | container running but sealed (run scripts/unseal.sh)"
  else
    echo "vault | DOWN | container running but not responding"
  fi
else
  echo "vault | DOWN | container not running (run: docker compose up vault -d)"
fi

if docker ps --format '{{.Names}}' | grep -qx "consumer-app"; then
  if curl -sf http://localhost:8000/status >/dev/null 2>&1; then
    echo "consumer-app | UP | responded on :8000/status"
  else
    echo "consumer-app | DOWN | container running but /status not responding"
  fi
else
  echo "consumer-app | DOWN | container not running (run: docker compose up consumer-app -d)"
fi
