# TICKETS — Vault Secrets Demo

Status values: `TODO`, `IN PROGRESS`, `READY FOR QA`, `REJECTED`, `DONE`

PM owns this file. Developer updates status to `READY FOR QA` when done.
QA updates status to `REJECTED` (with notes) or hands back to PM for final
`DONE` acceptance.

---

## VSD-001: Repo scaffolding and gitignore

**Status:** DONE

**Description:** Create the base repository structure as defined in
ARCHITECTURE.md — all directories, empty placeholder files where needed,
and a `.gitignore` that covers all secret-bearing paths before any other
code is written.

**Acceptance criteria:**
- Directory structure matches docs/ARCHITECTURE.md exactly
- `.gitignore` includes at minimum: `*.env*`, `unseal-keys.json`,
  `root-token.txt`, `.env.consumer`, `__pycache__/`, `.pytest_cache/`
- `LICENSE` (MIT) present
- Empty repo passes a manual review: no file in the initial commit could
  ever contain a real secret

**Dependencies:** None — first ticket

---

## VSD-002: Vault server configuration (no app yet)

**Status:** DONE

**Description:** Configure the Vault service in `docker-compose.yml` with
file storage backend and a listener config in `vault/config/vault-config.hcl`.
No TLS yet (local dev only at this stage).

**Acceptance criteria:**
- `docker compose up vault` starts a Vault container that responds to
  `vault status` (sealed, uninitialized — expected at this stage)
- `vault/config/vault-config.hcl` contains no secrets, is safe to commit
- Container restarts cleanly (`docker compose restart vault`) without
  losing its storage volume

**Dependencies:** VSD-001

---

## VSD-003: init.sh — operator bootstrap script

**Status:** DONE

**Description:** Write `scripts/init.sh` to fully bootstrap a fresh Vault
instance: init, unseal, enable KV v2, write policy, enable AppRole, create
role, seed multiple synthetic secrets covering different shapes/types, and
output AppRole credentials to a gitignored local file.

**Secrets to seed** (all obviously fake, no real-looking formats):

| Path | Type | Example shape |
|---|---|---|
| `secret/demo-db` | Key-value pair | `username=demo_user`, `password=demo-not-real-CHANGE-ME` |
| `secret/demo-api-key` | Single opaque string | `value=demo-fake-api-key-do-not-use-000111222` |
| `secret/demo-connection-string` | Single structured string | `value=postgresql://demo_user:demo-pass@localhost:5432/demo_db` |
| `secret/demo-signing-key` | Single opaque string | `value=demo-fake-jwt-signing-secret-xyz789` |
| `secret/demo-webhook` | Single URL-shaped string | `value=https://hooks.example.invalid/services/DEMO/FAKE/0000` |

Note: avoid any string that mimics a real provider's actual key format
(e.g. do not prefix with `AKIA`, `sk-ant-`, `ghp_`, etc.) **in the seeded
demo data only** — these patterns can trigger GitHub's automated
secret-scanning and push-protection even when fake, causing false-positive
alerts on this repo. Use a clearly invented format for the demo secrets.

This restriction applies only to what `init.sh` seeds automatically and
what ships in the repo/tests. It does **not** limit what a user stores in
their own running Vault instance after setup — the entire point of this
project is that a user can `vault kv put secret/my-real-key
value=<a real API key, real prefix and all>` and Vault stores it securely.
Real secrets a user adds live only in the Docker volume, never in git, so
the GitHub scanner concern doesn't apply to them. Add a line to the README
making this distinction explicit, so it doesn't read as "this tool can't
handle real keys."

**Acceptance criteria:**
- Running `scripts/init.sh` against a fresh, uninitialized Vault produces:
  unsealed Vault, KV v2 enabled at `secret/`, `demo-app-policy` applied,
  AppRole `demo-app` role created, all five secrets above seeded at their
  respective paths
- `demo-app-policy` grants read-only access to all five `secret/data/demo-*`
  paths (not just `demo-db`) — update the policy file accordingly
- Unseal keys and root token are written ONLY to a gitignored file
  (e.g. `.vault-init.json`), never printed to a location that could be
  accidentally committed or logged in CI
- Script is idempotent-safe: running it twice against an already-initialized
  Vault fails with a clear message rather than corrupting state
- `scripts/unseal.sh` exists separately for re-unsealing after a restart
- A code comment or inline doc explains why none of the seeded values use
  real-provider key formats (secret-scanner false-positive avoidance)

**Dependencies:** VSD-002

---

## VSD-004: vault_client.py — AppRole login and secret fetch

**Status:** DONE

**Description:** Implement `consumer-app/vault_client.py` using the `hvac`
library: AppRole login given `role_id` + `secret_id`, fetch a secret by
path, return only what's needed (never logs the raw secret).

**Acceptance criteria:**
- `vault_client.login()` returns a valid client token on correct
  credentials, raises a clear, typed exception on incorrect ones
- `vault_client.get_secret(path)` returns the secret dict on success
- No code path in this file ever calls `print()`, `logging.*`, or similar
  with the secret value included
- Unit tests (mocked `hvac` client) cover both success and failure paths

**Dependencies:** VSD-003 (needs real Vault to test against, even if
mocked in unit tests)

---

## VSD-005: Demo consumer app — FastAPI service

**Status:** DONE

**Description:** Implement `consumer-app/main.py`: on startup, use
`vault_client.py` to authenticate and fetch all five demo secrets
(`demo-db`, `demo-api-key`, `demo-connection-string`, `demo-signing-key`,
`demo-webhook`), use each in a small illustrative way, expose `GET /status`.

**What "using" each secret means (illustrative, all mocked — no real
external calls):**
- `demo-db` → "connect" to a mock SQLite DB
- `demo-api-key` → included as a header value in a mocked outbound request
  object (never actually sent anywhere)
- `demo-connection-string` → parsed to confirm it's well-formed (proves
  Vault returned the structured string intact)
- `demo-signing-key` → used to sign a trivial mock payload locally (e.g.
  HMAC of a fixed string), proving the key works without ever printing it
- `demo-webhook` → validated as a well-formed URL, not actually called

**Acceptance criteria:**
- `GET /status` returns a per-secret status object, e.g.:
  ```json
  {
    "vault_auth": "ok",
    "demo_db": "ok",
    "demo_api_key": "ok",
    "demo_connection_string": "ok",
    "demo_signing_key": "ok",
    "demo_webhook": "ok"
  }
  ```
- On Vault unreachable or auth failure, `/status` returns a clear error
  state — app does not crash on startup if Vault is temporarily
  unavailable; returns degraded status instead
- No secret value (any of the five) ever appears in any HTTP response
  body, including error responses
- `Dockerfile` builds and runs the app correctly in the compose stack

**Dependencies:** VSD-004

---

## VSD-006: Test suite — leakage and failure-mode coverage

**Status:** DONE

**Description:** Implement the full test suite per the testing spec:
`test_vault_client.py`, `test_auth_failure.py`, `test_no_secret_leakage.py`,
`test_integration.py`.

**Acceptance criteria:**
- All four test files exist and pass against a running test Vault instance
- `test_no_secret_leakage.py` captures stdout/stderr across a full app
  startup + `/status` call and asserts **all five** known placeholder
  secret values (db password, api key, connection string, signing key,
  webhook URL) never appear anywhere in captured output or response
  bodies — one assertion per secret, not a single combined check, so a
  failure clearly identifies which secret leaked
- `test_auth_failure.py` confirms a wrong `secret_id` produces a clean
  failure, not a crash or stack trace leak
- `test_vault_client.py` covers fetching each of the five secret shapes
  (key-value vs. single-string) correctly
- Test suite runs in under 60 seconds locally

**Dependencies:** VSD-005

---

## VSD-007: CI pipeline

**Status:** DONE

**Description:** GitHub Actions workflow that spins up the full stack,
runs `init.sh` in a CI-safe mode, runs the test suite, and tears down —
failing the build hard on any secret-leakage test failure.

**Acceptance criteria:**
- `.github/workflows/test.yml` runs on every push and PR
- Workflow spins up Vault + consumer app via Docker Compose, runs init,
  runs pytest, tears down
- Unseal keys / root token generated during the CI run are never written
  to a workflow artifact, log output, or cache
- A deliberately failing secret-leakage test (temporary, for verification
  only) confirms the build actually fails red — then is removed before
  merge

**Dependencies:** VSD-006

---

## VSD-008: README and documentation

**Status:** DONE

**Description:** Write the public-facing `README.md`, `docs/ARCHITECTURE.md`,
and `docs/AWS_DEPLOYMENT.md`.

**Acceptance criteria:**
- README covers: what it is, architecture summary, quickstart (clone →
  `docker compose up` → `init.sh` → verify `/status`), security scope,
  design-decision rationale table
- README includes a clear section: "Using this with real secrets" —
  explaining that the seeded demo secrets are fake placeholders for
  testing only, and showing the exact `vault kv put` command a user runs
  to store their own real credentials (any provider, any format) once
  Vault is running. Makes explicit that real secrets never touch git —
  they live only in the Vault storage volume
- `docs/AWS_DEPLOYMENT.md` is followable end-to-end by someone who has
  never used Vault, including the security-group caveat (restrict to your
  IP, not `0.0.0.0/0`) and the manual-unseal-after-reboot limitation
- Screenshot placeholder noted, using demo/placeholder data only
- LICENSE (MIT) linked

**Dependencies:** VSD-001 through VSD-007 (written last, once behavior is
final)

---

## VSD-009: Pre-publish security audit

**Status:** DONE

**Description:** Final manual pass before the repo goes public — not
delegated to Developer/QA roles, performed by the project owner directly.

**Acceptance criteria:**
- `git log --all --full-history` blob scan for any of: real secret values,
  unseal keys, root tokens, AppRole `secret_id` values
- Manual run of `docker compose up` + `init.sh` from a clean clone,
  confirming `/status` returns healthy and no secret appears anywhere
  on screen or in logs
- `.gitignore` re-verified against the final file tree (not just the
  initial scaffold)

**Dependencies:** All previous tickets DONE

---

## VSD-010 — Home lab deployment documentation

**Goal:** Document deployment on a Proxmox home lab environment and
integration with other portfolio projects.

**Deliverables:**
- `docs/HOMELAB_DEPLOYMENT.md` — full deployment walkthrough for
  Proxmox VE + Ubuntu Server VM environment
- README platform support table updated with home lab entry
- Integration notes for expiry-watcher AppRole setup
- Multi-project coexistence documented (ports, Portainer visibility)

**Tested on:**
- Proxmox VE 9.2.3, Beelink SER mini PC
- Ubuntu Server 24.04.3 LTS VM
- Docker 29.6.0

**Dependencies:** VSD-008, VSD-009

**Status: DONE**

---

## VSD-011: AppRole `secret_id` given a finite TTL

**Status:** DONE

**Description:** `scripts/init.sh` currently creates the `demo-app` AppRole
role with `secret_id_ttl=0`, which is Vault's syntax for "this secret_id
never expires." This contradicts the README's provider-comparison table,
which claims "AppRole `secret_id` and tokens have TTLs." Give the
`secret_id` a finite, demo-appropriate TTL so the credential's lifecycle
actually matches the README's claim, and add a regression test so this
can't silently regress back to unlimited.

**Acceptance criteria:**
- `auth/approle/role/demo-app` is created with a non-zero, finite
  `secret_id_ttl` (target: 90 days) — long enough that the
  quickstart/CI flow is never at risk of hitting it, short enough to be a
  real TTL and not security theater. Documented with a one-line comment
  in `init.sh`, matching the existing comment style next to
  `token_ttl`/`token_max_ttl`.
- `vault read auth/approle/role/demo-app` after running `scripts/init.sh`
  shows the new finite value, not `0`.
- A fresh `secret_id` issued via `scripts/init.sh` or
  `scripts/issue-consumer-creds.sh` inherits the new TTL automatically —
  confirmed empirically, no code change needed in
  `issue-consumer-creds.sh`.
- A new regression test asserts the configured `secret_id_ttl` on the
  `demo-app` role is non-zero, and is mutation-tested (proven to fail red
  at `secret_id_ttl=0`, pass green at the fix).
- Full existing test suite still passes: `pytest tests/ -v`.
- No change to `demo-app-policy`'s read-only scope
  (`secret/data/demo-*` only, capabilities `["read"]`).
- README's TTL claim in the comparison table remains accurate; a one-line
  note added near the table documenting the 90-day value and the
  recovery path (`scripts/issue-consumer-creds.sh`) if it's ever hit.
- Explicit secrets scan on the diff before shipping.

**Dependencies:** None — touches `scripts/init.sh`, a new test file, and
doc/comment lines only; all previously-DONE tickets are unaffected.

---

## Ticket status

| Ticket | Title | Status |
|---|---|---|
| VSD-001 | Repo scaffolding and gitignore | DONE |
| VSD-002 | Vault server configuration | DONE |
| VSD-003 | init.sh — operator bootstrap script | DONE |
| VSD-004 | vault_client.py — AppRole login and secret fetch | DONE |
| VSD-005 | Demo consumer app — FastAPI service | DONE |
| VSD-006 | Test suite — leakage and failure-mode coverage | DONE |
| VSD-007 | CI pipeline | DONE |
| VSD-008 | README and documentation | DONE |
| VSD-009 | Pre-publish security audit | DONE |
| VSD-010 | Home lab deployment documentation | DONE |
| VSD-011 | AppRole `secret_id` given a finite TTL | DONE |
