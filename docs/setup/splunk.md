---
layout: default
title: Splunk Install (as a Debian package on the VM)
---

# 🪵 Splunk install: Debian package on the dedicated VM

Splunk Enterprise Free runs as a `.deb` package on the Ubuntu 22.04 VM, not in a container. `infra/scripts/install-splunk.sh` drives the install over SSH and is idempotent (safe to re-run).

## What gets installed

- Splunk Enterprise Free 9.3.2 (pinned in the script; change `SPLUNK_VERSION` / `SPLUNK_BUILD` env vars to bump)
- Systemd service `splunk.service` with boot-start enabled
- HTTP Event Collector (HEC) enabled and listening on port `8088`
- Optional: `cloudflared` systemd service if `CLOUDFLARED_TOKEN` is set

## Prerequisites

- `terraform apply` has succeeded (the VM exists and has a public IP)
- The generated SSH key is at `infra/private_key/splunk.pem` (recovery: `terraform -chdir=infra/terraform output -raw splunk_ssh_private_key > infra/private_key/splunk.pem && chmod 600 infra/private_key/splunk.pem`)
- Your network has outbound internet (the script `wget`s the Splunk deb from download.splunk.com)

## Run the install

```bash
cd /Users/mariorui/Library/CloudStorage/OneDrive-MarioJRuiz/Projects/money-honey

# Grab the VM's public IP from terraform output
VM_IP=$(terraform -chdir=infra/terraform output -raw splunk_vm_public_ip)
echo "VM_IP=$VM_IP"

# Pick a strong admin password. Save it in a password manager.
# Splunk's rules: ≥ 8 chars, mix of upper/lower/digit/symbol.
export SPLUNK_ADMIN_PASSWORD='YourStrongPasswordHere!'

# Run the install (CLOUDFLARED_TOKEN is optional; skip for now).
VM_IP=$VM_IP \
  SPLUNK_ADMIN_PASSWORD="$SPLUNK_ADMIN_PASSWORD" \
  ./infra/scripts/install-splunk.sh
```

The script prints progress markers and ends with the UI URL + the cloudflared skip notice.

## Log into the Splunk UI

From your browser:

```
http://<VM_IP>:8000
```

Accept the self-signed cert warning (Splunk Web runs HTTPS on port 8000 by default; check the exact protocol from the install output). Log in with username `admin` and the password you set.

## Create an HEC token for Fluent Bit + OTel

Fluent Bit and OTel Collector both post events to Splunk's HTTP Event Collector. You need a token.

### Option A: one-liner (recommended)

Creates the token via Splunk CLI over SSH, extracts the UUID, writes it to Key Vault. Requires `SPLUNK_ADMIN_PASSWORD` already exported in your shell:

```zsh
HEC_TOKEN=$(ssh -i infra/private_key/splunk.pem -o StrictHostKeyChecking=no \
    azureuser@$(terraform -chdir=infra/terraform output -raw splunk_vm_public_ip) \
    "sudo /opt/splunk/bin/splunk http-event-collector create \
       -name money-honey-aks \
       -description 'AKS Tetragon events' \
       -index main \
       -sourcetype _json \
       -uri https://127.0.0.1:8089 \
       -auth admin:$SPLUNK_ADMIN_PASSWORD" \
  | grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}')

echo "HEC token: $HEC_TOKEN"

az keyvault secret set --vault-name mh-kv-w8fxwb --name splunk-hec-token --value "$HEC_TOKEN"
```

The `grep -oE` matches a bare UUID. That avoids storing the CLI's `token=<uuid>` prefix, which would break HEC auth headers.

### Option B: via the Splunk UI

1. Open via SSH port-forward: `ssh -i infra/private_key/splunk.pem -L 8000:localhost:8000 azureuser@<VM_IP>` then browse to http://localhost:8000
2. Settings → Data Inputs → HTTP Event Collector
3. Click New Token
4. Name: `money-honey-aks`
5. Source type: `_json`
6. Default index: `main` (or create `tetragon`)
7. Review + Submit, then copy the token (just the UUID, not any prefix)
8. Store it: `az keyvault secret set --vault-name mh-kv-w8fxwb --name splunk-hec-token --value '<uuid>'`

## Harden post-install (quick wins)

- In Settings, Server settings, General settings, enable TLS for Splunk Web (upload a cert or generate a local one). Optional if you are routing via Cloudflare Tunnel.
- Change the `admin` password if anyone else used the initial seed password.
- Disable the unused `main` index if you are routing everything to a dedicated `tetragon` index (saves the 500 MB/day budget).

## Troubleshooting

| Symptom | Fix |
|---|---|
| SSH hangs | NSG allows port 22 only from your current public IP. If your IP changed since `terraform apply`, re-run `terraform apply` to refresh the NSG rule. |
| `dpkg: error processing archive ...` | Rare. Run `sudo dpkg --configure -a` on the VM and retry. |
| Splunk does not start on boot | `sudo systemctl status splunk` and inspect. The script enables boot-start explicitly; a failure here usually means the VM is short on disk. |
| HEC returns `Server is busy` | Splunk is still initializing indexes. Wait 30-60 s after the first start. |

## Reference

- Script: [`infra/scripts/install-splunk.sh`](https://github.com/itsAmeMario0o/money-honey/blob/main/infra/scripts/install-splunk.sh)
- Splunk Enterprise docs: https://docs.splunk.com/Documentation/Splunk/latest/Installation/InstallonLinux
