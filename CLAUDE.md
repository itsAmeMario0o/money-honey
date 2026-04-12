# Money Honey: Layered Security Architecture for an AI Chatbot on AKS

Project root CLAUDE.md for Claude Code in VS Code. Read before every session.

---

## What This Project Is

Money Honey is a financial education chatbot. The chatbot is the vehicle. The security architecture is the point.

The real demonstration is a defense-in-depth model for AI applications, inspired by the "9 Rings of Defense" pattern (https://github.com/CiscoSE/ai-agent-defense-in-depth). That project treats an autonomous AI agent as an untrusted process and wraps it in nine independent security layers. Money Honey applies the same philosophy to an LLM-powered RAG chatbot on Kubernetes.

The core principle: assume compromise is possible at any layer. Design each security control to operate independently. No single layer's failure should cascade into full system compromise.

The chatbot answers personal finance questions using 3-4 CFP/investment PDFs as its knowledge base. It runs on AKS with Cilium networking, Tetragon runtime enforcement, and Splunk monitoring. But the story is the layering, not the chat.

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

## Security Architecture: Three Domains, Seven Layers

### Domain 1: Infrastructure Security

Controls that protect the platform the chatbot runs on.

**Layer 1: Network identity and segmentation (Cilium)**
Azure CNI powered by Cilium provides eBPF-based networking with identity-aware L3/L4 policy enforcement. Default-deny ingress and egress. Every pod-to-pod and pod-to-external connection requires an explicit CiliumNetworkPolicy. Egress restricted to known IPs (Claude API, OpenAI embeddings, Splunk HEC). No FQDN or L7 filtering in v1 (requires ACNS).

**Layer 2: Runtime enforcement (Tetragon)**
Tetragon runs as a DaemonSet, observing every process execution, file access, and network connection at the kernel level via eBPF. TracingPolicy CRDs define allowlists: which binaries can run, which files can be read, which network connections are permitted. Violations trigger SIGKILL (not just alerts). Process credential and namespace tracking enabled. JSON events exported for Fluent Bit collection.

**Layer 3: Secrets isolation (Azure Key Vault + CSI Driver)**
No secrets in environment variables, ConfigMaps, or code. All credentials (Claude API key, Splunk HEC token, embeddings API key) stored in Azure Key Vault. CSI Secret Store Driver mounts them as volumes. Managed Identity authentication. No service principal passwords.

**Layer 4: TLS termination and header hardening (Caddy)**
Caddy handles automatic Let's Encrypt TLS for money-honey.mariojruiz.com. Security headers enforced: X-Frame-Options DENY, Content-Security-Policy, Server header stripped. Reverse proxy routes `/api/*` to FastAPI and `/` to React. No direct pod exposure.

### Domain 2: AI/LLM Security

Controls that protect the AI pipeline: the model, the knowledge base, and the supply chain.

**Layer 5: AI supply chain and RAG integrity (Cisco AI Defense)**
Three tools from Cisco AI Defense operate across the AI lifecycle:

- AIBOM (AI Bill of Materials): Runs on every PR in CI. Inventories all AI components, dependencies, model versions, and data sources. Produces a machine-readable manifest of the AI supply chain. (https://github.com/cisco-ai-defense/aibom)
- Adversarial Hubness Detector: Runs when PDFs change. Detects poisoning attempts in the RAG knowledge base. Identifies adversarial documents designed to skew retrieval results. (https://github.com/cisco-ai-defense)
- IDE AI Security Scanner: Runs locally in VS Code. Scans AI-related code patterns for vulnerabilities, prompt injection risks, and insecure API usage. (https://cisco-ai-defense.github.io/docs/ai-security-scanner)

### Domain 3: Developer Workflow Security

Controls that protect the build, deploy, and review process.

**Layer 6: CI/CD pipeline controls (GitHub Actions)**
Four workflows enforce security gates before code reaches the cluster:

- `docker-build.yaml`: Build React + FastAPI images, push to GHCR. No images from untrusted registries.
- `deploy.yaml`: AKS context via `azure/aks-set-context@v3`, then `kubectl apply`. No direct cluster access outside CI.
- `aibom.yaml`: AIBOM scan blocks PRs that introduce untracked AI dependencies.
- `hubness-scan.yaml`: Adversarial Hubness Detector blocks PRs that modify PDFs without passing integrity checks.

Webex notification on every build (pass or fail) via `chrivand/action-webex-js`.

**Layer 7: Observability and audit (Splunk)**
All security telemetry converges in Splunk Enterprise Free (500 MB/day). Fluent Bit ships Tetragon JSON logs (process events, file access, network connections, policy violations). OTel Collector scrapes Tetragon Prometheus metrics on port 2112 and forwards cluster-level metrics. Splunk provides the single pane for security audit: what ran, what connected, what was blocked, and when.

---

## How the Layers Interact

```
User Request
    |
    v
[Caddy - Layer 4]  TLS termination, header hardening
    |
    v
[React + FastAPI]   Application layer (the chatbot)
    |
    v
[LangChain + FAISS] RAG retrieval from PDFs
    |
    v
[Claude API]        LLM inference (egress controlled by Layer 1)
    |
    |--- [Tetragon - Layer 2] watches every process, file, network call
    |--- [Cilium - Layer 1] enforces network identity and segmentation
    |--- [Key Vault - Layer 3] injects secrets without exposure
    |
    v
[Splunk - Layer 7]  All telemetry converges here

CI/CD Pipeline (pre-deployment):
[AIBOM - Layer 5]   AI supply chain inventory
[Hubness - Layer 5] RAG integrity check
[IDE Scanner - Layer 5] Local code security scan
[GitHub Actions - Layer 6] Build, scan, deploy gates
[Webex - Layer 6]   Notification on every build
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
| Frontend | React | Static SPA served by Caddy |
| Backend | FastAPI (Python) | REST API, handles chat requests |
| RAG framework | LangChain | Document loading, chunking, retrieval chain |
| LLM | Claude API (Anthropic) | Direct API, not Azure OpenAI or Bedrock |
| Vector store | FAISS | In-memory or local persistence, 3-4 PDFs |
| Embeddings | text-embedding-3-small (OpenAI) | Cost: less than $1/month for this corpus size |
| Reverse proxy | Caddy | Automatic Let's Encrypt TLS |

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

### No ArgoCD, no Trivy
Deferred to v2. GitHub Actions + kubectl apply for deployment. AIBOM for supply chain scanning.

### Tetragon via Helm
Only Helm release on this cluster. Chart version 1.3.0 pinned. Process cred tracking, namespace tracking, Prometheus on 2112, runtime hooks, JSON export.

### Worker nodes
3x Standard_B2als_v2 (2 vCPU, 4 GB RAM). Cheapest viable option. 3 nodes required for Cilium.

---

## Repo Structure

```
money-honey/
├── CLAUDE.md                  # This file
├── _config.yml                # Jekyll config for GitHub Pages
├── .github/
│   └── workflows/
│       ├── docker-build.yaml  # Build images, push to GHCR
│       ├── deploy.yaml        # AKS deploy via kubectl apply
│       ├── aibom.yaml         # AIBOM scan on every PR
│       └── hubness-scan.yaml  # Hubness Detector on PDF changes
├── app/                       # FastAPI backend
│   ├── main.py
│   ├── requirements.txt
│   └── Dockerfile
├── frontend/                  # React SPA
│   ├── src/
│   ├── package.json
│   └── Dockerfile
├── infra/
│   ├── terraform/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   ├── aks.tf
│   │   ├── tetragon.tf
│   │   ├── keyvault.tf
│   │   ├── splunk-vm.tf
│   │   └── dns.tf
│   └── scripts/
├── k8s/
│   ├── app/                   # FastAPI Deployment + Service
│   ├── frontend/              # React Deployment + Service
│   ├── caddy/                 # Caddy ConfigMap + Deployment + Service
│   ├── tetragon/              # TracingPolicy CRDs
│   ├── fluent-bit/            # DaemonSet + ConfigMap (Splunk HEC)
│   ├── otel/                  # OTel Collector config
│   ├── network-policies/      # CiliumNetworkPolicy manifests
│   └── secrets/               # SecretProviderClass for Key Vault CSI
├── splunk/                    # VM setup, HEC config, app install
├── docs/                      # GitHub Pages (Jekyll)
│   ├── index.md               # Landing page
│   ├── architecture/          # Security layer deep dives
│   ├── setup/                 # Provisioning and deployment guides
│   ├── chatbot/               # RAG pipeline and personality docs
│   ├── cost.md
│   └── roadmap.md
└── notebooks/                 # Jupyter notebooks (local VS Code only)
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
  set { name = "tetragon.exportFilename"; value = "/var/run/cilium/tetragon/tetragon.log" }
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

Webex Bot via `chrivand/action-webex-js`. Secrets: `WEBEX_BOT_TOKEN`, `WEBEX_ROOM_ID`. Posts build status to a Webex space on every workflow run.

---

## Cost Estimate (Monthly)

| Component | SKU | Monthly |
|-----------|-----|---------|
| AKS control plane | Free tier | $0 |
| AKS workers (3x) | Standard_B2als_v2 | ~$54 |
| AKS disks (3x 32 GB) | Standard SSD | ~$7.20 |
| Splunk VM | Standard_B2ms | ~$61 |
| Splunk disk | 64 GB SSD | ~$4.80 |
| Public IP | Standard static | $3.60 |
| Load Balancer | Standard | ~$18 |
| Key Vault | Standard | <$1 |
| Claude API | $20 prepaid | ~$3-5 |
| Embeddings | text-embedding-3-small | <$1 |
| **Total** | | **~$153-155/mo (running)** |

With `az aks stop` when not demoing: ~$65-70/month (Splunk VM + storage only).

---

## GitHub Pages Site

This project includes a GitHub Pages site at `https://itsAmeMario0o.github.io/money-honey/`. The site is the public-facing documentation for the security architecture.

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
├── architecture/
│   ├── overview.md            # Three domains, seven layers diagram and summary
│   ├── infrastructure.md      # Layers 1-4: Cilium, Tetragon, Key Vault, Caddy
│   ├── ai-security.md         # Layer 5: AIBOM, Hubness Detector, IDE Scanner
│   └── developer-workflow.md  # Layers 6-7: GitHub Actions gates, Splunk audit
├── setup/
│   ├── prerequisites.md       # Azure CLI, Terraform, kubectl, Helm versions
│   ├── terraform.md           # AKS provisioning walkthrough with code blocks
│   ├── tetragon.md            # Tetragon deployment and TracingPolicy examples
│   ├── splunk.md              # Splunk VM setup, HEC config, Cisco Security Cloud App
│   └── ci-cd.md               # GitHub Actions workflows and Webex notifications
├── chatbot/
│   ├── rag-pipeline.md        # LangChain + FAISS + Claude integration
│   └── personality.md         # Money Honey character and system prompt design
├── cost.md                    # Monthly cost breakdown with az aks stop savings
└── roadmap.md                 # v2 items: ACNS, Isovalent Enterprise, Trivy, ArgoCD
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
- Trivy (container image CVE scanning)
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

Plugin key: **advanced** = `engineering-advanced-skills`, **team** = `engineering-skills`. Both from the `alirezarezvani/claude-skills` marketplace.

Install via the Claude Code plugin marketplace (one-time, from any Claude Code session):
```
/plugin marketplace add alirezarezvani/claude-skills
/plugin install engineering-advanced-skills@claude-code-skills
/plugin install engineering-skills@claude-code-skills
/reload-plugins
```

Skills load from `~/.claude/plugins/cache/claude-code-skills/` — they are not copied into this repo. No `.claude/skills/` directory is required.

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
- Webex notification action: https://github.com/marketplace/actions/webex-post-message-to-room-javascript-action
