---
layout: default
title: Rotate a Key Vault secret
---

# 🔐 Rotate a Key Vault secret

Use this when a secret in `mh-kv-w8fxwb` needs to be replaced: suspected leak, scheduled rotation, or the upstream issuer (Anthropic, Cloudflare, Splunk HEC) gave you a new token.

The CSI Secret Store Driver does NOT auto-pick-up new versions by default. You must roll the consuming pods after writing the new secret.

## Symptom

- A token leaked or a vendor revoked the old one.
- A consuming pod (fastapi, fluent-bit, otel-collector, cloudflared) starts logging 401/403/auth-failed.
- Quarterly rotation cadence hit.

## Pre-checks

```zsh
# Confirm you're talking to the right Key Vault.
az keyvault show --name mh-kv-w8fxwb --query "id" -o tsv

# List current secrets and their enabled state.
az keyvault secret list --vault-name mh-kv-w8fxwb \
  --query "[].{name:name, enabled:attributes.enabled}" -o table

# Identify which workloads consume the secret you're rotating.
grep -rn '<secret-name>' k8s/secrets/
```

| Secret name | Consumed by | Namespace |
|---|---|---|
| `anthropic-api-key` | fastapi | money-honey |
| `splunk-hec-token` | fluent-bit, otel-collector | kube-system |
| `cloudflare-tunnel-splunk-token` | cloudflared on Splunk VM (systemd) | n/a |
| `cloudflare-tunnel-chatbot-token` | cloudflared in cluster | money-honey |

## Procedure

### 1. Write the new value as a NEW VERSION of the same secret

```zsh
read -s "NEW_VALUE?Paste the new secret value: "
echo
az keyvault secret set \
  --vault-name mh-kv-w8fxwb \
  --name <secret-name> \
  --value "$NEW_VALUE"
unset NEW_VALUE
```

The CSI driver references secrets by name (no version pin), so the next secret sync will pick the new latest version.

### 2. Force a CSI re-sync by rolling the consuming pods

The CSI sync interval is 2 minutes, but a pod restart triggers an immediate re-mount.

```zsh
# Pick the right rollout for the secret you rotated:
kubectl -n money-honey rollout restart deployment/fastapi          # anthropic-api-key
kubectl -n kube-system  rollout restart daemonset/fluent-bit       # splunk-hec-token (logs)
kubectl -n kube-system  rollout restart deployment/otel-collector  # splunk-hec-token (metrics)
kubectl -n money-honey  rollout restart deployment/cloudflared     # cloudflare-tunnel-chatbot-token

# For the Splunk-VM cloudflared (systemd, not k8s):
ssh azureuser@$SPLUNK_VM_IP 'sudo systemctl restart cloudflared'
```

### 3. Disable the OLD version (don't delete, so the audit trail is preserved)

```zsh
OLD_VERSION=$(az keyvault secret list-versions \
  --vault-name mh-kv-w8fxwb --name <secret-name> \
  --query "[?attributes.enabled].id" -o tsv | sed -n '2p')

az keyvault secret set-attributes \
  --vault-name mh-kv-w8fxwb \
  --name <secret-name> \
  --version $(basename "$OLD_VERSION") \
  --enabled false
```

## Verification

```zsh
# Pod has the latest version mounted (compare timestamps).
kubectl -n <ns> exec deploy/<consumer> -- stat /mnt/secrets/<secret-name>

# For app secrets, hit the path that exercises the secret.
# Example for fastapi + Anthropic:
kubectl -n money-honey port-forward svc/caddy 8080:80 &
curl -sS -X POST http://localhost:8080/api/chat \
  -H 'content-type: application/json' \
  -d '{"message":"hi"}' | jq '.response' | head -c 200

# For Splunk HEC, look for fresh events in Splunk Search:
#   index=tetragon earliest=-5m | head 5
```

If the consumer is still erroring after rollout completes (give it 60s):

- Check the pod was actually restarted: `kubectl -n <ns> get pods -l app=<name>` (AGE column).
- `kubectl -n <ns> describe pod <pod>` and look for CSI `MountVolume.SetUp failed` events.
- Check Key Vault firewall isn't blocking: `az keyvault network-rule list --name mh-kv-w8fxwb`.

## Rollback

Re-enable the old version, write it as a new "current" version, restart consumers.

```zsh
az keyvault secret set-attributes --vault-name mh-kv-w8fxwb \
  --name <secret-name> --version $(basename "$OLD_VERSION") --enabled true

OLD_VALUE=$(az keyvault secret show --vault-name mh-kv-w8fxwb \
  --name <secret-name> --version $(basename "$OLD_VERSION") --query value -o tsv)

az keyvault secret set --vault-name mh-kv-w8fxwb \
  --name <secret-name> --value "$OLD_VALUE"
unset OLD_VALUE

kubectl -n <ns> rollout restart <kind>/<consumer>
```
