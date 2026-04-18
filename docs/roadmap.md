---
layout: default
title: Roadmap
---

# 🗺️ Roadmap

## ✅ v1 scope (building now)

Everything in [`CLAUDE.md`](https://github.com/itsAmeMario0o/money-honey/blob/main/CLAUDE.md) under "Security Architecture: Three Domains, Eight Layers," plus CI/CD and quality tooling:

- Cilium network identity + Tetragon runtime enforcement on AKS
- Azure Key Vault with CSI-mounted secrets, managed identity
- Caddy ClusterIP reverse proxy inside the cluster
- Cisco AI Defense gates in CI (AIBOM + Hubness Detector + IDE scanner)
- CoSAI / OASIS **CodeGuard** Claude Code plugin — agent-side secure-coding rules during generation
- Demo workflow scaffolding under `app/tests/demos/`. First demo (CodeGuard path-traversal) landed; more per-layer demos to come
- GitHub Actions: `quality`, `docker-build`, `deploy`, `aibom`, `hubness-scan`
- Splunk Enterprise Free on a dedicated Ubuntu VM
- Fluent Bit + OpenTelemetry pipelines into Splunk
- Cloudflare Tunnel + Zero Trust (Free tier) as the public edge
- Trivy image scan (blocking), filesystem dep scan (blocking), k8s manifest scan (advisory)
- Pre-commit hook: gitleaks, tfsec, black, ruff, YAML/JSON check
- GitHub Secret Protection + Push Protection

## 🚧 v1 finishing tasks (the last mile)

- Operator: set Azure SP + 3 GitHub secrets (`docs/setup/azure-sp-for-ci.md`)
- Operator: install Splunk on the VM (`docs/setup/splunk.md`)
- Operator: populate Key Vault secrets (`docs/setup/kv-secrets.md`)
- Operator: configure Cloudflare Public Hostnames once tunnels show HEALTHY
- Enable GitHub Pages (Settings → Pages → Source `main` / `/docs`)
- Flip `trivy-k8s` job from advisory to required once a baseline pass clean

## 🔮 v2: post-launch hardening

Deferred on purpose. Each item is a clean follow-on project.

### Infrastructure

- ArgoCD / Flux for GitOps continuous delivery (replaces the `kubectl apply` step in `deploy.yaml`). Adds drift detection and rollback workflows.
- ACNS (Azure Container Networking Services) subscription. Unlocks Hubble flow visibility, FQDN-based network policies, and L7 (HTTP / gRPC) policies. About $30/mo at this cluster size.
- Isovalent Enterprise via Azure Marketplace. BGP peering, Tetragon enterprise features, Hubble UI. Consider only if the project goes production-adjacent.
- Private AKS cluster. The API server moves to a private endpoint reachable only through VNet peering or ExpressRoute. Raises the bar for attacker API access.
- Azure Bastion or Cloudflare SSH tunnel. Eliminates the Splunk VM's public IP entirely (currently kept for SSH admin).

### AI / LLM

- LLM evaluation harness. Regression-test retrieval quality and voice adherence as the corpus or system prompt evolves.
- Agentic Tier 3: autonomous planning agent. Multi-step financial plans, persistent memory (user profiles encrypted at rest), multi-agent architecture (planner delegates to debt/investing/budgeting specialists). This is the "9 Rings of Defense" scenario where the full security stack matters, because the agent decides what to do next. Spec the design before building; Tiers 1+2 must be live first. See [`docs/specs/agentic-v1.md`](specs/agentic-v1.html) for the Tier 1+2 spec.
- Prompt injection test suite. Red-team prompts baked into CI via a dedicated workflow.
- Per-session rate limiting at the FastAPI layer (currently none; only cost protection is the Anthropic $20 cap).
- Citation rendering in the UI. Show which PDF sourced each answer.
- Multi-language support. English-only in v1.
- Hybrid search (BM25 + vector) if the corpus grows past ~50 docs.
- Persisted FAISS index on an Azure File share. Skips the rebuild on pod restart.
- Bump fastapi 0.115.0 to 0.116+ so the starlette pin can move to 0.40.0+ and clear CVE-2024-47874 in `.trivyignore.yaml`. Currently safe because only JSON endpoints are exposed (no multipart parser invoked), but the dependency refresh is overdue.
- Migrate langchain 0.3.x to 1.x. Currently pinned to 0.3.27 because the sub-packages cohere there. langchain-core 1.2.22 fixes CVE-2026-34070 (path traversal in legacy `load_prompt`). The project is not exposed (it does not call the function; see `.trivyignore.yaml` rationale), but a clean migration eliminates the ignore and lands on a maintained line. Major-version bump means breaking API changes; budget a real iteration.

### Observability

- OTel `token_file:` refactor. Replace the `token: ${SPLUNK_HEC_TOKEN}` env-var substitution in `k8s/otel/configmap.yaml` with `token_file:` pointing at a CSI-mounted path. The token never sits in a Pod env or K8s Secret object; it only exists as a file mounted from Key Vault. Lets you delete the `.trivyignore.yaml` entry for `AVD-KSV-0109`. Requires either moving OTel into the `money-honey` namespace or duplicating the `SecretProviderClass` in `kube-system`.
- Splunk dashboards as code. Ship `splunk/dashboards/*.xml` (or JSON) defining the views that matter: Tetragon events per minute, policy violations by pod, egress allowlist hits, AIBOM classifier runs, HEC ingest rate vs. 500 MB/day quota. Definitions can be written now; they apply once Splunk has real event flow.

### Developer workflow

- cosign image signing + `policy-controller` verification on AKS admission.
- OPA Gatekeeper or Kyverno mutating/validating admission webhooks. Enforce resource-request presence, label conventions, etc.
- Dependabot or Renovate for automated dependency PRs (complements Trivy's detection with automated remediation).
- LLM cost tracking dashboard in Splunk. Per-request Anthropic spend, surfaced as a panel.
- Formal secrets rotation workflow. Currently all secret updates are manual `az keyvault secret set`.

### Operational

- Runbooks in `docs/runbooks/` for incident response (cluster down, tunnel broken, KV lockout, etc.).
- Webex webhook alerts from Splunk. A saved-search alert POSTs to `https://webexapis.com/v1/messages` when Tetragon logs a SIGKILL or policy violation. Reuses the same bot token + room ID as GitHub CI notifications.
- Webex webhook alerts from Cloudflare. Cloudflare Notifications (dashboard, Notifications, Create) can fire on tunnel health changes (DEGRADED/DOWN). Target a webhook that relays to the Webex messages API. Wire up after Cloudflare tunnels are live.
- ChatOps via the Webex bot. Make `money-honey-ci` interactive so it receives commands (`status`, `pods`, `deploy`, `splunk query`, `costs`, `help`) and responds in the space. Preferred architecture: Azure Function (Python, Consumption plan) as the webhook receiver. Webex POSTs events to the function; the function validates the webhook signature, parses the command, calls the appropriate API (GitHub, AKS, Splunk), and responds via the Webex messages API. Azure Front Door or API Management can front it with WAF + rate limiting. Function key + optional AAD auth restricts access. Satisfies the Cisco IT requirement of not directly exposing the bot. No Node.js frameworks (botkit is archived; webex-node-bot-framework is stale). Raw Webex webhooks + Python. Needs a spec at `docs/specs/chatops-v1.md` and Terraform for the Azure Function resource before implementation. Evaluated and rejected: webex-node-bot-framework (Node.js mismatch, 3 years stale), botkit (archived Sep 2024), Webex websocket mode (not production-recommended by Cisco). Once the Azure Function is live, upgrade CI notifications and ChatOps responses to Webex Adaptive Cards (Buttons & Cards API, https://developer.webex.com/messaging/docs/buttons-and-cards). Cards give color-coded status, collapsible sections, and action buttons ("Re-run build", "View logs"). Button clicks send `attachmentActions` webhooks back to the same Azure Function for handling.
- Smoke tests post-deploy in `deploy.yaml`. Hit `/api/health`, `/api/chat`, the public Cloudflare URL.
- Synthetic monitoring from an external location (Pingdom / Datadog Synthetics / Splunk Synthetics).
- Disaster recovery plan. The demo is currently stateless enough that "rebuild from code in 15 minutes" works. v2 would formalize that as a test you actually run.

## 🎯 Not building

Out of scope even for v2 unless requirements change:

- Multi-tenant support / user accounts / PII handling
- Full SSO integration (Cloudflare Access is enough for a demo)
- SOC 2 / HIPAA compliance evidence. Different project scope.
- Selling this as a product
