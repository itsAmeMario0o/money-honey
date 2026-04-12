# 🏛️ Money Honey Architecture

A comprehensive walk through the architecture, focusing on **how security is woven across three surfaces**: the user's path to the chatbot, the infrastructure that runs it, and the developer workflow that ships code. The same defense-in-depth principle applies to all three — assume any single control can fail, and make sure no single failure compromises the whole system.

---

## 📐 The framework at a glance

Money Honey's architecture is split into **three domains**, with **eight independent security layers** mapped across them. Each layer does one job well. Each control is independent of the others.

| Domain | What it protects | Layers |
|---|---|---|
| 🌐 **User access & edge** | How traffic from the internet reaches the app | Cloudflare Tunnel + Zero Trust, Caddy internal routing, TLS |
| 🏗️ **Infrastructure** | Where the chatbot runs | Cilium, Tetragon, Key Vault, Splunk |
| 👩‍💻 **Development workflow** | How code becomes production | Cisco AI Defense, GitHub Actions, pre-commit, quality gates |

The sections below walk each one.

---

## 🌐 User access & edge security

### 1. Zero-trust at the front door (Layer 8 — Cloudflare)

Every request from the public internet is **terminated at Cloudflare's edge** before it reaches Azure. This means:

- **No origin has a public inbound app port.** `cloudflared` runs on each origin (the Splunk VM and inside the AKS cluster as a Deployment) and dials outbound to Cloudflare. Attackers on the internet can't scan or probe the chatbot — there's nothing listening.
- **TLS is free and automatic.** Cloudflare manages certificates. Caddy inside the cluster runs plaintext HTTP because the only thing that talks to it is the `cloudflared` connector pod.
- **Identity-based access control.** Cloudflare Access Free tier (≤50 users) gates both the chatbot and the Splunk dashboard with email-domain allowlists like `*@cisco.com` or `*@gmail.com`. Users authenticate with Google, Microsoft, or email PIN before a single byte reaches the app.
- **No custom DNS required for v1.** Tunnels get Cloudflare-provided hostnames. Upgrading to a custom domain later is a DNS change, not an architecture change.

### 2. Internal routing and header hardening (Layer 4 — Caddy)

Once traffic is inside the cluster, Caddy takes over. It's not exposed publicly — it's a `ClusterIP` Service only reachable from `cloudflared`. Its jobs:

- Reverse-proxy `/api/*` to the FastAPI backend and `/` to the React frontend.
- Enforce security headers on every response: `X-Frame-Options: DENY`, `Content-Security-Policy: default-src 'self'`, strip the `Server` header, HSTS.
- Normalize the path and method namespace so misconfigured clients can't bypass routing.

### 3. What the user sees

```
User Browser
    │
    │ (HTTPS to Cloudflare)
    ▼
┌───────────────────────────────────┐
│ Cloudflare Edge                   │  Layer 8
│  - TLS termination (free LE)      │
│  - Zero Trust Access auth         │
│  - DDoS absorption                │
└───────────────────────────────────┘
    │ (tunnel, outbound-only from origin)
    ▼
┌───────────────────────────────────┐
│ cloudflared pod in AKS            │
└───────────────────────────────────┘
    │
    ▼
┌───────────────────────────────────┐
│ Caddy (ClusterIP)                 │  Layer 4
│  - Reverse proxy + security hdrs  │
└───────────────────────────────────┘
    │
    ▼
┌─────────────────┐   ┌─────────────────┐
│ React SPA       │   │ FastAPI         │
│ (nginx pod)     │   │ + LangChain     │
└─────────────────┘   └─────────────────┘
```

---

## 🏗️ Infrastructure security

The chatbot runs on **Azure Kubernetes Service** with guardrails at four independent levels.

### 1. Network identity and segmentation (Layer 1 — Cilium)

AKS uses Azure CNI **powered by Cilium** — eBPF-based networking with **identity-aware** L3/L4 policy.

- Default-deny ingress and egress at pod level.
- Every pod-to-pod and pod-to-external connection requires an explicit `CiliumNetworkPolicy`.
- Egress is narrowly scoped: only Claude API and Splunk HEC are allowed. Embeddings run locally, so there's no external embedding provider to whitelist.
- `network_data_plane = "cilium"` + `network_policy = "cilium"` pinned in Terraform.

### 2. Runtime enforcement (Layer 2 — Tetragon)

Tetragon runs as a **DaemonSet on every node**, hooking into the kernel via eBPF.

- Observes every process execution, file access, and network connection system-wide.
- `TracingPolicy` CRDs define allowlists for which binaries can run, which files can be read, which network connections are permitted.
- Violations trigger `SIGKILL` — not alerts. Malicious or unexpected processes are killed, not logged and forgotten.
- Process credential and namespace tracking are enabled so every event ties back to a specific container, pod, and user.
- Tetragon writes JSON events to `/var/run/cilium/tetragon/tetragon.log` which Fluent Bit tails and ships to Splunk.

### 3. Secrets isolation (Layer 3 — Key Vault + CSI)

**No secrets in code, environment variables, ConfigMaps, or images.**

- API keys (Claude), HEC tokens (Splunk), and Cloudflare tunnel credentials live in Azure Key Vault.
- Pods access them through the **Azure Key Vault Provider for Secret Store CSI Driver** — secrets mount as a volume at `/mnt/secrets/`.
- Authentication uses **System-Assigned Managed Identity** on the AKS cluster. No service principal passwords. No static credentials.
- Key Vault enforces `default_action = "Deny"` at the network level: only the operator's IP and the AKS node subnet can reach it. Soft-delete + purge protection are on.

### 4. Observability and audit (Layer 7 — Splunk)

Everything security-relevant converges in a **single pane of glass**.

- **Fluent Bit** runs as a DaemonSet and ships Tetragon's JSON event stream to Splunk HEC.
- **OpenTelemetry Collector** scrapes Tetragon's Prometheus metrics on port 2112 and forwards them.
- Splunk lives on its own Ubuntu VM in the same VNet (L3 reachable from AKS on port 8088 via the `aks-nodes` subnet CIDR).
- Public access to the Splunk UI is via its own Cloudflare Tunnel — same email-gated access as the chatbot.

### 5. The infrastructure picture

```
   [ Splunk VM on Ubuntu 22.04 ]
          ▲         ▲
          │ 8088    │ cloudflared tunnel (outbound)
          │ HEC     │
   ┌──────┴─────────┴──────────────────┐
   │  AKS (Cilium data plane)          │
   │                                   │
   │  ┌──────────────────────────┐     │
   │  │ Tetragon DaemonSet       │◄───────── Layer 2 (runtime)
   │  │ (every node, kernel)     │     │
   │  └──────────────────────────┘     │
   │                                   │
   │  ┌──────────────────────────┐     │
   │  │ CiliumNetworkPolicy      │◄───────── Layer 1 (network)
   │  │ default-deny everywhere  │     │
   │  └──────────────────────────┘     │
   │                                   │
   │  ┌──────────────────────────┐     │
   │  │ App pods mount KV secrets│◄───────── Layer 3 (secrets)
   │  │ via CSI + Managed Ident. │     │
   │  └──────────────────────────┘     │
   └───────────────────────────────────┘
                   │
                   │ Fluent Bit + OTel
                   ▼
        [ Splunk audit trail — Layer 7 ]
```

---

## 👩‍💻 Developer workflow security

The third domain protects the build and deploy pipeline itself. A compromised CI/CD system can ship arbitrary code to production — so it gets the same defense-in-depth treatment.

### 1. AI supply chain integrity (Layer 5 — Cisco AI Defense)

AI projects have a unique threat: poisoned models, poisoned retrieval corpora, or malicious AI-generated code. Three independent tools guard against this:

- **AIBOM** (AI Bill of Materials): runs on every pull request in CI. Inventories every AI component, dependency, model version, and data source. Produces a machine-readable manifest. A PR that introduces an unknown AI dependency is blocked.
- **Adversarial Hubness Detector**: runs when knowledge-base PDFs change. Detects RAG poisoning attempts — documents engineered to skew retrieval results toward attacker-preferred content. A PR that modifies a PDF without passing integrity checks is blocked.
- **IDE AI Security Scanner**: runs locally in VS Code. Scans AI-related code patterns for prompt-injection risks, insecure API usage, and common anti-patterns before the code is even committed.

### 2. CI/CD gates (Layer 6 — GitHub Actions)

Four workflows enforce security at every code push:

| Workflow | Purpose |
|---|---|
| `quality.yaml` | Runs pytest, vitest, ruff, black, mypy, tsc, eslint, prettier, gitleaks, tfsec on every PR. Fails close. |
| `docker-build.yaml` | Builds React + FastAPI images, pushes to GitHub Container Registry. No images from untrusted registries. |
| `deploy.yaml` | Uses `azure/aks-set-context` + `kubectl apply`. No direct cluster access outside CI. |
| `aibom.yaml` | Cisco AIBOM scan — blocks PRs that break the AI supply chain. |
| `hubness-scan.yaml` | Cisco Hubness Detector — blocks PRs that modify PDFs without passing integrity checks. |

Webex notifications fire on every build (pass or fail) so the team sees CI state in real time.

### 3. Pre-commit guardrails (local, fast)

Three **independent layers** of secret + quality enforcement:

| Layer | Where | What runs |
|---|---|---|
| 1 — Local pre-commit hook | Developer's laptop | gitleaks (with custom Azure subscription/tenant-ID rules), tfsec, ruff, black, private-key detection, YAML/JSON syntax, large-file block |
| 2 — GitHub Actions `quality.yaml` | CI on every PR + push to main | Everything above, plus pytest, vitest, mypy, eslint, prettier, tsc |
| 3 — GitHub Secret Protection | Server-side, before push succeeds | Vendor-maintained secret patterns, push-block enforcement |

Any one of them is enough to catch a typical mistake. All three together make the class of "I accidentally committed a secret" nearly impossible.

---

## 🧑‍🔬 Development strategy

### Spec-driven workflow

**No code before an approved spec.** Every new feature gets a spec in `docs/specs/` before implementation starts. Specs follow a 9-section format (title, context, functional requirements with RFC 2119 keywords, non-functional requirements with measurable thresholds, acceptance criteria in Given/When/Then, edge cases, API contracts, data models, explicit out-of-scope).

Current specs:
- [`docs/specs/chatbot-v1.md`](docs/specs/chatbot-v1.md) — application layer
- [`docs/specs/infra-v1.md`](docs/specs/infra-v1.md) — Terraform / Azure
- [`docs/specs/cloudflare-access-v1.md`](docs/specs/cloudflare-access-v1.md) — Layer 8 edge

### Skill-driven implementation

Every code change is driven by a matching skill from the `engineering-skills` and `engineering-advanced-skills` Claude Code plugins. The full table lives in `CLAUDE.md`, but examples:

| Layer of work | Skill(s) invoked |
|---|---|
| Terraform / Azure | `terraform-patterns`, `azure-cloud-architect`, `cloud-security`, `senior-secops` |
| Python backend | `senior-backend`, `rag-architect` |
| React frontend | `senior-frontend` |
| Docker images | `docker-development` |
| Kubernetes manifests | `senior-secops`, `helm-chart-builder`, `secrets-vault-manager` |
| Debugging | `focused-fix` |
| Testing | `tdd-guide`, `senior-qa`, `api-test-suite-builder` |
| Reviews | `code-reviewer`, `adversarial-reviewer`, `senior-security` |

Skills aren't executable — they're expert playbooks loaded into the assistant's context before writing code. This keeps the implementation aligned with best practices instead of improvised defaults.

### Conventions

- **Commit hygiene**: one logical change per commit. Descriptive messages. Never mix unrelated changes.
- **Code simplicity**: every file should read like it was written for a college freshman. Short functions (≤30 lines), clear names, comments that explain *why* not *what*.
- **Pinned dependencies everywhere**: exact versions for Python packages, npm packages, Terraform providers, Helm charts, container base images. No `latest` tags in production.
- **No hardcoded anything**: IDs, keys, URLs, cluster names — everything parameterized or read from environment/state.

---

## 🧪 Testing strategy

Tests are a first-class part of the security story. **No new function ships without tests.**

### Testing tools

| Surface | Lint | Format | Types | Tests |
|---|---|---|---|---|
| Python (`app/`) | `ruff` | `black` | `mypy` | `pytest` |
| TypeScript (`frontend/`) | `eslint` | `prettier` | `tsc --noEmit` | `vitest` + `@testing-library/react` |

All configs are committed (`app/pyproject.toml`, `frontend/eslint.config.js`, `frontend/vitest.config.ts`, `frontend/.prettierrc`). Running `pre-commit run --all-files` or `npm run test` reproduces exactly what CI runs.

### Testing layers

1. **Unit tests** — fast, offline, external dependencies mocked. Example: the RAG splitter is tested against a long document with no embedding model running.
2. **Contract tests** — validate API shape. Example: `/api/health` must return `{status, index_ready, llm_ready}` with the right types in all states.
3. **Component tests** (React) — render a component, drive it with `@testing-library/user-event`, assert on what the user sees.

### Test-driven discipline

Following `tdd-guide`: red → green → refactor. When a bug is filed, the first commit reproduces it as a failing test, and the fix commit turns it green. When a new feature is specced, test stubs are generated from the acceptance criteria before implementation starts.

### Coverage philosophy

Not chasing a percentage. Every **acceptance criterion** in a spec maps to at least one passing test. Every **edge case** has a test. Every **error response defined in an API contract** has a test that triggers it. If it's documented, it's tested.

### Test locations

```
app/tests/                               # pytest lives here
├── conftest.py                          # shared fixtures
├── test_health.py                       # /api/health + /api/chat integration
├── test_personality.py                  # system prompt sanity
└── test_rag.py                          # chunk / split helpers

frontend/src/components/__tests__/       # vitest lives here
└── ChatWindow.test.tsx                  # one real component flow
```

---

## 🔄 How the domains reinforce each other

The three domains aren't isolated — they reinforce each other:

| Attack scenario | First layer to fire | Second layer | Third layer |
|---|---|---|---|
| Attacker gets a valid cisco.com email and tries to exploit an API bug | Cloudflare Access lets them in; Caddy security headers + FastAPI validation reject the malformed payload | Tetragon sees the unexpected process spawn and kills it | Splunk logs the event; alert fires |
| Developer accidentally commits an Anthropic key | Pre-commit gitleaks hook blocks the commit locally | If bypassed, `quality.yaml` CI blocks the push | GitHub Secret Protection blocks the push server-side |
| Malicious PDF is added to the knowledge base | Cisco Hubness Detector blocks the PR in CI | Even if it lands, Tetragon sees the retrieval pattern | Splunk surfaces the anomaly |
| A pod tries to reach an unapproved external IP | Cilium `CiliumNetworkPolicy` denies the connection | Tetragon logs the attempted egress | Splunk audit shows the policy violation |
| State backend credentials leak | Role assignment scoped to single storage account; state is encrypted at rest | `use_azuread_auth = true` means no shared keys to leak | Azure blob versioning + 14-day soft-delete lets us recover |

No single failure cascades. That's the whole point.

---

## 🗂️ Where each piece lives in the repo

```
money-honey/
├── app/                           # FastAPI backend + pytest tests
├── frontend/                      # React + TypeScript + vitest
├── infra/
│   ├── terraform-bootstrap/       # RG + state SA (local state)
│   ├── terraform/                 # Main stack (remote state)
│   └── scripts/                   # tf wrappers + install-splunk.sh
├── k8s/                           # Kubernetes manifests (step 4)
├── splunk/                        # Splunk setup notes
├── docs/
│   ├── specs/                     # Specs: chatbot, infra, cloudflare-access
│   └── architecture/              # Detailed layer deep-dives (Jekyll site)
├── .github/workflows/
│   └── quality.yaml               # pytest + vitest + lint + scan
├── .pre-commit-config.yaml        # local quality hook
├── .gitleaks.toml                 # custom Azure ID rules
├── CLAUDE.md                      # architecture rules + skill table
├── ARCHITECTURE.md                # this document
└── README.md                      # public-facing overview
```

---

## 🧭 Where we are in the build

See `README.md` for the step-by-step progress table. At a glance:

- Steps 1–3 (scaffold, app layer, Terraform infra) are code-complete.
- Step 4 (Kubernetes manifests) is the active work.
- Step 5 (CI/CD workflows beyond quality) and step 6 (docs site) follow.
