# Vault Secrets Demo

A standalone, cloud-agnostic secrets management demo built on HashiCorp
Vault. Proves the AppRole authentication pattern end-to-end with a mock
consumer app — deployable locally via Docker, with a documented path to
AWS EC2.

![Vault Secrets Demo screenshot](docs/screenshot.png)

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

docker compose up -d
bash scripts/init.sh
```

`init.sh` initializes Vault, unseals it, enables the KV v2 engine, sets
up the AppRole auth method and policy, and seeds the five demo secrets.
It writes the unseal keys and root token to a **gitignored** local file —
back this up if you want to manage Vault manually later; losing it means
you'll need to start over with a fresh volume.

Verify it worked:

```bash
curl http://localhost:8000/status
```

You should see all five secrets reporting `"ok"`.

### Restarting after a stop

Vault re-seals on every restart (manual unseal is intentional — see
Design decisions above). To bring it back up:

```bash
docker compose up -d
bash scripts/unseal.sh
```

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

## Testing

```bash
docker compose -f docker-compose.yml -f docker-compose.test.yml up -d
pytest tests/ -v
```

The suite covers: AppRole login success/failure, secret fetch for all
five secret shapes, and — critically — a leakage test that captures all
stdout/stderr/HTTP response output during a full run and asserts none of
the five real secret values ever appear anywhere in it.

---

## License

[MIT](LICENSE) — free to use, modify, and distribute.

---

*Built by [Igal](https://github.com/igalhub) as a hands-on exploration of
self-hosted secrets management.*
