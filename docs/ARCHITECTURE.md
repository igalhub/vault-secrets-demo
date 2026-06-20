# Architecture — Vault Secrets Demo

## Overview

A two-container Docker Compose stack: a self-hosted Vault server and a
FastAPI consumer app that authenticates to Vault using AppRole and fetches
secrets at runtime. No secret value is ever written to disk, logged, or
returned in an HTTP response.

---

## Component diagram

```
Docker Compose
  ├── vault  (hashicorp/vault, file storage backend, KV v2 at secret/)
  │     - Initialized and unsealed manually via scripts/init.sh
  │     - Re-sealed on every restart; unseal via scripts/unseal.sh
  │     - Stores: demo-db, demo-api-key, demo-connection-string,
  │               demo-signing-key, demo-webhook
  │     - Exposes: http://localhost:8200 (internal + host)
  │
  └── consumer-app  (FastAPI, Python 3.12)
        On startup:
          1. Reads VAULT_ROLE_ID and VAULT_SECRET_ID from environment
          2. Calls Vault AppRole login → receives a short-lived token
          3. Fetches all five secrets via token-authenticated KV v2 reads
          4. Uses each secret in a mocked, illustrative way (no real calls)
        Exposes: GET /status → per-secret ok/failed JSON
                 (never returns a secret value)
```

---

## Directory structure

```
vault-secrets-demo/
├── .github/
│   └── workflows/
│       └── test.yml              # CI: spin up stack, init, pytest, tear down
├── consumer-app/
│   ├── Dockerfile
│   ├── main.py                   # FastAPI app, startup logic, /status endpoint
│   ├── requirements.txt
│   └── vault_client.py           # AppRole login + KV v2 fetch (hvac)
├── docs/
│   ├── ARCHITECTURE.md           # this file
│   ├── AWS_DEPLOYMENT.md         # EC2 deployment walkthrough
│   └── screenshot.png            # demo screenshot (placeholder)
├── scripts/
│   ├── init.sh                   # one-time bootstrap: init, unseal, seed, AppRole
│   └── unseal.sh                 # re-unseal after a restart
├── tests/
│   ├── __init__.py
│   ├── test_auth_failure.py      # wrong secret_id → clean failure, no crash
│   ├── test_integration.py       # full stack: login + /status returns healthy
│   ├── test_no_secret_leakage.py # asserts no secret value appears in output
│   └── test_vault_client.py      # unit tests for vault_client.py (mocked hvac)
├── vault/
│   ├── config/
│   │   └── vault-config.hcl      # listener, storage, log config — safe to commit
│   └── data/                     # Vault file-storage volume (gitignored)
├── .gitignore
├── docker-compose.yml
├── docker-compose.test.yml       # overlay for test environment
├── LICENSE
├── PRD.md
├── README.md
└── TICKETS.md
```

---

## Secrets stored

| Vault path | Type | Illustrative use in consumer app |
|---|---|---|
| `secret/demo-db` | Key-value (`username` + `password`) | Mock SQLite connection |
| `secret/demo-api-key` | Single opaque string (`value`) | Header in a mocked outbound request |
| `secret/demo-connection-string` | Structured string (`value`) | Parsed to confirm well-formed URL |
| `secret/demo-signing-key` | Single opaque string (`value`) | HMAC of a fixed payload |
| `secret/demo-webhook` | URL-shaped string (`value`) | Validated as a well-formed URL |

---

## Authentication flow

```
consumer-app                     Vault
      │                             │
      │── POST /v1/auth/approle ──► │
      │      role_id + secret_id    │
      │◄── client_token ───────────  │
      │                             │
      │── GET /v1/secret/data/* ──► │  (token in X-Vault-Token header)
      │◄── secret data ─────────── │
```

AppRole is used instead of a static root token because `secret_id` can be
rotated or revoked independently of `role_id`, matching production practice.

---

## Policy (principle of least privilege)

The `demo-app-policy` grants read-only access to the five demo paths and
nothing else:

```hcl
path "secret/data/demo-*" {
  capabilities = ["read"]
}
```

The consumer app cannot read other Vault paths, create/update/delete
secrets, or access Vault's system internals.

---

## Design decisions

| Decision | Reasoning |
|---|---|
| File storage backend | Simpler for a demo; the auth/secrets pattern is the teaching point, not HA storage |
| Manual unseal | More instructive — you see the actual unseal mechanic instead of it being hidden by auto-unseal |
| AppRole over root token | Matches production practice; `secret_id` can be rotated/revoked independently of `role_id` |
| Read-only policy scoped to `demo-*` paths | Principle of least privilege — the consumer app can't read or write anything else in Vault |
| Mock external calls | Keeps the demo focused on the secrets pattern, not on standing up real databases or third-party services |
| No TLS for local dev | Intentional simplification; TLS is required and documented for EC2 deployment |

---

## Production gaps (documented, not solved)

These are intentional simplifications appropriate for a portfolio demo:

- **Single node, file backend** — not resilient to the host disappearing; no HA
- **Manual unseal** — a server restart requires a human to run `unseal.sh`
- **No TLS locally** — required if you expose Vault over a network (see `docs/AWS_DEPLOYMENT.md`)
- **No secret rotation automation** — documented as a v2 follow-up

---

## Data flow: secret never touches a log or response

```
Vault storage (encrypted at rest)
    │
    ▼ (KV v2 API read, token-authenticated)
vault_client.get_secret(path) → Python dict in memory
    │
    ▼ (used in-process only)
mock_connect(password=secret["password"])   ← value used, not stored or logged
    │
    ▼ (status only, no value)
GET /status → {"demo_db": "ok"}
```
