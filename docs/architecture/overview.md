---
layout: default
title: Architecture Overview
---

# 🏛️ Architecture Overview

Money Honey is structured around three domains of security, each with its own independent controls. If one layer fails, the others still hold. No single compromise cascades.

This page is the summary. For the full narrative, read [`ARCHITECTURE.md`](https://github.com/itsAmeMario0o/money-honey/blob/main/ARCHITECTURE.md) in the repo.

## 🌐 Domain 1: User access & edge

Every request from the public internet terminates at Cloudflare's edge (Layer 8). `cloudflared` runs on each origin and dials outbound, so origins have no public inbound app ports. Cloudflare Access Free tier enforces email-domain allowlists before a single byte reaches the app. TLS is handled by Cloudflare; Caddy inside the cluster is ClusterIP-only.

## 🏗️ Domain 2: Infrastructure

- Layer 1, Cilium: eBPF-based network identity. Default-deny ingress and egress. Every connection allowlisted by CNP.
- Layer 2, Tetragon: kernel-level runtime enforcement. Policy violations trigger `SIGKILL`, not alerts.
- Layer 3, Key Vault + CSI: secrets mount as files via managed identity. No env vars, no ConfigMaps, no service principal passwords.
- Layer 7, Splunk: one place to search audit events. Every process, connection, and file access flows here via Fluent Bit + OTel.

## 👩‍💻 Domain 3: Development workflow

- Layer 5, Cisco AI Defense + CoSAI CodeGuard: AIBOM on every PR, Adversarial Hubness Detector on PDF changes, IDE scanner locally, CodeGuard rules injected into every Claude Code session.
- Layer 6, GitHub Actions: build, scan, deploy gates. `quality.yaml` runs pytest + vitest + lint + type check + gitleaks + tfsec on every PR.
- Pre-commit guardrails: local hook runs black, ruff, gitleaks, tfsec. GitHub Secret Protection is the third backstop.

## How it fits together

```
User browser
    ↓
Cloudflare edge (TLS, Zero Trust Access)         ← Layer 8
    ↓ (outbound tunnel)
cloudflared pod in AKS
    ↓
Caddy ClusterIP Service (security headers)       ← Layer 4
    ↓
React SPA + FastAPI backend (Cilium-secured,     ← Layers 1/2/3
Tetragon-watched, Key Vault-mounted)
    ↓
Claude API (egress-restricted)
    ↓
Response flows back through the tunnel
```

Every step is audited in Splunk via Fluent Bit (JSON events) + OTel Collector (metrics).

## Detailed layer pages

- [Infrastructure (layers 1, 2, 3, 7)](infrastructure.html)
- [AI / LLM security (layer 5)](ai-security.html)
- [Developer workflow (layer 6)](developer-workflow.html)
