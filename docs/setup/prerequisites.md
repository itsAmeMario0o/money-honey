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
| Container runtime | any | Colima recommended (`brew install colima docker`). Docker Desktop also works. |
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

## macOS ARM (Apple Silicon) build setup

AKS nodes run x86_64 (amd64). If your Mac has Apple Silicon (M1/M2/M3/M4), you need to build container images for the right architecture. Docker Desktop handles this automatically with `--platform linux/amd64`, but Colima requires a dedicated x86_64 VM.

### Colima setup for cross-architecture builds

```zsh
# Install Colima + Docker CLI + QEMU (for x86_64 emulation)
brew install colima docker qemu lima-additional-guestagents

# Start an x86_64 VM (not the default ARM one)
colima start --arch x86_64 --cpu 4 --memory 8

# Verify architecture
docker info | grep Architecture
# Expected: x86_64
```

If you already have a Colima VM running (ARM), delete it first:

```zsh
colima delete
colima start --arch x86_64 --cpu 4 --memory 8
```

### Building and pushing the backend image

```zsh
# Auth to GHCR (raw token, no quotes)
echo ghp_yourTokenHere | docker login ghcr.io -u itsAmeMario0o --password-stdin

# Build (--no-cache on first run to avoid ARM layer conflicts)
docker build --no-cache -t ghcr.io/itsamemario0o/money-honey-app:latest app/

# Push
docker push ghcr.io/itsamemario0o/money-honey-app:latest

# Restart pods to pull the new image
kubectl -n money-honey rollout restart deployment/fastapi
```

Build takes ~10-15 min under QEMU emulation. Subsequent builds are faster if the base layers are cached.

### Common errors

| Error | Cause | Fix |
|---|---|---|
| `exec format error` | Image built for ARM, running on x86_64 AKS | Rebuild with `colima start --arch x86_64` |
| `does not provide the specified platform` | Cached ARM layers from a previous build | Add `--no-cache` to the build command |
| `qemu-img not found` | QEMU not installed | `brew install qemu` |
| `lima-guestagent.Linux-x86_64` not found | Missing guest agent package | `brew install lima-additional-guestagents` |
| `architecture cannot be updated` | Existing Colima VM is ARM | `colima delete` then `colima start --arch x86_64` |
| Broken pipe on Docker socket | VM not fully started | `colima status` to check, then `colima start --arch x86_64 --cpu 4 --memory 8` |

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
