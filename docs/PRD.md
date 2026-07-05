# PRD — Vault Secrets Demo

## Problem statement
Secrets (API keys, DB passwords) shouldn't live in plaintext `.env` files or
in git history. Most solo/small-team developers either commit secrets by
accident or rely on a single cloud vendor's proprietary secrets service,
creating lock-in. This project demonstrates a cloud-agnostic secrets pattern
using HashiCorp Vault that runs identically on a laptop or any cloud VM.

## Goals
- G1: Stand up a self-hosted Vault server in Docker, sealed/unsealed correctly
- G2: Store and serve secrets via the KV v2 secrets engine
- G3: Authenticate a demo consumer app to Vault using AppRole (not root token)
- G4: Demo app proves it can fetch and use a secret without ever logging or
  displaying the secret value itself
- G5: Document a path to deploy the same Vault container to AWS EC2
- G6: Zero secrets — real or synthetic-but-realistic — ever committed to git

## Non-goals
- Not a production-grade HA Vault cluster (single-node setup)
- Not integrated with an existing app (Study Hub / Wellbeing Assistant) in v1
- Not implementing Vault's auto-unseal (manual unseal is fine and more
  instructive for a demo)
- Not implementing secret rotation automation in v1 (documented as a v2
  follow-up)

## Success criteria
- A fresh clone + `docker compose up` + init script gets Vault running,
  unsealed, and seeded with five synthetic secrets in under 5 minutes
- The demo consumer app authenticates via AppRole, fetches all five
  secrets, uses each in a small illustrative way, and returns a
  per-secret ok/failed status via `GET /status` — never the secret values
- All tests pass: `pytest` suite covers auth failure, successful fetch,
  and secret-value-never-logged assertion
- README documents the AWS EC2 deployment path clearly enough to follow
  without prior Vault experience

## Out of scope risks (explicitly documented, not solved)
- This is a single-node Vault setup — not resilient to the host disappearing
- Manual unseal means a server restart requires manual intervention
  (acceptable for a portfolio demo; flagged in README as a production gap)

## Architecture summary

```
Docker Compose
  ├── Vault server (hashicorp/vault image, file storage, KV v2 at secret/)
  │     unsealed manually via init.sh / unseal.sh
  └── Demo consumer app (FastAPI)
        1. Authenticates to Vault via AppRole (role_id + secret_id)
        2. Fetches all five secrets (demo-db, demo-api-key,
           demo-connection-string, demo-signing-key, demo-webhook)
        3. Uses each in a small illustrative way (mocked — no real calls)
        4. Exposes GET /status -> per-secret ok/failed JSON
           (never returns a secret value)
```

Full architecture detail: see `docs/ARCHITECTURE.md`.

## Design decisions and rationale

| Decision | Reasoning |
|---|---|
| File storage backend, not Consul/Raft | Simpler for a demo; the auth/secrets pattern is the teaching point, not HA storage |
| Manual unseal | More instructive — operator sees the actual unseal mechanic instead of it being hidden by auto-unseal |
| AppRole over token | Matches production practice; `secret_id` can be rotated/revoked independently of `role_id` |
| Read-only policy scoped to `demo-*` paths | Principle of least privilege — demo app can't read or write anything else in Vault |
| Mock DB, not a real one | Keeps the demo focused on the secrets pattern, not database setup |

## Definition of done (project-level)
- `docker compose up` + `scripts/init.sh` brings up a working system from a
  clean clone
- Full test suite passes in CI
- `docs/AWS_DEPLOYMENT.md` is followable end-to-end
- No secret value, key, or token ever appears in git history (verified via
  blob scan before any public release)
