# 🍯 Money Honey

A financial education chatbot wrapped in eight independent security layers. The chatbot is the demo. The defense-in-depth architecture is the lesson.

## 🎯 The idea

Money Honey answers personal finance questions in the voice of a nurturing-but-direct best friend. She grounds every answer in a small set of PDFs loaded into the knowledge base (local to the cluster, never exposed).

The project demonstrates a simple principle: **assume any one layer can fail, so no single layer gets to matter.** Treat the AI like an untrusted process and wrap it in independent controls that each do one job well.

## 🛡️ The eight layers

| # | Layer | What it does |
|---|---|---|
| 1 | **Cilium network identity** | eBPF-powered L3/L4 policy. Default-deny ingress and egress. Identity-aware, not IP-aware. |
| 2 | **Tetragon runtime enforcement** | Kernel-level process, file, and network visibility. Violations get `SIGKILL`, not alerts. |
| 3 | **Azure Key Vault + CSI driver** | Secrets mounted as volumes via Managed Identity. No env vars, no configmaps, no service principal passwords. |
| 4 | **Caddy (ClusterIP) internal routing** | Reverse proxy inside the cluster. Enforces security headers (CSP, X-Frame-Options, stripped Server header). TLS is handled by Cloudflare at the edge, not here. |
| 5 | **Cisco AI Defense** | AIBOM on every PR, Adversarial Hubness Detector on PDF changes, IDE scanner in VS Code. |
| 6 | **GitHub Actions gates** | Build → scan → deploy. AIBOM, Hubness, and code-quality checks all block merges. |
| 7 | **Splunk observability** | Every process, network call, and violation lands in one searchable place. |
| 8 | **Cloudflare Tunnel + Zero Trust** | `cloudflared` dials outbound from each origin. No public inbound app ports. Email-domain allowlists (Free plan, ≤50 users). See [`docs/specs/cloudflare-access-v1.md`](docs/specs/cloudflare-access-v1.md). |

Plus **pre-commit guardrails** (gitleaks, tfsec, black, ruff, mypy, eslint, prettier, vitest) and **GitHub Secret Protection with push protection** — three independent lines of defense against leaked secrets.

## 🧱 Tech stack

| Area | Technology |
|---|---|
| Frontend | React 18 + Vite + TypeScript, Space Grotesk type, gradient + glow design system |
| Backend | FastAPI (Python 3.12) |
| RAG | LangChain 0.3.x + FAISS, local `sentence-transformers/all-MiniLM-L6-v2` embeddings |
| LLM | Anthropic Claude (Haiku 4.5) |
| Platform | Azure Kubernetes Service with Cilium data plane (Cilium 1.18.6) |
| Runtime security | Tetragon (eBPF, DaemonSet) with namespaced TracingPolicies |
| Secrets | Azure Key Vault + CSI Secret Store Driver (managed identity) |
| Observability | Fluent Bit + OpenTelemetry → Splunk Enterprise Free (Ubuntu 22.04 VM) |
| Public edge | Cloudflare Tunnel + Zero Trust (Free plan) |
| IaC | Terraform (AzureRM 4.x) with remote state in Azure Blob |
| CI/CD | GitHub Actions (quality, docker-build, deploy, aibom, hubness-scan) + Dependabot |
| Registry | GitHub Container Registry (public packages) |
| Image scan | Trivy (image, filesystem, k8s manifest) |
| AI BOM | Cisco AI Defense `cisco-aibom` (PyPI) |
| Agent security rules | [CodeGuard](https://github.com/cosai-oasis/project-codeguard) — OASIS/CoSAI Claude Code plugin, injects secure-coding rules during generation |
| Docs | GitHub Pages (Jekyll / Merlot theme) |
| Code quality | black, ruff, mypy, pytest (Python); prettier, eslint, tsc, vitest (TypeScript) |
| Pre-commit | gitleaks, tfsec, ruff, black + scoped `.trivyignore.yaml` / `.gitleaksignore` |

## 🚦 Current status

| Step | Status |
|---|---|
| 1. Repo scaffold | ✅ Done |
| 2. Application layer (FastAPI + React) | ✅ Done — frontend redesign with gradient/glow palette landed |
| 3. Infrastructure (Terraform) | ✅ Applied to Azure — AKS, KV, VNet, Splunk VM all live |
| 4. Kubernetes manifests | ✅ All manifests applied — namespace, 8 CNPs, 3 TracingPolicies, 2 SPCs, Fluent Bit, OTel, Caddy, fastapi/react Deployments. App pods waiting on first successful image pull. |
| 5. CI/CD workflows | ✅ Active — quality + docker-build + deploy + aibom + hubness-scan all wired. Azure SP federated, kubelogin in deploy, Trivy in build, scoped ignores in `.trivyignore.yaml`. |
| 6. Jekyll docs site | 🚧 Landing page + architecture deep-dives + setup walkthroughs written. Enable Pages in Settings when ready for public docs. |
| Cloudflare Tunnel (Layer 8) | 🚧 Splunk VM tunnel installed; chatbot tunnel pod manifest written. Tokens still placeholder in KV. Public Hostname routing pending operator. |
| Splunk install | ✅ Splunk Enterprise Free running, HEC token populated in KV |
| Anthropic key | ⏳ KV placeholder — operator-supplied when ready |
| Branch protection | ✅ Force-push + deletion blocked on `main` |

See [`CLAUDE.md`](./CLAUDE.md) for the full architecture, build plan, and Claude Code session rules.

## 🧪 Run it locally

You only need local dev today. Cloud deploy needs the Terraform from step 3 applied first.

```bash
# Backend
cd app
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env          # add your ANTHROPIC_API_KEY
uvicorn main:app --reload     # :8000

# Frontend (second terminal)
cd frontend
npm install
npm run dev                   # :3000 — Vite proxies /api to :8000
```

Drop your PDFs into `app/knowledge_base/pdfs/` — the folder is gitignored so source material never gets committed.

## 🏗️ Deploy to Azure (when step 4 lands)

```bash
# One-time: create the Terraform state backend (local-state bootstrap module)
cd infra/terraform-bootstrap
terraform init
terraform apply

# Then the main stack (remote state points at the SA created above)
cd ../terraform
terraform init
terraform plan -out=tfplan
terraform apply tfplan

# Splunk post-install (manual, runs once)
VM_IP=$(terraform output -raw splunk_vm_public_ip) \
  SPLUNK_ADMIN_PASSWORD='...' \
  ../scripts/install-splunk.sh
```

## 🔒 Contributor setup

The repo enforces automated security checks on every commit:

```bash
brew install pre-commit
pre-commit install
```

After that, `git commit` automatically runs:
- **gitleaks** with custom Azure subscription/tenant-ID patterns
- **tfsec** on Terraform files
- Private-key detection, large-file block, YAML/JSON syntax

**Three layers of prevention:**
1. Local pre-commit hook (above)
2. CI workflow scan (step 5)
3. GitHub Secret Protection with push protection (repo setting)

Read [`CLAUDE.md`](./CLAUDE.md) §Rules before editing anything. Every change starts with the matching skill from the Claude Code Skills table.

## 📚 Key documents

- [`CLAUDE.md`](./CLAUDE.md) — Architecture, rules, skill usage, tech stack, cost, build plan
- [`ARCHITECTURE.md`](./ARCHITECTURE.md) — Comprehensive security, development, and testing architecture
- [`STATUS.md`](./STATUS.md) — Live build status, what's running, what's blocked, what's next
- [`docs/specs/chatbot-v1.md`](./docs/specs/chatbot-v1.md) — Application layer spec
- [`docs/specs/infra-v1.md`](./docs/specs/infra-v1.md) — Terraform / Azure spec
- [`docs/specs/cloudflare-access-v1.md`](./docs/specs/cloudflare-access-v1.md) — Zero-trust edge (Layer 8)
- [`docs/setup/cloudflare-tunnel.md`](./docs/setup/cloudflare-tunnel.md) — Phase 2 walkthrough for the public edge
- [`docs/runbooks/`](./docs/runbooks/) — Ops playbooks: rotate KV secret, recover Splunk, tunnel outage, deploy rollback
- [`app/tests/demos/`](./app/tests/demos/) — Per-layer demo artifacts (CodeGuard path-traversal demo today; more layers landing in the demo workflow)
