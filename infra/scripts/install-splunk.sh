#!/usr/bin/env bash
# install-splunk.sh — one-shot install of Splunk Enterprise Free on the Ubuntu VM.
#
# Runs locally. SSHes into the VM and installs Splunk non-interactively.
# Idempotent: if Splunk is already installed, the script exits cleanly.
#
# Required env vars:
#   VM_IP                 — public IP of the Splunk VM (from terraform output)
#   SPLUNK_ADMIN_PASSWORD — strong password for the Splunk admin account
#
# Optional env vars:
#   CLOUDFLARED_TOKEN     — Cloudflare Tunnel connector token for the
#                           money-honey-splunk tunnel. When set, cloudflared
#                           is installed + enabled. When not set, the step
#                           is skipped (you can re-run later to add it).
#   KEY_FILE       (default: ../private_key/splunk.pem)
#   VM_USER        (default: azureuser)
#   SPLUNK_VERSION (default: 9.3.2)
#   SPLUNK_BUILD   (default: d8bb32809498)

set -euo pipefail

KEY_FILE=${KEY_FILE:-"$(dirname "$0")/../private_key/splunk.pem"}
VM_USER=${VM_USER:-azureuser}
VM_IP=${VM_IP:?set VM_IP (run: terraform output -raw splunk_vm_public_ip)}
PASSWORD=${SPLUNK_ADMIN_PASSWORD:?set SPLUNK_ADMIN_PASSWORD to a strong password}
# CLOUDFLARED_TOKEN is optional — if unset, the cloudflared install step
# is skipped and the VM stays on its public-IP SSH path.

SPLUNK_VERSION=${SPLUNK_VERSION:-9.3.2}
SPLUNK_BUILD=${SPLUNK_BUILD:-d8bb32809498}
DEB_URL="https://download.splunk.com/products/splunk/releases/${SPLUNK_VERSION}/linux/splunk-${SPLUNK_VERSION}-${SPLUNK_BUILD}-linux-2.6-amd64.deb"

if [[ ! -f "$KEY_FILE" ]]; then
  echo "❌ Private key not found at: $KEY_FILE"
  echo "   Recover it with: terraform output -raw splunk_ssh_private_key > '$KEY_FILE' && chmod 600 '$KEY_FILE'"
  exit 1
fi

echo "→  Installing Splunk ${SPLUNK_VERSION} on ${VM_USER}@${VM_IP}..."

ssh -i "$KEY_FILE" -o StrictHostKeyChecking=accept-new "${VM_USER}@${VM_IP}" bash <<REMOTE_SCRIPT
set -euo pipefail

if [[ -x /opt/splunk/bin/splunk ]]; then
  echo "✔  Splunk already installed at /opt/splunk — skipping download."
else
  echo "→  Downloading Splunk package..."
  sudo apt-get update -qq
  sudo apt-get install -y -qq wget
  wget -qO /tmp/splunk.deb "${DEB_URL}"
  echo "→  Installing .deb..."
  sudo dpkg -i /tmp/splunk.deb
  rm -f /tmp/splunk.deb
fi

if ! sudo /opt/splunk/bin/splunk status >/dev/null 2>&1; then
  echo "→  Starting Splunk with seeded admin password..."
  sudo /opt/splunk/bin/splunk start \
    --accept-license --answer-yes --no-prompt \
    --seed-passwd "${PASSWORD}"
fi

echo "→  Ensuring boot-start enabled..."
sudo /opt/splunk/bin/splunk enable boot-start -user splunk -systemd-managed 1 || true

echo "→  Enabling HTTP Event Collector (HEC)..."
sudo /opt/splunk/bin/splunk http-event-collector enable \
  -auth "admin:${PASSWORD}" \
  -uri https://127.0.0.1:8089 || true

# --- Cloudflare Tunnel (Layer 8) ---
# Only installed if a CLOUDFLARED_TOKEN was supplied. Without the
# token we leave the VM on its public-IP SSH path and defer the
# tunnel setup to a later run.
if [ -n "${CLOUDFLARED_TOKEN:-}" ]; then
  if systemctl is-active --quiet cloudflared 2>/dev/null; then
    echo "✔  cloudflared already running — skipping install."
  else
    echo "→  Installing cloudflared (Cloudflare Tunnel connector)..."
    curl -sSL -o /tmp/cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
    sudo dpkg -i /tmp/cloudflared.deb
    rm -f /tmp/cloudflared.deb
    sudo cloudflared service install "${CLOUDFLARED_TOKEN}"
  fi
  sudo systemctl enable --now cloudflared
else
  echo "⏭  CLOUDFLARED_TOKEN not set — skipping cloudflared install. Re-run the script later with the token exported to add the tunnel."
fi

echo "✅ Splunk + cloudflared ready on this VM."
REMOTE_SCRIPT

echo ""
echo "🎉 Local (private-IP) Splunk UI reachable from the VM only:"
echo "   http://<private-ip>:8000   (admin-only; not exposed publicly)"
echo ""
echo "🔐 Public access lives behind the Cloudflare Tunnel:"
echo "   Check the Zero Trust dashboard → Networks → Tunnels → money-honey-splunk"
echo "   Once HEALTHY, configure the Public Hostname (or Access Self-Hosted"
echo "   Application) to point at http://localhost:8000."
echo ""
echo "⚠️  Next step: in Splunk UI, create a HEC token for the AKS Fluent Bit"
echo "   pods and store it in Key Vault as 'splunk-hec-token'."
