# Vault Secrets Demo

A standalone, cloud-agnostic secrets management demo built on HashiCorp
Vault. Proves the AppRole authentication pattern end-to-end with a mock
consumer app — deployable locally via Docker, with a documented path to
AWS EC2.

> **Screenshot:** a full-stack screenshot is pending (post-deploy); see `docs/AWS_DEPLOYMENT.md` for the expected `/status` output.

> **What this is:** A reference implementation, not a production system.
> It shows how to run Vault, authenticate a service to it without a
> long-lived root token, and fetch secrets at runtime — patterns you can
> adapt into any of your own projects, regardless of which cloud (or no
> cloud) you deploy to.

---

## Why this exists

Secrets — API keys, database passwords, signing keys — need somewhere
safe to live that isn't a plaintext `.env` file or a wiki page. This
project demonstrates one solid answer: a self-hosted Vault instance that
any app, on any host, can authenticate to and pull secrets from at
runtime, with nothing sensitive ever committed to git.

---

## Why not just keep secrets in a Confluence page?

A common pattern (and the one I came from) is a Confluence doc with a
restricted viewer/editor list. It's better than nothing, but it has real
gaps:

| Problem | Confluence (access-list) | SOPS (encrypted file in git) | Vault (this project) |
|---|---|---|---|
| Secret is encrypted, not just access-restricted | ❌ Plaintext to anyone with page access | ✅ Real encryption (age/GPG), key never in git | ✅ Stored encrypted, served only via authenticated API |
| Audit trail of actual secret access | ❌ Page views only, not "who copied the password" | ⚠️ Git history shows *when the value changed*, not who decrypted it locally | ✅ Full audit log of every read |
| Automatic rotation | ❌ Manual | ❌ Manual | ✅ Supports dynamic, auto-rotated secrets |
| Expiry / TTL on access | ❌ None | ❌ None | ✅ AppRole `secret_id` and tokens have TTLs |
| Reduces copy-paste sprawl | ❌ Every use is a copy-paste | ⚠️ Better — decrypted only at point of use | ✅ Apps fetch directly, no manual copying |
| Cost | Free (if you already pay for Confluence) | Free | Free (Community Edition) |
| Works the same on any host/cloud | N/A | ✅ Yes — it's just a file | ✅ Yes — same Docker image anywhere |

**The honest summary:** SOPS is a meaningful upgrade over a wiki page —
real encryption, versioned, no plaintext ever at rest. But it's still a
*static file* model. Vault is the bigger leap because it's a live
service: it adds audit logging, automatic rotation, and TTL-bound access
that a SOPS file structurally can't provide. If you mainly distrust
"access lists as security," SOPS already solves that. If you also want
to know *who read what, when*, and want credentials that expire on their
own, Vault is the one that delivers that.

---

## Cost

**Vault itself is free.** This project uses Vault **Community Edition**
— open source, no license fee, no usage limits, runs anywhere via Docker.

What you're *not* using, and what does cost money:
- **HCP Vault** (HashiCorp's managed/hosted Vault) — paid, not used here
- **Vault Enterprise** — paid, adds multi-datacenter replication and
  governance features aimed at large organizations — not needed for this
  project and not used here

The only real cost in this setup is infrastructure, not Vault licensing:
- Running locally on your machine: $0
- Running on AWS EC2 (see `docs/AWS_DEPLOYMENT.md`): covered under the
  AWS free tier for new accounts, or a few dollars a month on a
  `t3.micro` afterward — the same cost profile as any small EC2 instance,
  not a Vault-specific charge

---

## How it works (technical)

```
Docker Compose
  ├── Vault server (hashicorp/vault image, file storage, KV v2 at secret/)
  │     unsealed manually via init.sh / unseal.sh
  └── Demo consumer app (FastAPI)
        1. Authenticates to Vault via AppRole (role_id + secret_id)
        2. Fetches five demo secrets (db creds, API key, connection
           string, signing key, webhook URL)
        3. Uses each in a small illustrative way (mocked — no real
           external calls)
        4. Exposes GET /status -> per-secret ok/failed status
           (never returns a secret value itself)
```

Full architecture detail: see `docs/ARCHITECTURE.md`.

### Design decisions

| Decision | Reasoning |
|---|---|
| File storage backend, not Consul/Raft | Simpler for a demo; the auth/secrets pattern is the teaching point, not HA storage |
| Manual unseal | More instructive — you see the actual unseal mechanic instead of it being hidden by auto-unseal |
| AppRole over root token | Matches production practice; `secret_id` can be rotated/revoked independently of `role_id` |
| Read-only policy scoped to demo paths | Principle of least privilege — the demo app can't read or write anything else in Vault |
| Mock DB and mocked external calls | Keeps the demo focused on the secrets pattern itself, not on standing up real databases or third-party services |

---

## Using this with real secrets

The five secrets seeded by `scripts/init.sh` are **fake placeholders for
testing only** — they deliberately avoid real provider key formats (no
`sk-ant-`, `AKIA`, `ghp_` prefixes), because plaintext seed data in a
public repo can trigger GitHub's automated secret-scanning even when the
value is fake.

That restriction applies only to what ships in this repo. **It doesn't
limit what you store in your own running Vault instance.** Once Vault is
up, store a real credential like this:

```bash
vault kv put secret/my-real-key value="sk-ant-your-actual-key-here"
```

Real secrets you add this way live only in Vault's storage volume — never
in git, never scanned by GitHub, because they're never committed at all.
That's the actual point of the project: a place to put real secrets that
isn't a file in your repo or a page in a wiki.

---

## Setup

### Prerequisites
- Docker and Docker Compose
- No other dependencies — the consumer app runs in its own container

### Quickstart

```bash
git clone https://github.com/igalhub/vault-secrets-demo.git
cd vault-secrets-demo

# Pre-create vault/data/ with ownership that Vault's container user can write to.
# (See troubleshooting note below for why this is required.)
mkdir -p vault/data
sudo chown 100 vault/data

# Step 1: start Vault only (.env.consumer doesn't exist yet)
docker compose up vault -d

# Step 2: initialize Vault, seed secrets, write .env.consumer
bash scripts/init.sh

# Step 3: start the consumer app (now that .env.consumer exists)
docker compose up consumer-app -d
```

`init.sh` initializes Vault, unseals it, enables the KV v2 engine, sets
up the AppRole auth method and policy, seeds the five demo secrets, and
writes AppRole credentials to two **gitignored** local files
(`.vault-init.json` and `.env.consumer`). Back up `.vault-init.json` if
you want to manage Vault manually later — losing it means you'll need a
fresh volume to recover.

### Troubleshooting: `mkdir /vault/data/core: permission denied`

If you see this error from `scripts/init.sh`, the cause is a container
UID mismatch on the bind mount.

**What happens:** the Vault image's entrypoint uses `su-exec` to run the
Vault server process as the internal `vault` user (UID 100) rather than
as root. On a fresh `git clone`, `vault/data/` doesn't exist (it's
gitignored). When Docker Compose creates it automatically, it creates it
as `root:root 755`. UID 100 is not root and can't write to a root-owned
directory, so the first write (`vault operator init` creating
`vault/data/core/`) fails with `permission denied`.

**Fix:**

```bash
docker compose down
sudo chown 100 vault/data
docker compose up vault -d
bash scripts/init.sh
```

To verify that 100 is the right UID for the image version you're using:

```bash
docker run --rm --entrypoint sh hashicorp/vault:1.17 \
  -c 'grep vault /etc/passwd'
# Expected: vault:x:100:1000:...
```

Verify it worked (uvicorn needs a few seconds to complete the Vault login
and five-secret bootstrap before the port is ready):

```bash
curl --retry 10 --retry-delay 1 --retry-connrefused -sf \
  http://localhost:8000/status
```

Expected output (all six keys `"ok"`):

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

### Restarting after a stop

Vault re-seals on every restart (manual unseal is intentional — see
Design decisions above). The cleanest restart sequence:

```bash
# Start Vault first, then unseal before the consumer app tries to authenticate
docker compose up vault -d
bash scripts/unseal.sh
docker compose up consumer-app -d
```

Alternatively, if you bring everything up at once:

```bash
docker compose up -d            # consumer-app starts with vault_auth: "failed" (vault is sealed)
bash scripts/unseal.sh          # unseal vault
docker compose restart consumer-app   # re-authenticate now that vault is unsealed
```

### Recovery: missing or stale .env.consumer

If `.env.consumer` is missing or out of date (e.g. you ran `init.sh`
before the env file feature existed, or the secret_id expired), re-issue
a fresh `secret_id` without re-initializing Vault:

```bash
bash scripts/issue-consumer-creds.sh
docker compose up consumer-app -d
```

Requires an initialized, unsealed Vault and `.vault-init.json` present.

### Starting fresh (local teardown)

To fully reset the local environment — stop containers, clear Vault's
storage, and remove credential files:

```bash
bash scripts/teardown.sh
```

This uses a throw-away container to clear `vault/data/` (files are owned
by Vault's container UID, not your user, so `rm -rf` on the host would
require `sudo`). After teardown, run the quickstart sequence again.

### AWS EC2 deployment

See `docs/AWS_DEPLOYMENT.md` for the full walkthrough, including the
security-group configuration (restrict access to your own IP, not
`0.0.0.0/0`) and the manual-unseal-after-reboot limitation.

---

## Security scope

This is a demo/reference project, not a hardened production deployment.
Specifically:

- Single-node Vault, file storage backend — not resilient to the host
  disappearing; no high availability
- Manual unseal — a server restart requires you to re-run `unseal.sh`
- TLS is disabled by default for local use; **required** if you deploy
  to EC2 — see `docs/AWS_DEPLOYMENT.md`

These are documented tradeoffs appropriate for a personal/demo project,
not oversights. A production deployment would add a proper storage
backend (Consul or integrated Raft), auto-unseal via a cloud KMS, and
TLS with a real certificate.

---

## Platform support

This project draws a clear line between what's been tested end-to-end and
what's reasonably expected to work but hasn't been verified. Two separate
questions are involved, and they don't move together: **where you run the
commands from** (your local dev machine) and **where Vault itself ends up
running** (local, or a cloud VM).

### Local development platform

| Platform | Status | Notes |
|---|---|---|
| **Linux** | ✅ Tested | Every command, script, and bug fix in this repo was developed and verified on Ubuntu 24.04, including a genuine fresh-clone smoke test. Also verified in CI on every push (`ubuntu-latest`). |
| **macOS** | ⚠️ Unverified — CI attempt was inconclusive | A CI job was added specifically to find out whether macOS hits the same bind-mount permission issue as Linux. It didn't get far enough to answer that question: Colima (the Docker runtime used to get Docker onto the GitHub-hosted macOS runner) failed to start its VM — `error starting vm: error at 'creating and starting': exit status 1`. This is a known limitation of nested virtualization on GitHub's hosted macOS runners, not a bug in this project. Verifying macOS support properly requires testing on real Mac hardware with Docker Desktop installed natively, which hasn't been done yet. |
| **Windows** | ❌ Requires a different setup, untested | The `.sh` scripts (`init.sh`, `unseal.sh`, `teardown.sh`, etc.) need a bash-compatible environment to run at all — native Windows `cmd`/PowerShell can't execute them directly. **WSL2** is the recommended path; Git Bash may work for some scripts but isn't verified. `sudo chown` has no direct Windows equivalent outside WSL2. Treat this as "needs porting," not "needs minor adjustment." |

### Why the bind-mount permission issue matters here

Several scripts in this repo work around a specific bug: Vault's official
Docker image runs its server process as a non-root internal user
(UID 100), but a bind-mounted `vault/data/` directory created fresh by
Docker Compose is typically owned by your host user, not UID 100 — so
Vault can't write to it until you manually run
`sudo chown 100 vault/data`. This was found and fixed during development
on Linux (and confirmed to affect a real GitHub Actions Linux CI runner
too, fixed there with a `chmod`). Whether this exact issue, exactly this
way, appears on macOS or Windows-via-WSL2 is still unknown — the
underlying cause (container UID vs. host-created directory ownership) is
Docker-architecture-specific, not Linux-specific, so it's reasonable to
expect *some* version of this issue on other platforms, but neither the
exact symptom nor the fix has been confirmed there.

### Cloud deployment target

Separately from your local dev platform, Vault itself can be deployed to
a cloud VM. This is a different axis — you could, for example, develop
from a Mac while deploying Vault to an AWS Linux instance.

| Cloud | Status | Notes |
|---|---|---|
| **AWS (EC2)** | ✅ Tested | Full walkthrough in `docs/AWS_DEPLOYMENT.md`, including the security group configuration, the same bind-mount permission fix (verified to reproduce on a fresh EC2 instance and confirmed fixed), and the manual-unseal-after-reboot limitation. |
| **Azure / GCP / other clouds** | ⚠️ Pattern transfers, untested | The underlying setup — a Docker container running Vault with a bind-mounted data volume — is cloud-agnostic by design, which is the whole premise of using Vault over a cloud-proprietary secrets service (see the comparison table above). The general approach (provision a VM, install Docker, clone, fix bind-mount permissions, run `init.sh`) should transfer directly. What's **not** done yet is writing out the cloud-specific provisioning steps (security group equivalents, VM sizing, IAM/access-control specifics) for any provider besides AWS. If you deploy this to Azure or GCP, the Docker-level steps from `docs/AWS_DEPLOYMENT.md` should apply almost verbatim from Step 4 onward (Install Docker) — only Steps 1–3 (VM provisioning and network/firewall rules) would need provider-specific instructions. |

### Summary

**Confidently claimed:** Linux local dev, AWS EC2 deployment — both
tested through a full fresh-environment verification pass, including bugs
found and fixed along the way.

**Attempted, inconclusive:** macOS local dev — a CI verification attempt
was made and is documented in `.github/workflows/test.yml`
(`test-macos`, marked `continue-on-error: true` so it doesn't block
merges), but it couldn't get past a GitHub Actions runner limitation
unrelated to this project. Real-hardware testing is still needed.

**Reasonably expected, not yet verified:** Azure/GCP deployment — same
underlying technology (Docker, bind mounts), no reason to expect
fundamentally different behavior, but not run and confirmed.

**Needs a different setup, not just an adjustment:** Windows local dev
without WSL2 — the script execution model itself doesn't match native
Windows.

If you test this on macOS (real hardware), Windows/WSL2, or another cloud
provider, contributions documenting what you found (working as-is, needed
a tweak, or hit a new issue) are welcome — see Contributing.

---

## Testing

Install dev dependencies first:

```bash
pip install -r requirements-dev.txt
```

**Against the quickstart stack** (simplest — uses credentials already in
`.vault-init.json`):

```bash
# Vault must be running and initialized (done during quickstart)
pytest tests/ -v
```

**Against a fresh test stack** (replicates what CI does):

```bash
docker compose -f docker-compose.yml -f docker-compose.test.yml up vault -d
bash scripts/init.sh
docker compose -f docker-compose.yml -f docker-compose.test.yml up consumer-app -d
pytest tests/ -v
docker compose -f docker-compose.yml -f docker-compose.test.yml down -v
```

The suite covers: AppRole login success/failure, secret fetch for all
five secret shapes, and — critically — a leakage test that captures all
stdout/stderr/HTTP response output during a full startup + `/status` call
and asserts none of the five demo secret values ever appear anywhere in it.

---

## License

[MIT](LICENSE) — free to use, modify, and distribute.

---

*Built by [Igal](https://github.com/igalhub) as a hands-on exploration of
self-hosted secrets management.*
