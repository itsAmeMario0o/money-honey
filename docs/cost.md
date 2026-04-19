---
layout: default
title: Cost
---

# 💰 Monthly cost

Demo project. The numbers below are East US estimates as of early 2026. Your bill may shift slightly with discounts, reservations, or egress charges.

## 🟢 Running (cluster up, VM up)

| Component | SKU | Monthly |
|---|---|---|
| AKS control plane | Free tier | $0 |
| AKS workers (3×) | `Standard_D2s_v3` | ~$87 |
| AKS node OS disks (3× 32 GB) | Standard SSD | ~$7 |
| Splunk VM | `Standard_B2ms` | ~$61 |
| Splunk data disk (64 GB) | Standard SSD | ~$5 |
| Splunk public IP | Static | $3.60 |
| Key Vault | Standard | <$1 |
| Storage (Terraform state) | LRS, <1 GiB | <$1 |
| Claude API | $20 prepaid (Haiku 4.5) | ~$3–5 |
| Embeddings | Local `all-MiniLM-L6-v2` | $0 |
| GHCR (container images) | Public repo | $0 |
| GitHub Pages (docs) | Public repo | $0 |
| Cloudflare Zero Trust | Free plan, ≤50 users | $0 |
| Azure Files (knowledge-base + hf-cache) | Standard LRS, ~108 MB | <$0.01 |
| **Total** | | **~$165–170/mo** |

## 🟡 Paused between demos

Run `az aks stop -g money-honey-rg -n money-honey-aks`. Disks, Key Vault, and the Splunk VM still cost money. The nodes don't.

| Component | Still costs | Stops costing |
|---|---|---|
| AKS control plane | — | — |
| AKS workers | — | ✅ |
| AKS node disks | ~$7 | — |
| Splunk VM | ~$61 | — (use `az vm deallocate` too) |
| Splunk disks | ~$5 | — |
| Everything else | <$5 | — |

Paused with both stopped: ~$20/mo.

## 🔴 If Cilium were non-managed, or ACNS were on

Both are avoided in v1 (see CLAUDE.md Architecture Decisions). They would add:

- ACNS: ~$30/mo at this cluster size. Gets you Hubble, FQDN filtering, L7 policy. Evaluate in v2 if FQDN egress allowlists are needed.
- Isovalent Enterprise (via Marketplace): ~$100/mo for enterprise Cilium features. Skipped for v1.

## 💡 Cost-saving tips

1. Run `az aks stop` between demos. Saves ~$87/mo on nodes. Two-minute restart when you need the cluster again.
2. Drop the Splunk VM to `Standard_B2s` (2 vCPU / 4 GB instead of 4 / 8). Splunk Enterprise Free caps at 500 MB/day ingest, and a B2s handles that. Saves ~$30/mo.
3. Delete the Splunk public IP once Cloudflare Tunnel is live for SSH too. Saves $3.60/mo. (You need SSH to install cloudflared first, so the IP has to exist during bootstrap.)
4. Use spot instances for the AKS node pool. Spot pricing on `Standard_D2s_v3` can cut node costs by 65-80%, but nodes can be reclaimed. Not great for a demo that needs to stay reachable.

## Anthropic API spend

Haiku 4.5 pricing:
- Input: $1.00 / 1M tokens
- Output: $5.00 / 1M tokens

A typical turn uses ~2,500 input tokens (system prompt + 4 RAG chunks + user message) and ~250 output tokens. About $0.00375 per turn.

- 100 demo conversations x 5 turns = 500 turns = $1.88
- Daily dev testing at ~20 turns/day = $0.08/day = ~$2.40/mo

The $20 prepaid Anthropic credit lasts months at this rate.
