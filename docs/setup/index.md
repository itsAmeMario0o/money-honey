---
layout: default
title: Setup guides
---

# 🛠️ Setup guides

Step-by-step walkthroughs for provisioning and operating Money Honey. Run them roughly in order.

| Guide | When you need it |
|---|---|
| [Prerequisites](prerequisites.html) | Before anything else: Azure CLI, Terraform, kubectl, Helm versions, login. |
| [Terraform](terraform.html) | Provision the Azure stack: AKS, VNet, Key Vault, Splunk VM, Tetragon Helm release. |
| [Splunk](splunk.html) | Install Splunk Enterprise Free on the VM, configure HEC, populate the HEC token in Key Vault. |
| [Key Vault secrets](kv-secrets.html) | Populate Anthropic + Cloudflare secrets that you must supply. |
| [Cloudflare Tunnel](cloudflare-tunnel.html) | Phase 2: wire the public edge (Layer 8). Tunnel tokens, Public Hostname, Access policies. |
| [Azure SP for CI](azure-sp-for-ci.html) | One-time setup of the federated Service Principal that GitHub Actions uses to deploy to AKS. |

For day-2 operations (rotating a secret, recovering Splunk, rolling back a deploy), see the [runbooks](../runbooks/).
