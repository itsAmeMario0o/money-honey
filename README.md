# 🍯 Money Honey

A financial education chatbot with a serious security story behind it.

## 🎯 What this is

Money Honey is an AI chatbot that answers personal finance questions. She has a personality (think: a ballsy, nurturing best friend who wants you to get your money right) and she pulls her answers from a small set of CFP / investment PDFs.

But the **real point of this project is the security architecture**. The chatbot is the demo. The defense-in-depth layers around it are the lesson.

## 🛡️ The security idea

The core idea is simple: assume any single layer can fail, so don't rely on any one of them. Treat the AI like an untrusted process and wrap it in independent controls that each do one job well.

In Money Honey, that's **7 independent security layers** across **3 domains**:

- 🏗️ **Infrastructure security** — Cilium network policies, Tetragon runtime enforcement, Azure Key Vault secrets, Caddy TLS
- 🤖 **AI / LLM security** — Cisco AI Defense tools (AIBOM, Hubness Detector, IDE Scanner)
- 🧑‍💻 **Developer workflow security** — GitHub Actions gates, Splunk audit trail

If one layer gets compromised, the others still hold. That's the whole point.

## 🧱 Tech stack (quick view)

| Layer | Tech |
|---|---|
| Frontend | React + Vite |
| Backend | FastAPI (Python 3.12) |
| RAG | LangChain + FAISS |
| LLM | Claude API |
| Platform | Azure Kubernetes Service (AKS) with Cilium |
| Runtime security | Tetragon (eBPF) |
| Secrets | Azure Key Vault + CSI Driver |
| Observability | Fluent Bit + OpenTelemetry + Splunk |
| CI/CD | GitHub Actions + GHCR |

## 📚 Full docs

The complete architecture write-up lives on the project site:
👉 **https://itsAmeMario0o.github.io/money-honey/** *(coming in step 6)*

## 🤝 For contributors

Read [`CLAUDE.md`](./CLAUDE.md) first. It has the rules, the architecture decisions, and the tone guide for code and docs. Every Claude Code session starts there.

## 🚧 Status

Early build. Scaffolding is in place. Application layer, infra, and CI/CD are being added step by step. See [`CLAUDE.md`](./CLAUDE.md) for the full plan.
