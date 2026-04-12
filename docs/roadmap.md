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

## 🔮 v2 — post-launch hardening

Deferred on purpose from v1 — each is a clean follow-on project.

### Infrastructure

- **ArgoCD / Flux** for GitOps-style continuous delivery (replaces the `kubectl apply` step in `deploy.yaml`). Adds drift detection and rollback workflows.
- **ACNS (Azure Container Networking Services)** subscription — unlocks Hubble flow visibility, FQDN-based network policies, L7 (HTTP / gRPC) policies. About $30/mo at our cluster size.
- **Isovalent Enterprise** via Azure Marketplace — BGP peering, tetragon enterprise features, Hubble UI. Consider only if we go production-adjacent.
- **Private AKS cluster** — API server moves to a private endpoint only reachable through VNet peering or Express Route. Raises the bar for attacker API access.
- **Azure Bastion or Cloudflare SSH tunnel** — eliminate the Splunk VM's public IP entirely (currently kept for SSH admin).

### AI / LLM

- **LLM evaluation harness** — regression-test retrieval quality and voice adherence as the corpus or system prompt evolves.
- **Prompt injection test suite** — red-team prompts baked into CI via a dedicated workflow.
- **Per-session rate limiting** at the FastAPI layer (currently none; only cost protection is the Anthropic $20 cap).
- **Citation rendering in the UI** — show which PDF sourced each answer.
- **Multi-language support** — English-only in v1.
- **Hybrid search** (BM25 + vector) — if corpus grows past ~50 docs.
- **Persisted FAISS index** on an Azure File share — skip the rebuild on pod restart.

### Developer workflow

- **cosign** image signing + `policy-controller` verification on AKS admission.
- **OPA Gatekeeper or Kyverno** mutating/validating admission webhooks — enforce resource-request presence, label conventions, etc.
- **Dependabot or Renovate** for automated dependency PRs (complements Trivy's detection with automated remediation).
- **LLM cost tracking** dashboard in Splunk — per-request Anthropic spend, surfaced as a panel.
- **Formal secrets rotation** workflow — currently all secret updates are manual `az keyvault secret set`.

### Operational

- **Runbooks** in `docs/runbooks/` for incident response (cluster down, tunnel broken, KV lockout, etc.).
- **Smoke tests post-deploy** in `deploy.yaml` — hit `/api/health`, `/api/chat`, the public Cloudflare URL.
- **Synthetic monitoring** from an external location (Pingdom / Datadog Synthetics / Splunk Synthetics).
- **Disaster recovery plan** — currently the demo is stateless enough that "rebuild from code in 15 minutes" is the strategy. v2 would formalise this as a test we actually run.

## 🎯 What we're NOT building

Things explicitly out of scope even for v2 unless requirements change:

- Multi-tenant support / user accounts / PII handling
- Real user authentication (Cloudflare Access is enough for a demo; a full SSO integration isn't on the roadmap)
- SOC 2 / HIPAA compliance evidence — that's a different project scope
- Selling this as a product
