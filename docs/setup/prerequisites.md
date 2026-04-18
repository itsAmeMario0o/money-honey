---
layout: default
title: Prerequisites
---

# ✅ Prerequisites

Tools needed on your machine (macOS tested; Linux works the same; Windows, use WSL2).

## Required

| Tool | Minimum version | Install (macOS) |
|---|---|---|
| Azure CLI | 2.60 | `brew install azure-cli` |
| Terraform | 1.5.0 | `brew install terraform` (or tfenv for version pinning) |
| kubectl | 1.30 | Comes with `az aks install-cli`; or `brew install kubectl` |
| Cilium CLI (optional, for connectivity tests) | 0.19 | `brew install cilium-cli` |
| pre-commit | 4.x | `brew install pre-commit` |
| Git | 2.40 | Built in on macOS; `brew install git` if you want latest |

## After installing the tools

```bash
# Log into Azure and set your subscription
az login
az account set --subscription <your-subscription-id>

# Clone the repo + install the pre-commit hook
git clone https://github.com/itsAmeMario0o/money-honey.git
cd money-honey
pre-commit install
```

## Permissions

Your Azure account needs at minimum:

- Contributor on the subscription (or on the target resource group if you scope it tighter).
- Storage Blob Data Contributor on the Terraform state storage account. The `terraform-bootstrap` module grants this automatically on first apply.

## Optional but recommended

| Tool | Why |
|---|---|
| `gh` (GitHub CLI) | `brew install gh`. Handy for inspecting workflow runs from the terminal. |
| `jq` | `brew install jq`. Parses Azure CLI JSON output in one-liners. |
| A Webex bot | Build at https://developer.webex.com. Optional CI notifications. |
| An Anthropic account | https://console.anthropic.com. For the Claude API key that powers the chatbot. |

## Order of operations for a fresh clone

1. Read [`CLAUDE.md`](https://github.com/itsAmeMario0o/money-honey/blob/main/CLAUDE.md) for project rules and architecture.
2. Read [`ARCHITECTURE.md`](https://github.com/itsAmeMario0o/money-honey/blob/main/ARCHITECTURE.md) for the three-domain framework deep-dive.
3. Read [`STATUS.md`](https://github.com/itsAmeMario0o/money-honey/blob/main/STATUS.md) for the current state of play.
4. Follow [`docs/setup/terraform.md`](terraform.html) to provision Azure resources
5. Follow [`docs/setup/splunk.md`](splunk.html) to install Splunk on the VM
6. Follow [`docs/setup/kv-secrets.md`](kv-secrets.html) to populate Key Vault
7. Follow [`docs/setup/azure-sp-for-ci.md`](azure-sp-for-ci.html) to wire up CI/CD
