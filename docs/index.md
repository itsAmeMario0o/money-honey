---
layout: default
title: Money Honey
---

# 🍯 Money Honey

A financial-education AI chatbot wrapped in **eight independent security layers**. The chatbot is the demo. The defense-in-depth architecture is the lesson.

> 👉 **The full architecture deep-dive lives in [ARCHITECTURE.md](https://github.com/itsAmeMario0o/money-honey/blob/main/ARCHITECTURE.md)** in the repo.

## The three-domain framework

| Domain | What it protects | Layers |
|---|---|---|
| 🌐 **User access & edge** | How traffic reaches the app | Cloudflare Tunnel + Zero Trust (L8), Caddy internal routing (L4) |
| 🏗️ **Infrastructure** | Where the chatbot runs | Cilium (L1), Tetragon (L2), Key Vault + CSI (L3), Splunk (L7) |
| 👩‍💻 **Development workflow** | How code becomes production | Cisco AI Defense (L5), GitHub Actions + quality gates (L6) |

No single failure cascades — that's the whole point.

## Tech stack at a glance

- **Frontend**: React 18 + Vite + TypeScript (served by nginx, routed by Caddy inside the cluster)
- **Backend**: FastAPI (Python 3.12) + LangChain + FAISS + local sentence-transformers embeddings
- **LLM**: Anthropic Claude (Haiku 4.5) — direct API, no third-party intermediary
- **Platform**: Azure Kubernetes Service with Cilium data plane (v1.18.6)
- **Runtime security**: Tetragon as a DaemonSet, eBPF-powered
- **Secrets**: Azure Key Vault + CSI Secret Store Driver, managed identity
- **Observability**: Fluent Bit + OpenTelemetry Collector → Splunk Enterprise Free
- **Public edge**: Cloudflare Tunnel + Zero Trust (Free tier, ≤50 users)

## Explore

- [Architecture overview](architecture/overview.html)
- [Infrastructure security](architecture/infrastructure.html)
- [AI / LLM security](architecture/ai-security.html)
- [Developer workflow security](architecture/developer-workflow.html)
- [Setup guides](setup/)
- [Chatbot internals](chatbot/)

## Source

[github.com/itsAmeMario0o/money-honey](https://github.com/itsAmeMario0o/money-honey)
