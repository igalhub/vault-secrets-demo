# AWS EC2 Deployment — Vault Secrets Demo

This walkthrough takes you from a blank AWS account to a running Vault
instance with the demo consumer app, accessible from your local machine.
It assumes familiarity with the AWS console and basic SSH — not prior
Vault experience.

---

## What you'll end up with

- A `t3.micro` EC2 instance (free tier eligible) running the two-container
  Docker Compose stack
- Vault listening on port 8200, consumer app on port 8000
- Both ports restricted to your IP address — not the open internet
- The same `scripts/init.sh` quickstart flow as local dev, just run on
  the remote host

**Not covered here:** TLS termination, auto-unseal via AWS KMS, high
availability. Those are documented as production gaps in `ARCHITECTURE.md`.

---

## Prerequisites

- An AWS account with permission to launch EC2 instances and manage
  security groups (an admin IAM user or the root account for a personal
  demo account is fine)
- An EC2 key pair for SSH access — create one in the console under
  **EC2 → Key Pairs** if you don't have one yet; download the `.pem` file
- Your current public IP address (visit `https://ifconfig.me` or similar)
- Docker and Git on your local machine (only used to verify connectivity;
  all build work happens on the EC2 instance)

---

## Step 1 — Launch the EC2 instance

In the AWS console, go to **EC2 → Instances → Launch instances**.

| Field | Value |
|---|---|
| Name | `vault-secrets-demo` |
| AMI | Ubuntu Server 24.04 LTS (the default "Quick Start" option) |
| Instance type | `t3.micro` (free tier eligible) |
| Key pair | Select your existing key pair |
| Storage | 8 GiB gp3 (default) — Vault's file storage is tiny |

Under **Network settings**, click **Edit**. You'll configure the security
group in the next step. For now, leave the VPC and subnet on their defaults
and **do not enable** "Auto-assign public IP" — check that it's enabled
(AWS enables it by default for default-VPC subnets).

---

## Step 2 — Configure the security group

**This is the most important step for security.** This demo runs without
TLS — acceptable only while both ports are restricted to your own IP. Do
not set any rule to `0.0.0.0/0` (anywhere); that would expose Vault
without encryption to the public internet.

Create a new security group with these inbound rules:

| Type | Protocol | Port | Source | Why |
|---|---|---|---|---|
| SSH | TCP | 22 | My IP | SSH access for setup and management |
| Custom TCP | TCP | 8200 | My IP | Vault API |
| Custom TCP | TCP | 8000 | My IP | Consumer app `/status` endpoint |

**"My IP"** is a shortcut in the AWS console that fills in your current
public IP automatically. If your ISP gives you a dynamic IP, you'll need
to update these rules when it changes.

> **Why not just use SSH tunneling?** You can — if you prefer not to
> expose ports 8200 and 8000 at all, set SSH to My IP only, then access
> Vault and the consumer app via SSH port-forward:
> `ssh -L 8200:localhost:8200 -L 8000:localhost:8000 ubuntu@<instance-ip>`
> Then browse or curl `localhost:8200` and `localhost:8000` locally.

After configuring the security group, click **Launch instance**.

---

## Step 3 — Connect to the instance

Find the public IP of your new instance on the EC2 Instances page. Then:

```bash
# Adjust the key path and IP to match yours
ssh -i ~/.ssh/your-key.pem ubuntu@<PUBLIC_IP>
```

If you get a `Permission denied (publickey)` error, confirm:
- The key file permissions are `600`: `chmod 600 ~/.ssh/your-key.pem`
- You're using the correct username (`ubuntu` for Ubuntu AMIs)
- The security group inbound rule for port 22 matches your current IP

---

## Step 4 — Install Docker

Run these commands on the EC2 instance:

```bash
# Install Docker Engine (includes the compose plugin)
curl -fsSL https://get.docker.com | sudo sh

# Add your user to the docker group so you can run docker without sudo
sudo usermod -aG docker ubuntu

# Apply the group change without logging out
newgrp docker
```

Verify Docker is working:

```bash
docker run --rm hello-world
```

---

## Step 5 — Clone the repo and start Vault

```bash
git clone https://github.com/igalhub/vault-secrets-demo.git
cd vault-secrets-demo

# Pre-create vault/data/ with ownership that Vault's container user can write to.
# (See troubleshooting note below for why this is required.)
mkdir -p vault/data
sudo chown 100 vault/data

# Start Vault first (.env.consumer doesn't exist yet)
docker compose up vault -d

# Wait for Vault to be healthy (sealed/uninitialized — expected)
docker compose ps
```

The healthcheck accepts the sealed state (exit 2 from `vault status`) as
healthy, so `docker compose ps` should show the vault service as `healthy`
within about 10 seconds.

### Troubleshooting: `mkdir /vault/data/core: permission denied`

If you see this error during Step 6 (`scripts/init.sh`), the cause is a
container UID mismatch on the bind mount.

**What happens:** the Vault image's entrypoint script uses `su-exec` to
run the Vault server process as the internal `vault` user (UID 100, GID
1000) rather than as root. On a fresh `git clone`, the `vault/data/`
directory doesn't exist (it's gitignored). When Docker Compose creates it
automatically on the host, it creates it as `root:root 755`. UID 100 is
not root and can't write to a root-owned directory, so the first write
(`vault operator init` creating `vault/data/core/`) fails with
`permission denied`.

**Fix:**

```bash
# Stop Vault if it's running
docker compose down

# Set ownership to Vault's container UID
sudo chown 100 vault/data

# Restart
docker compose up vault -d
bash scripts/init.sh
```

To verify that 100 is the right UID for the image version you're using:

```bash
docker run --rm --entrypoint sh hashicorp/vault:1.17 \
  -c 'grep vault /etc/passwd'
# Expected: vault:x:100:1000:...
```

> **Note:** The CI fix for the same issue is `chmod 777 vault/data`. That
> works on ephemeral runners where the machine is discarded after the job,
> but on a persistent host `chown 100` is preferable — it grants write
> access only to Vault's own UID, not to every process on the machine.

---

## Step 6 — Initialize and seed Vault

```bash
bash scripts/init.sh
```

This does the same thing it does locally:
- Initializes Vault (generates unseal key + root token)
- Unseals Vault
- Enables KV v2 at `secret/`
- Creates the `demo-app-policy` (read-only, scoped to `secret/data/demo-*`)
- Enables AppRole auth and creates the `demo-app` role
- Seeds the five demo secrets
- Writes credentials to `.vault-init.json` and `.env.consumer`
  (both gitignored)

```bash
# Start the consumer app now that .env.consumer exists
docker compose up consumer-app -d
```

---

## Step 7 — Verify

From the EC2 instance:

```bash
curl http://localhost:8000/status
```

From your local machine (requires port 8000 open in the security group):

```bash
curl http://<PUBLIC_IP>:8000/status
```

Expected output:

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

You can also check Vault directly:

```bash
curl http://<PUBLIC_IP>:8200/v1/sys/health
```

---

## Manual unseal after reboot

**This is the main operational limitation of this demo setup.**

Vault re-seals on every restart. When the EC2 instance reboots — for
patch updates, spot interruptions, or any other reason — Vault comes back
up sealed, and the consumer app's `/status` endpoint will show
`"vault_auth": "failed: VaultAuthError"`.

To recover:

```bash
# SSH into the instance
ssh -i ~/.ssh/your-key.pem ubuntu@<PUBLIC_IP>
cd vault-secrets-demo

# Re-unseal Vault (reads the unseal key from .vault-init.json)
bash scripts/unseal.sh

# Restart the consumer app to re-authenticate
docker compose restart consumer-app
```

**How to detect a sealed Vault:**

```bash
curl http://localhost:8200/v1/sys/health
# Returns HTTP 503 with "sealed": true when sealed
# Returns HTTP 200 with "sealed": false when healthy
```

**Production fix:** auto-unseal via AWS KMS eliminates the manual step.
The Vault config would add an `seal "awskms"` stanza pointing to a KMS
key; Vault then unseals itself on startup without human intervention.
That's out of scope for this demo but is the standard approach for
long-running instances.

---

## TLS requirement

This demo runs without TLS — the Vault listener has `tls_disable = 1` in
`vault/config/vault-config.hcl`.

This is acceptable when:
- Both ports are restricted to your own IP in the security group (so
  traffic never crosses the open internet), **or**
- You access Vault via SSH tunneling (traffic is encrypted inside the
  SSH connection)

It is **not** acceptable if you open either port to `0.0.0.0/0`, or if
you're testing with real credentials.

**To add TLS**, replace the listener block in `vault-config.hcl` with:

```hcl
listener "tcp" {
  address       = "0.0.0.0:8200"
  tls_cert_file = "/vault/tls/vault.crt"
  tls_key_file  = "/vault/tls/vault.key"
}
```

Mount your certificate and key into the container via a `volumes` entry
in `docker-compose.yml`. A free certificate from Let's Encrypt (via
Certbot or Caddy) is the standard approach for a domain-backed instance.
A self-signed certificate is also possible but requires trusting the cert
on every client.

---

## Data persistence

Vault's storage lives at `~/vault-secrets-demo/vault/data/` on the EC2
instance — a bind mount from the container to the host filesystem.

**If you stop the instance (not terminate):** the EBS root volume is
preserved; Vault data survives; you'll need to unseal after restart.

**If you terminate the instance:** the EBS root volume is deleted by
default (check "Delete on termination" in the instance storage settings).
Vault data, `.vault-init.json`, and the unseal key are all gone.

To preserve data across instance replacement, either:
- Uncheck "Delete on termination" on the EBS volume before terminating,
  then re-mount it on the new instance
- Periodically back up `vault/data/` to S3:
  `aws s3 sync vault/data/ s3://your-bucket/vault-backup/`

---

## Cost

Vault Community Edition is free. The only cost is the EC2 instance:

| Instance type | On-demand hourly | ~Monthly |
|---|---|---|
| `t3.micro` | ~$0.0104/hr | ~$7.50 |
| `t3.nano` | ~$0.0052/hr | ~$3.75 |

`t3.micro` is free-tier eligible for the first 750 hours/month in new
accounts. `t3.nano` works fine for this demo (Vault is not CPU-intensive);
`t3.micro` gives a bit more headroom.

**Stop the instance when not in use** — a stopped instance doesn't accrue
compute charges (you still pay for the EBS volume, ~$0.08/GB-month, so
about $0.65/month for the default 8 GB volume).

---

## Teardown / cleanup

To stop the Docker stack (instance keeps running):

```bash
docker compose down
```

To remove Vault data and credential files and start fresh:

```bash
bash scripts/teardown.sh
```

To stop the EC2 instance (preserves EBS, no compute charges):
Go to **EC2 → Instances → select instance → Instance state → Stop**.

To terminate the EC2 instance (deletes EBS volume and all data):
Go to **EC2 → Instances → select instance → Instance state → Terminate**.
