---
layout: default
title: Populating Key Vault Secrets
---

# 🗝️ Populating Key Vault secrets

Terraform creates four secret shells in `mh-kv-w8fxwb`. You set the real values manually. They never live in code, CI, or Terraform state.

## Prerequisites

- You are `az login`'d and scoped to the right subscription
- You have `Set` permission on the vault. The Terraform `operator` access policy granted this to whoever ran the apply.
- For each secret, you have the real value in hand (password manager ideally)

## The four secrets

| Secret | When to set | Where the value comes from |
|---|---|---|
| `anthropic-api-key` | Before app deploy | https://console.anthropic.com/, API Keys |
| `splunk-hec-token` | After Splunk install | Splunk UI, Settings, Data Inputs, HTTP Event Collector, token you created |
| `cloudflare-tunnel-splunk-token` | Before running cloudflared on the Splunk VM | Cloudflare Zero Trust, Networks, Tunnels, `money-honey-splunk`, token |
| `cloudflare-tunnel-chatbot-token` | Before deploying the cloudflared pod | Cloudflare Zero Trust, Networks, Tunnels, `money-honey-chatbot`, token |

## Commands

### Anthropic API key

```bash
az keyvault secret set \
  --vault-name mh-kv-w8fxwb \
  --name anthropic-api-key \
  --value 'sk-ant-api03-...your-key-here...'
```

### Splunk HEC token

After Splunk is installed and you've created an HEC token in the UI:

```bash
az keyvault secret set \
  --vault-name mh-kv-w8fxwb \
  --name splunk-hec-token \
  --value 'your-hec-token-uuid-here'
```

### Cloudflare tunnel tokens (when you're ready)

```bash
az keyvault secret set \
  --vault-name mh-kv-w8fxwb \
  --name cloudflare-tunnel-splunk-token \
  --value 'eyJhIjoi...'

az keyvault secret set \
  --vault-name mh-kv-w8fxwb \
  --name cloudflare-tunnel-chatbot-token \
  --value 'eyJhIjoi...'
```

## Verify secrets are populated (without exposing values)

```bash
# List secret names + versions (no values in the listing)
az keyvault secret list --vault-name mh-kv-w8fxwb --query "[].{name:name, enabled:attributes.enabled, updated:attributes.updated}" -o table
```

You should see `enabled: true` and a recent `updated` timestamp on the ones you set.

## Side effects of setting a secret

Terraform's `azurerm_key_vault_secret` resources use `lifecycle { ignore_changes = [value, version] }`, so your manual `az keyvault secret set` creates a new version and Terraform does not try to revert it on the next apply. Safe to set and re-set freely.

Fluent Bit, OTel Collector, FastAPI, and cloudflared pods mount these secrets via the CSI driver. New values propagate within ~5 minutes (`secret_rotation_interval` on the AKS add-on). For an immediate refresh: `kubectl -n money-honey rollout restart deploy/<name>`.

## Audit trail

Every `az keyvault secret set` writes to the vault's activity log. View from Azure Portal → Key Vault → `mh-kv-w8fxwb` → Monitoring → Activity log.
