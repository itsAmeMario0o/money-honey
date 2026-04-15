---
layout: default
title: Roadmap
---

# 🗺️ Roadmap

## ✅ v1 scope (what we're building now)

Everything listed in [`CLAUDE.md`](https://github.com/itsAmeMario0o/money-honey/blob/main/CLAUDE.md) §"Security Architecture: Three Domains, Eight Layers" plus the CI/CD + quality tooling:

- Cilium network identity + Tetragon runtime enforcement on AKS
- Azure Key Vault with CSI-mounted secrets, managed identity
- Caddy ClusterIP reverse proxy inside the cluster
- Cisco AI Defense gates in CI (AIBOM + Hubness Detector + IDE scanner)
- CoSAI / OASIS **CodeGuard** Claude Code plugin — agent-side secure-coding rules during generation
- Demo workflow scaffolding under `app/tests/demos/` — first demo (CodeGuard path-traversal) landed; more per-layer demos to come
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

Deferred on purpose from v1. Each is a clean follow-on project.

### Infrastructure

- ArgoCD / Flux for GitOps-style continuous delivery (replaces the `kubectl apply` step in `deploy.yaml`). Adds drift detection and rollback workflows.
- ACNS (Azure Container Networking Services) subscription. Unlocks Hubble flow visibility, FQDN-based network policies, and L7 (HTTP / gRPC) policies. About $30/mo at our cluster size.
- Isovalent Enterprise via Azure Marketplace. BGP peering, Tetragon enterprise features, Hubble UI. Consider only if we go production-adjacent.
- Private AKS cluster. API server moves to a private endpoint only reachable through VNet peering or Express Route. Raises the bar for attacker API access.
- Azure Bastion or Cloudflare SSH tunnel. Eliminate the Splunk VM's public IP entirely (currently kept for SSH admin).

### AI / LLM

- LLM evaluation harness. Regression-test retrieval quality and voice adherence as the corpus or system prompt evolves.
- Prompt injection test suite. Red-team prompts baked into CI via a dedicated workflow.
- Per-session rate limiting at the FastAPI layer (currently none; only cost protection is the Anthropic $20 cap).
- Citation rendering in the UI. Show which PDF sourced each answer.
- Multi-language support. English-only in v1.
- Hybrid search (BM25 + vector) if the corpus grows past ~50 docs.
- Persisted FAISS index on an Azure File share. Skip the rebuild on pod restart.
- Bump fastapi 0.115.0 → 0.116+ so the starlette pin can move to 0.40.0+ and clear CVE-2024-47874 in `.trivyignore.yaml`. Currently safe because we expose JSON-only endpoints (no multipart parser invoked), but the dependency-tree refresh is overdue.
- Migrate langchain 0.3.x → 1.x. Currently pinned to 0.3.27 because the sub-packages cohere there. langchain-core 1.2.22 fixes CVE-2026-34070 (path traversal in legacy `load_prompt`). We're not exposed (we don't call the function; see `.trivyignore.yaml` rationale), but a clean migration eliminates the ignore and gets us on a maintained line. Major-version bump means breaking API changes; budget a real iteration.

### Observability

- OTel `token_file:` refactor. Replace the `token: ${SPLUNK_HEC_TOKEN}` env-var substitution in `k8s/otel/configmap.yaml` with `token_file:` pointing at a CSI-mounted path. Removes the env-var / K8s-Secret hop entirely (the token never sits in a Pod env or K8s Secret object; it only exists as a file mounted from Key Vault). Lets us delete the `.trivyignore.yaml` entry for `AVD-KSV-0109`. Requires either moving OTel into the `money-honey` namespace or duplicating the `SecretProviderClass` in `kube-system`.

### Developer workflow

- cosign image signing + `policy-controller` verification on AKS admission.
- OPA Gatekeeper or Kyverno mutating/validating admission webhooks. Enforce resource-request presence, label conventions, etc.
- Dependabot or Renovate for automated dependency PRs (complements Trivy's detection with automated remediation).
- LLM cost tracking dashboard in Splunk. Per-request Anthropic spend, surfaced as a panel.
- Formal secrets rotation workflow. Currently all secret updates are manual `az keyvault secret set`.

### Operational

- Runbooks in `docs/runbooks/` for incident response (cluster down, tunnel broken, KV lockout, etc.).
- Smoke tests post-deploy in `deploy.yaml`. Hit `/api/health`, `/api/chat`, the public Cloudflare URL.
- Synthetic monitoring from an external location (Pingdom / Datadog Synthetics / Splunk Synthetics).
- Disaster recovery plan. Currently the demo is stateless enough that "rebuild from code in 15 minutes" is the strategy. v2 would formalise this as a test we actually run.

## 🎯 What we're NOT building

Things explicitly out of scope even for v2 unless requirements change:

- Multi-tenant support / user accounts / PII handling
- Real user authentication (Cloudflare Access is enough for a demo; a full SSO integration isn't on the roadmap)
- SOC 2 / HIPAA compliance evidence. That's a different project scope.
- Selling this as a product
