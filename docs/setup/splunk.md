---
layout: default
title: Splunk Install (as a Debian package on the VM)
---

# 🪵 Splunk install — Debian package on the dedicated VM

Splunk Enterprise Free runs **as a `.deb` package** on the Ubuntu 22.04 VM — not in a container. Installation is driven by `infra/scripts/install-splunk.sh` over SSH; the script is idempotent (safe to re-run).

## What gets installed

- Splunk Enterprise Free 9.3.2 (pinned in the script — change `SPLUNK_VERSION`/`SPLUNK_BUILD` env vars to bump)
- Systemd service `splunk.service` with boot-start enabled
- HTTP Event Collector (HEC) enabled and listening on port `8088`
- Optional: `cloudflared` systemd service if `CLOUDFLARED_TOKEN` is set

## Prerequisites

- `terraform apply` has succeeded (the VM exists and has a public IP)
- The generated SSH key is at `infra/private_key/splunk.pem` (recovery: `terraform -chdir=infra/terraform output -raw splunk_ssh_private_key > infra/private_key/splunk.pem && chmod 600 infra/private_key/splunk.pem`)
- You're on a network with outbound internet (the script `wget`s the Splunk deb from download.splunk.com)

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

The script prints progress markers (`→`, `✔`, `✅`) and ends with the UI URL + the cloudflared skip notice.

## Log into the Splunk UI

From your browser:

```
http://<VM_IP>:8000
```

Accept the self-signed cert warning (Splunk Web runs HTTPS on port 8000 by default when installed this way; check the exact protocol from the install output). Log in with username `admin` and the password you set.

## Create an HEC token for Fluent Bit + OTel

Fluent Bit and OTel Collector both post events to Splunk's HTTP Event Collector. You need a token:

1. In Splunk UI → **Settings → Data Inputs → HTTP Event Collector**
2. Click **New Token**
3. Name: `money-honey-aks`
4. Source type: `_json` (our Tetragon events arrive as JSON)
5. Default index: `main` (or create a dedicated `tetragon` index)
6. **Review + Submit** — copy the token
7. Save it; you'll paste it into Key Vault next (`docs/setup/kv-secrets.md`)

## Harden post-install (quick wins)

- In **Settings → Server settings → General settings** → enable TLS for Splunk Web (upload a cert, or generate a local one). Optional if you're routing via Cloudflare Tunnel in the end.
- Change the `admin` user's password if anyone else used the initial seed password.
- Disable the unused `main` index if you're routing everything to a dedicated `tetragon` index (saves the 500 MB/day budget).

## Troubleshooting

| Symptom | Fix |
|---|---|
| SSH hangs | NSG allows port 22 only from your current public IP. If your IP changed since `terraform apply`, re-run `terraform apply` to refresh the NSG rule. |
| `dpkg: error processing archive ...` | Rare. Run `sudo dpkg --configure -a` on the VM and retry. |
| Splunk doesn't start on boot | `sudo systemctl status splunk` and inspect. The script enables boot-start explicitly; a failure here usually means the VM is short on disk. |
| HEC returns `Server is busy` | Splunk is still initializing indexes — wait 30–60 s after the first start. |

## Reference

- Script: [`infra/scripts/install-splunk.sh`](https://github.com/itsAmeMario0o/money-honey/blob/main/infra/scripts/install-splunk.sh)
- Splunk Enterprise docs: https://docs.splunk.com/Documentation/Splunk/latest/Installation/InstallonLinux
