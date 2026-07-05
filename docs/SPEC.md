# SPEC — Vault Secrets Demo

`docs/ARCHITECTURE.md` already covers the component diagram, directory
structure, secrets stored, auth flow, policy, and design decisions in
depth — this file doesn't repeat that. It covers what's one layer down:
the actual code (`consumer-app/`), the bootstrap script's exact
mechanics, and the test suite's leakage-proof strategy.

---

## `consumer-app/vault_client.py`

```python
VaultClient(url, role_id, secret_id)
  .login() -> None                    # raises VaultAuthError
  .get_secret(path: str) -> dict       # raises VaultSecretError
```

Thin wrapper over `hvac`. `login()` performs the AppRole login and then
explicitly checks `client.is_authenticated()` — `hvac`'s login call can
return without raising in some failure modes, so the authenticated-check
is a deliberate second gate, not redundant. Both exceptions wrap the
underlying `hvac`/`requests` exception's *type name only*
(`type(exc).__name__`), never `str(exc)` — this is intentional: some
`hvac`/`requests` exception messages can echo back part of the request
(including the path or, in edge cases, header values), and the type
name alone is enough for the `/status` endpoint's per-secret ok/failed
reporting without risking a leak into an HTTP response.

`get_secret` always reads via
`secrets.kv.v2.read_secret_version(mount_point="secret",
raise_on_deleted_version=True)` — the explicit
`raise_on_deleted_version` means a soft-deleted KV v2 secret version
raises rather than silently returning the last surviving version, which
matters for a demo whose whole point is proving the auth/fetch path
actually works end-to-end.

## `consumer-app/main.py`

Single FastAPI route: `GET /status`. All secret-consumption logic runs
once, at startup, via a `lifespan` context manager (`_bootstrap()`) —
not per-request. This means:

- The app's demonstrated behavior (auth → fetch 5 secrets → "use" each)
  happens exactly once per container lifetime, matching the real-world
  pattern of a service authenticating at boot and caching what it needs,
  not re-authenticating to Vault on every incoming request.
- `/status` is a pure read of the in-memory `_status` dict populated at
  startup — it never touches Vault itself, so hitting it repeatedly
  can't cause repeated AppRole logins or secret reads.

`_status` starts all five keys (`vault_auth`, `demo_db`,
`demo_api_key`, `demo_connection_string`, `demo_signing_key`,
`demo_webhook`) as `"pending"`. If `client.login()` raises
`VaultAuthError`, `vault_auth` is set to `"failed: VaultAuthError"` and
`_bootstrap` returns immediately — none of the five secrets are even
attempted, since there's no authenticated client to fetch them with.
Otherwise each of the five `_use_demo_*` functions is tried
independently inside its own `try/except Exception`, so one secret's
"use" logic raising (e.g. a malformed connection string failing
`urllib.parse` validation) doesn't stop the other four from being
demonstrated. Every failure path stores only
`f"failed: {type(exc).__name__}"` — same leak-avoidance pattern as
`vault_client.py`, applied consistently at the call site that actually
produces the HTTP response.

The five "use" functions are deliberately trivial and side-effect-free
beyond an in-memory demonstration (an in-memory SQLite insert, an HMAC
computation, URL parsing) — see `docs/ARCHITECTURE.md`'s design
decisions for why real external calls are out of scope.

## `scripts/init.sh` — exact bootstrap sequence

Everything is `docker exec` into the running Vault container — no host
Vault CLI required. Sequence:

1. **Prerequisite check** — the `vault` container must already be
   running (`docker compose up vault -d`); exits with a clear error and
   the exact command to run otherwise.
2. **Idempotency guard** — checks `vault status` for
   `Initialized: true` and refuses to proceed if Vault is already
   initialized, rather than silently reinitializing (which would
   orphan the existing unseal key/root token). Points at
   `docker compose down -v` as the explicit "start fresh" path.
3. **Init** — `vault operator init -key-shares=1 -key-threshold=1`
   (single unseal key/share, appropriate for a single-node demo, not
   production — see ARCHITECTURE.md). Retried up to 3 times: the Docker
   healthcheck can report ready while Vault's storage layer is still
   settling, causing an immediate first attempt to fail in CI.
4. **Unseal** — feeds the one unseal key back in.
5. **KV v2 mount, AppRole auth method, read-only policy, AppRole role**
   — created via authenticated (`vault_exec_root`, using the root token
   from step 3) calls.
6. **Seed the five demo secrets** at `secret/demo-*` — the fake,
   provider-format-avoiding placeholder values described in the README.
7. **Write credentials** — `.vault-init.json` (root token + unseal key,
   gitignored) and `.env.consumer` (the AppRole `role_id`/`secret_id`
   the consumer app reads at startup, also gitignored).

## Test suite structure

| File | What it proves |
|---|---|
| `test_vault_client.py` | `VaultClient` unit behavior against a mocked `hvac.Client` |
| `test_auth_failure.py` | Wrong/revoked AppRole credentials fail cleanly — `vault_auth` reports `"failed: ..."`, app doesn't crash |
| `test_integration.py` | Full stack against a real Vault (via the `vault` pytest marker / live docker-compose target in CI) |
| `test_no_secret_leakage.py` | The actual security property this project exists to demonstrate |

`test_no_secret_leakage.py`'s strategy: `secret_values.py` holds the
known plaintext of every seeded demo secret
(`KNOWN_SECRET_VALUES["db_password"]` etc. — these are the same fake
placeholder values `init.sh` seeds, not real credentials). The `full_run`
fixture drives a real `/status` request through `TestClient`, captures
**stdout, stderr, and the HTTP response body together** via `capsys` +
`response.text`, and each test asserts a specific known secret value is
absent from that combined output. This is a substring search across
every observable output surface, not a mock-based assertion — it would
actually fail if a future change accidentally `print()`'d a secret or
put one in an error message. `HANDOFF.md`'s audit notes record a real
mutation-test of this exact suite: a commit titled "TEMP: deliberate
leak for CI verification — revert next commit" printed one of the fake
seed values (`demo-not-real-CHANGE-ME`) from inside the app, confirmed
`test_no_secret_leakage.py` failed as expected, and the next commit
reverted the print statement.
