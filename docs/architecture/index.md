---
layout: default
title: Architecture
---

# 🏛️ Architecture

The Money Honey security architecture is split into three domains, eight layers. Each page below is a deep dive into one part of the model.

| Page | What it covers |
|---|---|
| [Overview](overview.html) | The three-domain framework, the eight layers, and how they interact at request time. |
| [Infrastructure security](infrastructure.html) | Layers 1–4: Cilium network identity, Tetragon runtime enforcement, Azure Key Vault + CSI, Caddy internal routing. |
| [AI / LLM security](ai-security.html) | Layer 5: Cisco AI Defense (AIBOM, Hubness Detector, IDE Scanner) and CoSAI CodeGuard. |
| [Developer workflow security](developer-workflow.html) | Layers 6–7: GitHub Actions gates, pre-commit hooks, Splunk audit. |

For the full reference document with diagrams and code examples, see [`ARCHITECTURE.md`](https://github.com/itsAmeMario0o/money-honey/blob/main/ARCHITECTURE.md) in the repo.
