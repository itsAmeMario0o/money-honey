---
layout: default
title: Cost
---

# 💰 Monthly cost

This is a demo project. The numbers below are **estimates** for East US pricing as of early 2026; your bill may vary slightly with discounts, reservations, or egress charges.

## 🟢 Running (cluster up, VM up)

| Component | SKU | Monthly |
|---|---|---|
| AKS control plane | Free tier | $0 |
| AKS workers (3×) | `Standard_B2s` | ~$90 |
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
| **Total** | | **~$170–175/mo** |

## 🟡 Paused between demos

Stop AKS with `az aks stop -g money-honey-rg -n money-honey-aks`. Disks + Key Vault + Splunk VM still cost, but the nodes don't.

| Component | Still costs | Stops costing |
|---|---|---|
| AKS control plane | — | — |
| AKS workers | — | ✅ |
| AKS node disks | ~$7 | — |
| Splunk VM | ~$61 | — (use `az vm deallocate` too) |
| Splunk disks | ~$5 | — |
| Everything else | <$5 | — |

Paused with both stopped: **~$20/mo**.

## 🔴 If Cilium were non-managed, or we used ACNS

Both are explicitly avoided in v1 per CLAUDE.md Architecture Decisions. They would add:

- **ACNS**: ~$30/mo at our cluster size (gets us Hubble, FQDN filtering, L7 policy). Evaluate in v2 if we need FQDN allowlists for egress.
- **Isovalent Enterprise** (via Marketplace): adds ~$100/mo for "everything in open-source Cilium plus enterprise features." Skipped for v1.

## 💡 Cost-saving tips

1. **Use `az aks stop`** between demos. Saves ~$90/mo on nodes. 2-minute re-start when you need the cluster again.
2. **Drop the Splunk VM to `Standard_B2s`** (2 vCPU/4 GB instead of 4/8). Splunk Enterprise Free is capped at 500 MB/day ingest; a B2s can handle that load. Saves ~$30/mo.
3. **Delete the Splunk public IP** once Cloudflare Tunnel is live for SSH too. Saves $3.60/mo. (Bootstrap problem: you need SSH to install cloudflared first.)
4. **Use spot instances** for the AKS node pool. Spot pricing on `Standard_B2s` is often $30/mo for the 3 nodes (65–80% discount) — but cluster nodes can be reclaimed, so spot isn't ideal for a "always reachable for demos" use case.

## Anthropic API spend

With Haiku 4.5 at current pricing:
- Input: $1.00 / 1M tokens
- Output: $5.00 / 1M tokens

A typical Money Honey turn uses ~2,500 input tokens (system prompt + 4 RAG chunks + user message) and ~250 output tokens. That's roughly **$0.00375 per turn**.

- 100 demo conversations × 5 turns each = 500 turns → **$1.88**
- Daily internal test during development = ~20 turns/day → $0.08/day → ~$2.40/mo

The $20 prepaid Anthropic credit lasts months at this usage rate.
