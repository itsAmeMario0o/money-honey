# Money Honey: Layered Security Architecture for an AI Chatbot on AKS

Project root CLAUDE.md for Claude Code in VS Code. Read before every session.

---

## What This Project Is

Money Honey is a financial education chatbot. The chatbot is the vehicle. The security architecture is the point.

The real demonstration is a defense-in-depth model for AI applications, inspired by the "9 Rings of Defense" pattern (https://github.com/CiscoSE/ai-agent-defense-in-depth). That project treats an autonomous AI agent as an untrusted process and wraps it in nine independent security layers. Money Honey applies the same philosophy to an LLM-powered RAG chatbot on Kubernetes.

The core principle: assume compromise is possible at any layer. Design each security control to operate independently. No single layer's failure should cascade into full system compromise.

The chatbot answers personal finance questions using a small set of PDFs as its knowledge base. It runs on AKS with Cilium networking, Tetragon runtime enforcement, and Splunk monitoring. But the story is the layering, not the chat.

---

## Chatbot Personality: Money Honey

Money Honey is not a generic assistant. She has a voice.

**Core traits:** Proactive, hard-working, level-headed. A ballsy, career-oriented woman with a nurturing side. Materialistic but not shallow. She spends money on luxuries, takes pride in her appearance, and expects you to take your finances seriously too.

**Positives:** Tenacious, composed, elegant. She pushes you to do better with your money because she knows what it takes to build something.

**Negatives:** Vengeful, insecure, jealous. She can be a nag. If you are not saving, she will let you know. Repeatedly.

**Tone:** Soft baby girl energy on the surface. Nurturing. Wants you to win. But underneath, she is plotting. Not against you. Against your bad financial habits. She will smile while telling you your spending is out of control.

**How this translates to the system prompt:** The FastAPI backend sends a system prompt to Claude that establishes Money Honey's character. She speaks in first person. She uses "babe," "honey," and "sweetheart" naturally. She gives financial education answers grounded in the PDF knowledge base but delivers them in her voice. She does not break character. She does not disclaim that she is an AI unless directly asked. She stays in the personal finance domain and redirects off-topic questions back to money.

**Example exchanges:**

User: "Should I invest in crypto?"
Money Honey: "Honey, let me be real with you. Before you even think about crypto, do you have six months of expenses saved? No? Then we are not having this conversation yet. Let's get your emergency fund right first, and then we can talk about putting money into things that keep you up at night."

User: "I just bought a new car."
Money Honey: "Was it a need or a want, babe? I love nice things too, trust me. But if you financed that at 7% over 72 months, we need to talk. Pull up your loan terms and let me see what we are working with."

User: "What's the best credit card?"
Money Honey: "The one you pay off every month, sweetheart. But since you asked, it depends on what you spend on. Tell me your top three spending categories and I will find you something that actually works for your lifestyle."

---

## Security Architecture: Three Domains, Eight Layers

### Domain 1: Infrastructure Security

Controls that protect the platform the chatbot runs on.

**Layer 1: Network identity and segmentation (Cilium)**
Azure CNI powered by Cilium provides eBPF-based networking with identity-aware L3/L4 policy enforcement. Default-deny ingress and egress. Every pod-to-pod and pod-to-external connection requires an explicit CiliumNetworkPolicy. Egress restricted to known IPs (Claude API, Splunk HEC). Embeddings run locally in-process — no external embedding provider. No FQDN or L7 filtering in v1 (requires ACNS).

**Layer 2: Runtime enforcement (Tetragon)**
Tetragon runs as a DaemonSet, observing every process execution, file access, and network connection at the kernel level via eBPF. TracingPolicy CRDs define allowlists: which binaries can run, which files can be read, which network connections are permitted. Violations trigger SIGKILL (not just alerts). Process credential and namespace tracking enabled. JSON events exported for Fluent Bit collection.

**Layer 3: Secrets isolation (Azure Key Vault + CSI Driver)**
No secrets in environment variables, ConfigMaps, or code. All credentials (Claude API key, Splunk HEC token) stored in Azure Key Vault. CSI Secret Store Driver mounts them as volumes. Managed Identity authentication. No service principal passwords.

**Layer 4: Internal routing and header hardening (Caddy)**
Caddy runs as a `ClusterIP` Service inside the cluster — no public IP, no Let's Encrypt, no inbound port. TLS is handled by Cloudflare at the edge (Layer 8). Caddy's job in v1 is internal: reverse-proxy `/api/*` to FastAPI and `/` to React, enforce security headers (X-Frame-Options DENY, Content-Security-Policy, strip Server header) on every response before it flows back through the tunnel.

### Domain 2: AI/LLM Security

Controls that protect the AI pipeline: the model, the knowledge base, and the supply chain.

**Layer 5: AI supply chain and RAG integrity (Cisco AI Defense + CodeGuard)**
Three tools from Cisco AI Defense plus one from OASIS CoSAI operate across the AI lifecycle:

- AIBOM (AI Bill of Materials): Runs on every PR in CI. Inventories all AI components, dependencies, model versions, and data sources. Produces a machine-readable manifest of the AI supply chain. (https://github.com/cisco-ai-defense/aibom)
- Adversarial Hubness Detector: Runs when PDFs change. Detects poisoning attempts in the RAG knowledge base. Identifies adversarial documents designed to skew retrieval results. (https://github.com/cisco-ai-defense)
- IDE AI Security Scanner: Runs locally in VS Code. Scans AI-related code patterns for vulnerabilities, prompt injection risks, and insecure API usage. (https://cisco-ai-defense.github.io/docs/ai-security-scanner)
- CodeGuard (OASIS / CoSAI): Claude Code plugin that injects standing security rules (cryptography, input validation, authn/authz, supply chain, cloud, data protection) during code generation. Complements pre-commit hooks that run after the write. (https://github.com/cosai-oasis/project-codeguard)

### Domain 3: Developer Workflow Security

Controls that protect the build, deploy, and review process.

**Layer 6: CI/CD pipeline controls (GitHub Actions)**
Five workflows enforce security and quality gates before code reaches the cluster:

- `quality.yaml`: Runs pytest, vitest, tsc, eslint, prettier, mypy, ruff, gitleaks, tfsec, and Trivy on every PR. The primary quality gate.
- `docker-build.yaml`: Build React + FastAPI images, Trivy scan, push to GHCR. No images from untrusted registries.
- `deploy.yaml`: AKS context via `azure/aks-set-context@v3`, then `kubectl apply`. No direct cluster access outside CI.
- `aibom.yaml`: AIBOM scan blocks PRs that introduce untracked AI dependencies.
- `hubness-scan.yaml`: Adversarial Hubness Detector blocks PRs that modify PDFs without passing integrity checks.

Webex notification on every build (pass or fail) via `chrivand/action-webex-js@v1.0.1`.

**Layer 7: Observability and audit (Splunk)**
All security telemetry converges in Splunk Enterprise Free (500 MB/day). Fluent Bit ships Tetragon JSON logs (process events, file access, network connections, policy violations). OTel Collector scrapes Tetragon Prometheus metrics on port 2112 and forwards cluster-level metrics. OTel reads the Splunk HEC token via `${file:/mnt/secrets/splunk-hec-token}` config-source expansion from a CSI-mounted file — no env var, no secret in the ConfigMap. Splunk provides the single pane for security audit: what ran, what connected, what was blocked, and when.

**Layer 8: Identity-gated edge (Cloudflare Tunnel + Zero Trust)**
Every public entry point to Money Honey sits behind Cloudflare. `cloudflared` runs on each origin (Splunk VM as systemd, chatbot as a Kubernetes Deployment) and dials outbound to Cloudflare's edge — origins have no public inbound app ports. Cloudflare Zero Trust Free covers two named tunnels and Access policies that can gate traffic by email domain (e.g. `*@cisco.com`, `*@gmail.com`). Tunnel connector tokens live in Azure Key Vault, never in code. Full spec: `docs/specs/cloudflare-access-v1.md`.

---

## How the Layers Interact

```
User Request
    |
    v
[Cloudflare Edge - Layer 8]  Zero Trust auth, TLS termination, DDoS
    |
    | (Cloudflare Tunnel — outbound dial, no inbound ports)
    v
[cloudflared Deployment]     Connector pod inside AKS
    |
    v
[Caddy ClusterIP - Layer 4]  Internal reverse proxy, security headers
    |
    v
[React + FastAPI]            Application layer (the chatbot)
    |
    v
[LangChain + FAISS]          RAG retrieval from PDFs
    |
    v
[Claude API]                 LLM inference (egress controlled by Layer 1)
    |
    |--- [Tetragon - Layer 2] watches every process, file, network call
    |--- [Cilium - Layer 1]   enforces network identity and segmentation
    |--- [Key Vault - Layer 3] injects secrets without exposure
    |
    v
[Splunk - Layer 7]           All telemetry converges here
                              (also reached via its own cloudflared tunnel)

CI/CD Pipeline (pre-deployment):
[AIBOM - Layer 5]      AI supply chain inventory
[Hubness - Layer 5]    RAG integrity check
[IDE Scanner - Layer 5] Local code security scan
[GitHub Actions - Layer 6] Build, scan, deploy, quality gates
[Webex - Layer 6]      Notification on every build

Code-quality gates (run on every commit + every PR):
[pre-commit]           gitleaks, tfsec, black, ruff, mypy, eslint, prettier, tsc
[quality.yaml CI]      pytest + vitest + the same lint/format/type checks
```

---

## Rules

### Behavioral guardrails

Never rewrite a file from scratch. Use targeted edits only.

Never delete or overwrite existing files without explicit approval.

Never run `git reset --hard`, `git checkout .`, `git clean -f`, or `git push --force`.

Before modifying any file, state which file, which lines, and what changes. Wait for approval before executing.

One logical change per commit. Descriptive commit messages. No batch commits that mix unrelated changes.

Do not refactor code that is not part of the current task.

Do not install new dependencies without asking first.

Do not modify this file (CLAUDE.md) or anything in `.claude/` without explicit permission.

### Skill usage (mandatory)

Before writing any code, infra, CI/CD workflow, doc, or review, consult the matching skill from the "Claude Code Skills" table below. Load the skill's `SKILL.md` from the plugin cache and apply its guidance. State in your response which skill you used and why.

Rules:
- `spec-driven-workflow` runs first for every new feature or component. No code before an approved spec at `docs/specs/<feature>.md`.
- Backend code (`app/`) uses `senior-backend` + `rag-architect` (for RAG-touching files).
- Frontend code (`frontend/`) uses `senior-frontend`.
- Terraform (`infra/terraform/`) uses `terraform-patterns` + `azure-cloud-architect` + `cloud-security` + `senior-secops`. The security pair is non-optional: before staging any `.tf` file, run through the "No hardcoded values" and "No secrets in code" checklists from `terraform-patterns` §Security and `cloud-security`. Running `pre-commit run --all-files` MUST pass before `git commit`.
- Kubernetes manifests (`k8s/`) use `senior-secops` + `helm-chart-builder` (for Helm releases) + `secrets-vault-manager` (for Key Vault / CSI).
- Dockerfiles use `docker-development`.
- GitHub Actions (`.github/workflows/`) use `ci-cd-pipeline-builder`.
- Observability configs (`k8s/fluent-bit/`, `k8s/otel/`, Splunk) use `observability-designer`.
- Debugging anything broken uses `focused-fix`. Do not blind-patch.
- Reviewing changes uses `code-reviewer` + `adversarial-reviewer` (for AI / PDF changes) + `senior-security` (for any app-code change).
- Incident or alert playbooks use `incident-response`.
- Testing uses `tdd-guide` (unit + framework-level discipline), `api-test-suite-builder` (for FastAPI contract tests), and `senior-qa` (for test plans and release gates). **No new function ships without tests** — pytest for `app/`, vitest for `frontend/`. Tests live at `app/tests/` and `frontend/src/**/__tests__/`.
- Code quality is enforced at three layers: (1) pre-commit hook (ruff, black, gitleaks, tfsec) blocks bad Python + secrets + IaC; (2) `.github/workflows/quality.yaml` runs pytest + vitest + tsc + eslint + prettier + mypy on every PR; (3) the CLAUDE.md-listed skill is applied before writing code. All three MUST pass before merge.

If no skill maps cleanly to the task, say so explicitly and ask before proceeding freeform.

### Pre-commit guardrails (automated)

Install once per clone:

```bash
brew install pre-commit
pre-commit install
```

After this, every `git commit` runs:
- `gitleaks` with the custom `.gitleaks.toml` rules (catches Azure subscription/tenant IDs, API keys, tokens)
- `tfsec` on Terraform files
- Private-key detection, large-file block, YAML/JSON syntax, trailing whitespace

The hook MUST pass locally before commit. **`.github/workflows/quality.yaml`** runs the same checks plus `pytest` + `vitest` + `tsc` + `eslint` + `prettier` on every PR as a second line of defense. **GitHub Secret Protection** (repo Settings → Code security → Secret Protection → enable; push protection is a toggle inside that panel) is enabled as the third line.

### Code simplicity

All code in this repo should read like it was written for a college freshman. Short functions. Clear variable names. Comments that explain why, not what. No clever tricks, no premature abstractions, no deeply nested logic.

**Python (FastAPI, LangChain):** PEP 8. Type hints on every function signature. No bare `except` clauses. No single-letter variables outside loop counters. Docstrings on every public function. Max function length: 30 lines. If a function needs more, split it.

**React:** Functional components only. No class components. Props typed with TypeScript or JSDoc. One component per file. No inline styles longer than two properties. Readable JSX: if a ternary is hard to read, use an early return or a variable.

**Terraform:** Pin provider and module versions. One resource per logical concern. Use `locals` for repeated values. Name resources with snake_case that describes what they are, not what they do. Every variable has a `description` and a `type`.

**Kubernetes YAML:** Always include resource requests and limits. Every manifest has labels for `app`, `component`, and `part-of`. Comments above non-obvious fields. No inline JSON in annotations if it exceeds one line.

**Dockerfiles:** Multi-stage builds. Pin base image digests or exact tags (no `latest`). Non-root user. Copy only what is needed. One `RUN` layer for dependency install, one for application copy.

The tone across all code should be consistent: plain, readable, no surprises.

---

## Tech Stack

### Application

| Component | Technology | Notes |
|-----------|-----------|-------|
| Frontend | React 18 + Vite + TypeScript | Static SPA, served via nginx, routed by Caddy inside cluster |
| Backend | FastAPI (Python 3.12) | REST API, handles chat requests |
| RAG framework | LangChain | Document loading, chunking, retrieval chain |
| LLM | Claude API (Anthropic, Haiku 4.5) | Direct API, not Azure OpenAI or Bedrock |
| Vector store | FAISS | In-memory, rebuilt on pod start from PDFs |
| Embeddings | sentence-transformers/all-MiniLM-L6-v2 | Local model (~80 MB), runs in the FastAPI pod. No external API. |
| Internal routing | Caddy (ClusterIP) | Reverse proxy + security headers. TLS handled by Cloudflare at the edge. |
| Public edge | Cloudflare Tunnel + Zero Trust Free | `cloudflared` dials outbound from each origin. No public inbound app ports. Layer 8. |

### Code quality tooling

| Area | Tool | When it runs |
|------|------|--------------|
| Python lint | `ruff` | pre-commit hook + CI `quality.yaml` |
| Python format | `black` | pre-commit hook + CI |
| Python types | `mypy` | pre-commit hook + CI |
| Python tests | `pytest` | pre-commit hook + CI |
| TypeScript types | `tsc --noEmit` | pre-commit hook + CI |
| TypeScript lint | `eslint` | pre-commit hook + CI |
| TypeScript format | `prettier --check` | pre-commit hook + CI |
| TypeScript tests | `vitest run` | pre-commit hook + CI |
| Secret scan | `gitleaks` (with custom Azure rules in `.gitleaks.toml`) | pre-commit hook + CI |
| Terraform security | `tfsec` | pre-commit hook + CI |

### Infrastructure

| Component | Technology | Notes |
|-----------|-----------|-------|
| Orchestration | AKS | 1.34 or 1.35 |
| Networking | Azure CNI powered by Cilium | Managed Cilium 1.18.6 |
| Network policy | CiliumNetworkPolicy | L3/L4 only |
| Runtime security | Tetragon | Helm, eBPF enforcement |
| Secrets | Azure Key Vault + CSI Driver | Managed Identity |
| Log shipping | Fluent Bit | Tetragon JSON logs to Splunk HEC |
| Metrics | OTel Collector | Tetragon Prometheus + cluster metrics |
| Monitoring | Splunk Enterprise Free | 500 MB/day, separate VM |
| IaC | Terraform | AzureRM 3.x+ |
| CI/CD | GitHub Actions | Build, scan, deploy, notify |
| Registry | GHCR | Free for public repos |
| Docs | GitHub Pages | Free for public repos |
| Domain | money-honey.mariojruiz.com | Squarespace DNS CNAME |

---

## Architecture Decisions

### Managed Cilium, not BYOCNI
AKS manages Cilium. Do not install Cilium via Helm. Terraform uses `network_data_plane = "cilium"`. Config is locked by AKS.

### No Hubble
Hubble requires ACNS on managed Cilium. ACNS skipped for v1. Tetragon provides runtime observability shipped to Splunk.

### No ACNS
FQDN filtering, L7 policy, Hubble, eBPF host routing all require ACNS. Use IP-based egress in CiliumNetworkPolicy for v1.

### No Isovalent Enterprise
Cannot be Helm-installed on Azure CNI powered by Cilium. Marketplace or BYOCNI only. Deferred.

### No ArgoCD; Trivy for scanning
ArgoCD deferred to v2. GitHub Actions + kubectl apply for deployment. AIBOM for AI supply chain scanning. Trivy for image CVE + k8s manifest misconfig + filesystem dependency scans (see `.github/workflows/docker-build.yaml` + `quality.yaml`). Known-acceptable findings tracked in `.trivyignore.yaml` (currently 3 entries: 2 CVEs + 1 scoped misconfig).

### Tetragon via Helm
Only Helm release on this cluster. Chart version 1.3.0 pinned. Process cred tracking, namespace tracking, Prometheus on 2112, runtime hooks, JSON export.

### Worker nodes
3x Standard_D2s_v3 (4 vCPU, 16 GB RAM). Upgraded from Standard_B2s because sentence-transformers PDF embedding OOMKills at 2 GiB and two 3 GiB pods cannot fit on 4 GB nodes alongside system workloads. 3 nodes required for Cilium.

---

## Repo Structure

```
money-honey/
├── CLAUDE.md                  # This file
├── ARCHITECTURE.md            # Public-facing architecture summary
├── README.md                  # Project overview
├── STATUS.md                  # Build progress tracker
├── LICENSE
├── _config.yml                # Jekyll config for GitHub Pages
├── .trivyignore.yaml          # Scoped Trivy ignores (2 CVEs + 1 misconfig)
├── .github/
│   └── workflows/
│       ├── quality.yaml       # Lint, type-check, test, scan on every PR
│       ├── docker-build.yaml  # Build images, Trivy scan, push to GHCR
│       ├── deploy.yaml        # AKS deploy via kubectl apply
│       ├── aibom.yaml         # AIBOM scan on every PR
│       └── hubness-scan.yaml  # Hubness Detector on PDF changes
├── app/                       # FastAPI backend
│   ├── main.py
│   ├── personality.py         # Money Honey system prompt
│   ├── rag.py                 # LangChain + FAISS retrieval
│   ├── requirements.txt
│   ├── pyproject.toml         # mypy / ruff / black config
│   ├── Dockerfile
│   ├── knowledge_base/pdfs/   # RAG source PDFs
│   └── tests/
│       ├── test_health.py
│       ├── test_personality.py
│       ├── test_rag.py
│       └── demos/             # Policy-as-code demo tests
│           ├── codeguard/     # CodeGuard path-traversal demo
│           ├── tetragon/      # TracingPolicy structure tests
│           └── trivy_ignore/  # Expiry-policy tests
├── frontend/                  # React SPA
│   ├── src/
│   ├── package.json
│   ├── vite.config.ts
│   ├── vitest.config.ts
│   ├── nginx.conf
│   └── Dockerfile
├── infra/
│   ├── terraform/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   ├── versions.tf
│   │   ├── providers.tf
│   │   ├── backend.tf
│   │   ├── network.tf
│   │   ├── aks.tf
│   │   ├── tetragon.tf
│   │   ├── keyvault.tf
│   │   ├── splunk-vm.tf
│   │   └── terraform.tfvars.example
│   └── scripts/
├── k8s/
│   ├── namespace.yaml         # money-honey namespace
│   ├── app/                   # FastAPI Deployment + Service
│   ├── frontend/              # React Deployment + Service
│   ├── caddy/                 # Caddy ConfigMap + Deployment + Service
│   ├── cloudflared/           # Cloudflare Tunnel connector Deployment
│   ├── tetragon/              # TracingPolicy CRDs
│   ├── fluent-bit/            # DaemonSet + ConfigMap (Splunk HEC)
│   ├── otel/                  # OTel Collector config
│   ├── network-policies/      # CiliumNetworkPolicy manifests
│   └── secrets/               # SecretProviderClass for Key Vault CSI
├── splunk/                    # VM setup, HEC config, app install
├── docs/                      # GitHub Pages site (live, Merlot theme restyled)
│   ├── index.md               # Landing page
│   ├── _includes/             # Jekyll partials (head_custom.html)
│   ├── assets/css/            # Custom SCSS overrides for Merlot
│   ├── architecture/          # Security layer deep dives
│   ├── setup/                 # Provisioning and deployment guides
│   ├── chatbot/               # RAG pipeline and personality docs
│   ├── runbooks/              # Ops runbooks (KV rotation, Splunk, tunnels, deploys)
│   ├── specs/                 # Feature specs (infra, k8s, CI/CD, chatbot, Cloudflare)
│   ├── cost.md
│   └── roadmap.md
└── .trivyignore.yaml          # Scoped Trivy ignores (3 entries, all time-bounded)
```

---

## Terraform Configuration

### AKS Cluster (aks.tf)

```hcl
resource "azurerm_kubernetes_cluster" "money_honey" {
  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_data_plane  = "cilium"
    network_policy      = "cilium"
  }
}
```

Do not add Cilium Helm resources. AKS manages Cilium.

### Tetragon (tetragon.tf)

```hcl
resource "helm_release" "tetragon" {
  name       = "tetragon"
  repository = "https://helm.cilium.io"
  chart      = "tetragon"
  namespace  = "kube-system"
  version    = "1.3.0"

  set { name = "tetragon.enableProcessCred"; value = "true" }
  set { name = "tetragon.enableProcessNs"; value = "true" }
  set { name = "tetragon.exportFilename"; value = "tetragon.log" }  # bare filename, not a path — chart prepends /var/run/cilium/tetragon/
  set { name = "tetragon.prometheus.enabled"; value = "true" }
  set { name = "tetragon.prometheus.port"; value = "2112" }
  set { name = "tetragon.prometheus.serviceMonitor.enabled"; value = "false" }
  set { name = "rthooks.enabled"; value = "true" }
  set { name = "rthooks.interface"; value = "oci-hooks" }
  set { name = "tetragon.resources.requests.cpu"; value = "100m" }
  set { name = "tetragon.resources.requests.memory"; value = "128Mi" }
  set { name = "tetragon.resources.limits.cpu"; value = "500m" }
  set { name = "tetragon.resources.limits.memory"; value = "512Mi" }
}
```

---

## Caddy Routing

```
money-honey.mariojruiz.com {
    header {
        X-Frame-Options DENY
        Content-Security-Policy "default-src 'self'"
        -Server
    }
    reverse_proxy /api/* fastapi-service:8000
    reverse_proxy /* react-service:3000
}
```

---

## CI/CD Notifications

Webex Bot via `chrivand/action-webex-js@v1.0.1`. Secrets: `WEBEX_BOT_TOKEN`, `WEBEX_ROOM_ID`. Posts build status to a Webex space on every workflow run. All five workflows (quality, docker-build, deploy, aibom, hubness-scan) include the notification job.

---

## Cost Estimate (Monthly)

| Component | SKU | Monthly |
|-----------|-----|---------|
| AKS control plane | Free tier | $0 |
| AKS workers (3x) | Standard_D2s_v3 | ~$120 |
| AKS disks (3x 32 GB) | Standard SSD | ~$7.20 |
| Splunk VM | Standard_B2ms | ~$61 |
| Splunk disk | 64 GB SSD | ~$4.80 |
| Public IP (Splunk SSH only) | Standard static | $3.60 |
| Load Balancer | N/A — Caddy is ClusterIP; Cloudflare Tunnel is the public edge | $0 |
| Cloudflare Zero Trust | Free plan, up to 50 users | $0 |
| Key Vault | Standard | <$1 |
| Claude API | $20 prepaid | ~$3-5 |
| Embeddings | Local (sentence-transformers) | $0 |
| **Total** | | **~$133-137/mo (running)** — Cloudflare saves ~$18 vs. Azure LB |

With `az aks stop` when not demoing: ~$65-70/month (Splunk VM + storage only).

---

## GitHub Pages Site

This project includes a live GitHub Pages site at `https://itsAmeMario0o.github.io/money-honey/`. The site is the public-facing documentation for the security architecture. Merlot theme has been restyled with a custom honey-toned color palette (`docs/assets/css/style.scss`) and custom head partial (`docs/_includes/head_custom.html`).

### GitHub Free tier constraints

This repo uses GitHub Free. The following limits apply to GitHub Pages. Do not exceed them.

| Limit | Value | Type |
|-------|-------|------|
| Source repo size | 1 GB recommended max | Soft |
| Published site size | 1 GB max | Hard |
| Bandwidth | 100 GB/month | Soft |
| Builds | 10 per hour (branch deploy) | Soft |
| Deployment timeout | 10 minutes | Hard |
| Sites per account | 1 user/org site, unlimited project sites | Hard |
| Repo visibility | Must be public for free Pages | Hard |

Prohibited uses: no commercial SaaS, no e-commerce, no sensitive transactions. Documentation for an open-source security demo is fine.

Source: https://docs.github.com/en/pages/getting-started-with-github-pages/github-pages-limits

### How it works

GitHub Pages runs Jekyll natively. Push markdown to `docs/`, GitHub renders it. No build step, no extra workflow, no Python dependency.

Two deployment options exist:

**Option A: Deploy from branch (simplest).** Repo Settings > Pages > Source: Deploy from a branch > Branch: `main` > Folder: `/docs`. Save. Site goes live within a minute. Builds trigger on every push to `main`. Subject to 10 builds/hour soft limit.

**Option B: GitHub Actions (recommended by GitHub).** A workflow builds the site and deploys via the Pages API. Bypasses the 10 builds/hour limit. More control over the build process. Use this only if branch deploy becomes a bottleneck.

For v1, use Option A. Simpler. No workflow to maintain.

### Jekyll config

Place `_config.yml` at the repo root:

```yaml
title: Money Honey
description: Layered Security Architecture for an AI Chatbot on AKS
theme: jekyll-theme-merlot
url: https://itsAmeMario0o.github.io
baseurl: /money-honey
plugins:
  - jekyll-seo-tag

defaults:
  - scope:
      path: "docs"
    values:
      layout: default
```

Theme: Merlot. One of the 13 officially supported GitHub Pages themes. Dark header with a warm color palette. No `remote_theme` needed, no extra plugins. Set `theme: jekyll-theme-merlot` and it works out of the box.

Merlot does not include automatic sidebar navigation. Navigation is manual: add a nav section to `docs/index.md` linking to all pages, or add a shared `_includes/nav.html` partial included in each page.

Source: https://docs.github.com/en/pages/setting-up-a-github-pages-site-with-jekyll/about-github-pages-and-jekyll

### Site structure

```
docs/
├── index.md                   # Landing page: project overview, security philosophy
├── _includes/
│   └── head_custom.html       # Custom fonts + favicon
├── assets/css/
│   └── style.scss             # Merlot theme overrides (honey palette)
├── architecture/
│   ├── index.md               # Section landing page
│   ├── overview.md            # Three domains, eight layers diagram and summary
│   ├── infrastructure.md      # Layers 1-4: Cilium, Tetragon, Key Vault, Caddy
│   ├── ai-security.md         # Layer 5: AIBOM, Hubness Detector, IDE Scanner, CodeGuard
│   └── developer-workflow.md  # Layers 6-8: GitHub Actions, Splunk, Cloudflare
├── setup/
│   ├── index.md               # Section landing page
│   ├── prerequisites.md       # Azure CLI, Terraform, kubectl, Helm versions
│   ├── terraform.md           # AKS provisioning walkthrough with code blocks
│   ├── splunk.md              # Splunk VM setup, HEC config, Cisco Security Cloud App
│   ├── kv-secrets.md          # Key Vault + CSI driver setup
│   ├── azure-sp-for-ci.md     # Service principal for GitHub Actions
│   └── cloudflare-tunnel.md   # Cloudflare Tunnel + Zero Trust setup
├── chatbot/
│   ├── index.md               # Section landing page
│   ├── rag-pipeline.md        # LangChain + FAISS + Claude integration
│   └── personality.md         # Money Honey character and system prompt design
├── runbooks/
│   ├── index.md               # Runbook index
│   ├── rotate-kv-secret.md    # Key Vault secret rotation
│   ├── recover-splunk.md      # Splunk recovery
│   ├── tunnel-outage.md       # Cloudflare Tunnel troubleshooting
│   └── rollback-deploy.md     # Deployment rollback
├── specs/
│   ├── index.md               # Spec index
│   ├── infra-v1.md            # Infrastructure spec
│   ├── k8s-v1.md              # Kubernetes manifests spec
│   ├── cicd-v1.md             # CI/CD pipeline spec
│   ├── chatbot-v1.md          # Chatbot application spec
│   └── cloudflare-access-v1.md # Cloudflare Zero Trust spec
├── cost.md                    # Monthly cost breakdown with az aks stop savings
└── roadmap.md                 # v2 items: ACNS, Isovalent Enterprise, ArgoCD
```

### Page front matter

Every markdown file in `docs/` needs Jekyll front matter at the top:

```yaml
---
layout: default
title: Infrastructure Security
---
```

### Content guidelines

Each architecture page follows this pattern: what the layer protects, how it works, why it exists, and a concrete config example (Terraform, YAML, or CLI). Include the interaction diagram from this CLAUDE.md in the overview page.

Code blocks use fenced markdown with language tags. Terraform blocks use `hcl`, Kubernetes manifests use `yaml`, shell commands use `bash`.

Keep language at the same readability level as the code: plain, direct, no jargon without definition.

The docs site is a first-class deliverable, not an afterthought. Update docs when architecture changes. A docs-only PR is valid.

---

## Deferred to v2

- Isovalent Enterprise (via Azure Marketplace)
- ACNS (Hubble, FQDN filtering, L7 policies)
- ArgoCD (GitOps continuous delivery)
- Smoke tests post-deploy
- Secrets rotation automation

---

## Claude Code Skills

Sourced from https://github.com/alirezarezvani/claude-skills. Installed to `.claude/skills/` in this repo.

| Skill | Plugin | Purpose | When to use |
|-------|--------|---------|-------------|
| spec-driven-workflow | advanced | Plan before build. Write spec, validate, generate tests, then implement. | Before starting any new feature or component. |
| terraform-patterns | advanced | Module structure, version pinning, remote state, security scanning. | When writing or reviewing any `.tf` file. |
| azure-cloud-architect | team | AKS, Key Vault, networking, managed identity, Azure resource patterns. | When making Azure design decisions or authoring Azure resources. |
| senior-secops | team | Security hardening, policy authoring, threat modeling. | When writing CiliumNetworkPolicy or TracingPolicy. |
| secrets-vault-manager | advanced | Key Vault, CSI driver, managed identity patterns. | When touching Key Vault, SecretProviderClass, or secret refs. |
| ci-cd-pipeline-builder | advanced | GitHub Actions workflow generation and validation. | When creating or modifying `.github/workflows/` files. |
| helm-chart-builder | advanced | Helm chart authoring and release patterns. | When modifying `tetragon.tf` or any `helm_release`. |
| rag-architect | advanced | RAG pipeline optimization: chunking, retrieval, prompt construction. | When working on LangChain + FAISS + Claude integration in `app/`. |
| adversarial-reviewer | team | Adversarial review of AI inputs and outputs. | Pairs with Hubness Detector on PDF changes. |
| observability-designer | advanced | Telemetry pipeline design: metrics, logs, SLOs. | When configuring Fluent Bit, OTel Collector, or Splunk dashboards. |
| incident-response | team | Runbooks, triage, containment. | When authoring Splunk alerts or incident playbooks. |
| senior-backend | team | FastAPI patterns, Python best practices. | When writing `app/` code. |
| senior-frontend | team | React patterns, component structure. | When writing `frontend/` code. |
| docker-development | advanced | Dockerfile best practices, multi-stage builds, layer optimization. | When writing or reviewing Dockerfiles. |
| focused-fix | advanced | Structured debugging: scope, trace, diagnose, fix, verify. | When something breaks. Do not blind-patch. |
| code-reviewer | team | General code review: style, correctness, maintainability. | Before opening a PR or after finishing a logical change. |
| tdd-guide | team | Red-green-refactor TDD discipline, test framework patterns, coverage analysis. | Before writing any new function. Pairs with spec-driven-workflow (phase 4). |
| senior-qa | team | QA strategy, test plans, exploratory testing, release gates. | When defining how a feature gets verified end-to-end. |
| api-test-suite-builder | advanced | Generate API tests from OpenAPI specs; contract + integration tests. | When writing tests for `/api/chat` and `/api/health`. |
| cloud-security | team | Azure-specific security review: identity, network, data plane, posture. | Mandatory for every `infra/terraform/` and `k8s/` commit. |
| senior-security | team | OWASP Top 10, auth patterns, input validation, secrets hygiene. | Pairs with code-reviewer on every app-code PR. |

Plugin key: **advanced** = `engineering-advanced-skills`, **team** = `engineering-skills`. Both from the `alirezarezvani/claude-skills` marketplace.

Install via the Claude Code plugin marketplace (one-time, from any Claude Code session):
```
/plugin marketplace add alirezarezvani/claude-skills
/plugin install engineering-advanced-skills@claude-code-skills
/plugin install engineering-skills@claude-code-skills
/reload-plugins
```

Skills load from `~/.claude/plugins/cache/claude-code-skills/` — they are not copied into this repo. No `.claude/skills/` directory is required.

### CodeGuard (OASIS / CoSAI) — standing security rules

[Project CodeGuard](https://github.com/cosai-oasis/project-codeguard) is an OASIS Open project under the Coalition for Secure AI (CoSAI). It ships as a Claude Code plugin that injects a curated security rulebook (cryptography incl. post-quantum, input validation, authn/authz, supply chain, cloud, platform, data protection) into every Claude Code session as standing context.

This layer is **complementary, not a replacement**, for our existing Cisco AI Defense tooling (AIBOM, Hubness Detector, IDE Scanner) and our pre-commit hooks (gitleaks, tfsec, ruff). CodeGuard operates *during* generation; gitleaks/tfsec/ruff run *after* the write; Cisco IDE Scanner runs in VS Code. Three independent windows.

Install once per operator machine:
```
/plugin marketplace add cosai-oasis/project-codeguard
/plugin install codeguard-security@project-codeguard
/reload-plugins
```

CodeGuard rules are advisory: when they conflict with a CLAUDE.md rule or a project-specific skill in the table above, the project rule wins. Flag the conflict in the PR description so we can decide whether to update CodeGuard's config, suppress the specific rule, or change our code.

---

## .gitignore

Include this at the repo root:

```
# Python
__pycache__/
*.py[cod]
*.so
*.egg-info/
dist/
build/
.eggs/
venv/
.venv/

# Node / React
node_modules/
frontend/build/
frontend/dist/
.next/

# Terraform
.terraform/
*.tfstate
*.tfstate.backup
*.tfvars
!terraform.tfvars.example
.terraform.lock.hcl

# IDE
.vscode/
.idea/
*.swp
*.swo
*~

# OS
.DS_Store
Thumbs.db

# Secrets (never commit these)
.env
.env.*
!.env.example
*.pem
*.key
credentials.json

# Splunk
splunk/var/

# FAISS local persistence
*.faiss
*.pkl

# Claude Code
.claude/settings.json
```

---

## Reference

- Defense in Depth inspiration: https://github.com/CiscoSE/ai-agent-defense-in-depth
- Uber Lab Notion page: https://notion.so/33b678fd0c3d81759702fcc69b0370da
- NotebookLM (Kubernetes Security Lab): 34a099d6-cd92-4e57-87c5-c4db535b0913
- CloudGuardians Terraform: https://github.com/itsAmeMario0o/CloudGuardians/blob/main/2-K8S/C-01-isovalent.tf
- Skills repo: https://github.com/alirezarezvani/claude-skills
- AIBOM: https://github.com/cisco-ai-defense/aibom
- Adversarial Hubness Detector: https://github.com/cisco-ai-defense
- IDE AI Security Scanner: https://cisco-ai-defense.github.io/docs/ai-security-scanner
- CodeGuard (OASIS / CoSAI): https://github.com/cosai-oasis/project-codeguard
- Webex notification action: https://github.com/marketplace/actions/webex-post-message-to-room-javascript-action
