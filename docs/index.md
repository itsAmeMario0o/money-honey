---
layout: default
title: Money Honey
---

# 🍯 Money Honey

Most AI chatbot demos skip security entirely. Money Honey does the opposite: eight independent security layers wrap a financial-education chatbot on AKS. The chatbot is the demo. The defense-in-depth architecture is the lesson.

Full architecture deep-dive: [ARCHITECTURE.md](https://github.com/itsAmeMario0o/money-honey/blob/main/ARCHITECTURE.md) in the repo.

## The three-domain framework

| Domain | What it protects | Layers |
|---|---|---|
| 🌐 User access & edge | How traffic reaches the app | Cloudflare Tunnel + Zero Trust (L8), Caddy internal routing (L4) |
| 🏗️ Infrastructure | Where the chatbot runs | Cilium (L1), Tetragon (L2), Key Vault + CSI (L3), Splunk (L7) |
| 👩‍💻 Development workflow | How code becomes production | Cisco AI Defense + CoSAI CodeGuard (L5), GitHub Actions + quality gates (L6) |

If one layer fails, the others still hold. That is the whole point.

## Tech stack at a glance

- Frontend: React 18 + Vite + TypeScript. Served by nginx, routed by Caddy inside the cluster.
- Backend: FastAPI (Python 3.12) + LangChain + FAISS + local sentence-transformers embeddings.
- LLM: Anthropic Claude (Haiku 4.5). Direct API, no third-party intermediary.
- Platform: Azure Kubernetes Service with Cilium data plane (v1.18.6).
- Runtime security: Tetragon as a DaemonSet, eBPF-powered.
- Secrets: Azure Key Vault + CSI Secret Store Driver, managed identity.
- Observability: Fluent Bit + OpenTelemetry Collector shipping to Splunk Enterprise Free.
- Public edge: Cloudflare Tunnel + Zero Trust (Free tier, up to 50 users).

## Explore

- [Architecture overview](architecture/overview.html)
- [Infrastructure security](architecture/infrastructure.html)
- [AI / LLM security](architecture/ai-security.html)
- [Developer workflow security](architecture/developer-workflow.html)
- [Setup guides](setup/)
- [Chatbot internals](chatbot/)
- [Operations runbooks](runbooks/)
- [Specifications](specs/)
- [Lessons learned](lessons-learned.html)
- [Cost](cost.html) · [Roadmap](roadmap.html)

## Source

[github.com/itsAmeMario0o/money-honey](https://github.com/itsAmeMario0o/money-honey)
