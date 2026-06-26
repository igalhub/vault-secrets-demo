# Home Lab Deployment (Proxmox + Ubuntu Server VM)

This guide covers deploying vault-secrets-demo on a Proxmox home lab
running Ubuntu Server 24.04 in a VM — tested on a Beelink SER mini PC
with Proxmox VE 9.2.3.

## Environment

| Component | Version |
|---|---|
| Hypervisor | Proxmox VE 9.2.3 |
| OS | Ubuntu Server 24.04.3 LTS |
| Docker | 29.6.0 |

## Prerequisites

- Ubuntu Server VM with Docker installed
- Static IP configured (e.g. `192.168.1.6`)
- SSH access from your main machine

## Deployment

```bash
git clone git@github.com:igalhub/vault-secrets-demo.git
cd vault-secrets-demo

# Pre-create vault/data with correct ownership (required — see Troubleshooting in README)
mkdir -p vault/data
sudo chown 100 vault/data

# Step 1: start Vault
docker compose up vault -d

# Step 2: initialize Vault, seed secrets, write .env.consumer
bash scripts/init.sh

# Step 3: start consumer app
docker compose up consumer-app -d
```

## Verify

```bash
curl http://localhost:8000/status
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

## Access from your main machine

Since the VM has a static IP, access the consumer app from any machine
on your network:
`http://<VM_IP>:8000/status`
Replace `<VM_IP>` with your VM's static IP address.

## Notes

- No issues encountered on this environment — deploys cleanly following
  the standard quickstart
- The bind-mount permission fix (`sudo chown 100 vault/data`) is
  required on Ubuntu Server just as it is on desktop Linux
- Vault re-seals on every restart — run `bash scripts/unseal.sh` after
  any VM reboot before starting the consumer app

## Integration with expiry-watcher

This Vault instance serves as the backend for
[expiry-watcher](https://github.com/igalhub/expiry-watcher). Once
vault-secrets-demo is running, create a short-TTL AppRole for
expiry-watcher to monitor:

```bash
export VAULT_TOKEN=<root-token-from-.vault-init.json>
cd ~/expiry-watcher
bash scripts/vault_setup_test_role.sh
```

The script prints a `role_id` and `secret_id` — copy them into
`expiry-watcher/config/vault.yaml`. See expiry-watcher's
`docs/HOMELAB_DEPLOYMENT.md` for the next steps.

## Running alongside other projects

This project was tested running simultaneously with:
- **expiry-watcher** (port 8080)
- **docker-sentinel** (port 8081)
- **kube-sentinel** (Grafana port 30093, Prometheus port 31664)
- **Portainer** (port 9000)

No port conflicts. All containers are visible and manageable via
Portainer at `http://<VM_IP>:9000`.
