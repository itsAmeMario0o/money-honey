# 🤖 Spec: CI/CD Workflows v1

## 1. Title and Metadata

| Field | Value |
|---|---|
| **Feature** | GitHub Actions workflows for build, deploy, AI supply-chain scans, notifications |
| **Author** | Mario Ruiz + Claude Code |
| **Status** | 🚧 **In progress** — workflows written; `quality.yaml` already live; remaining 4 need repo secrets before they can run successfully |
| **Reviewers** | Mario Ruiz |
| **Skills used** | `spec-driven-workflow`, `ci-cd-pipeline-builder`, `docker-development`, `senior-secops` |
| **Depends on** | `docs/specs/infra-v1.md` (AKS cluster), `docs/specs/k8s-v1.md` (manifests to apply) |

---

## 2. Context

CLAUDE.md Layer 6 defines four CI/CD workflows that gate every code change before it reaches the cluster. `.github/workflows/quality.yaml` (from earlier work) already runs lint/tests/scans on every PR. This spec adds the four workflows that build images and deploy — plus Cisco AI Defense gates.

All workflows run on GitHub-hosted Ubuntu runners. No self-hosted runners in v1.

---

## 3. Functional Requirements (RFC 2119)

### `docker-build.yaml`

| ID | Requirement |
|---|---|
| **FR-1** | A workflow MUST build both `app/` (FastAPI backend) and `frontend/` (React SPA) Docker images on every push to `main` and every PR targeting `main`. |
| **FR-2** | Images MUST be pushed to GHCR at `ghcr.io/${{ github.repository_owner }}/money-honey-app` and `...money-honey-frontend`. |
| **FR-3** | Each image MUST be tagged with the commit SHA (`:sha-<short>`) AND `:latest` (on `main` branch pushes only). |
| **FR-4** | Authentication to GHCR MUST use the built-in `GITHUB_TOKEN` — no personal access tokens. |
| **FR-5** | Build cache MUST use GitHub Actions cache (`type=gha,mode=max`) to speed up repeated builds. |
| **FR-6** | On failure, a Webex notification MUST fire with the run URL. |

### `deploy.yaml`

| ID | Requirement |
|---|---|
| **FR-7** | The workflow MUST trigger on push to `main` only. |
| **FR-8** | Authentication to Azure MUST use OIDC federation (`azure/login@v2` with client-id + tenant-id + subscription-id inputs), no client secrets. |
| **FR-9** | The workflow MUST run `azure/aks-set-context@v4` to pull the kubeconfig, then `kubectl apply` the manifests in `k8s/app/`, `k8s/frontend/`, `k8s/caddy/`. |
| **FR-10** | The workflow MUST NOT apply network policies, tracing policies, SecretProviderClass, Fluent Bit, OTel, or cloudflared — those are operator-controlled changes requiring explicit human review. |
| **FR-11** | A Webex notification MUST fire on every run (pass or fail). |

### `aibom.yaml`

| ID | Requirement |
|---|---|
| **FR-12** | The workflow MUST run on every PR that touches `app/` or `frontend/`. |
| **FR-13** | It MUST generate a machine-readable AI Bill of Materials manifest. **Current implementation:** a CycloneDX SBOM via `anchore/sbom-action` (syft under the hood) for both `app/` and `frontend/`. Cisco's public AIBOM repo is a spec + JSON schema, not a runnable CLI; we stand in with CycloneDX SBOMs until a Cisco AIBOM CLI ships. |
| **FR-14** | A "highlight AI/ML components" step greps the SBOM for known AI/ML library names (`langchain`, `anthropic`, `sentence-transformers`, `faiss`, `transformers`, `huggingface`, `torch`, `numpy`) and surfaces them as a PR-visible summary. Hard blocking on "untracked AI component" is deferred to v2 once a baseline manifest is approved. |

### `hubness-scan.yaml`

| ID | Requirement |
|---|---|
| **FR-15** | The workflow MUST run on every PR that modifies anything under `app/knowledge_base/`. |
| **FR-16** | It MUST invoke Cisco's Adversarial Hubness Detector to scan new/changed PDFs. |
| **FR-17** | If a PDF fails integrity checks (poisoning score above threshold), the workflow MUST fail and block the PR. |

### Required repo secrets (operator sets)

| Secret | Used by | Purpose |
|---|---|---|
| `AZURE_CLIENT_ID` | `deploy.yaml` | OIDC client ID of the federated SP |
| `AZURE_TENANT_ID` | `deploy.yaml` | Tenant (already in `.gitleaks.toml` allowlist) |
| `AZURE_SUBSCRIPTION_ID` | `deploy.yaml` | Subscription to target |
| `WEBEX_BOT_TOKEN` | `docker-build.yaml`, `deploy.yaml` | Webex bot token |
| `WEBEX_ROOM_ID` | `docker-build.yaml`, `deploy.yaml` | Target room |

---

## 4. Non-Functional Requirements

| ID | Requirement | Threshold |
|---|---|---|
| **NFR-1** (security) | No workflow MAY use long-lived client secrets for Azure auth. OIDC only. | 0 `client_secret` references |
| **NFR-2** (security) | Every third-party action MUST be pinned to a specific commit SHA or a tagged release. No `@main` or `@latest`. | 100% pinned |
| **NFR-3** (performance) | A clean `docker-build` run SHOULD complete in under 8 minutes. | p50 < 8 min |
| **NFR-4** (safety) | `deploy.yaml` MUST NOT be triggerable on PRs — only on merge to `main`. | No PR trigger |
| **NFR-5** (observability) | Every workflow run MUST post to Webex on completion or failure. | 100% coverage |

---

## 5. Acceptance Criteria

| ID | Criterion | Refs |
|---|---|---|
| **AC-1** | **Given** a PR is opened, **When** CI runs, **Then** `docker-build.yaml` builds both images and `aibom.yaml` runs against `app/`. | FR-1, FR-12 |
| **AC-2** | **Given** a PR modifies `app/knowledge_base/`, **When** `hubness-scan.yaml` runs, **Then** either it passes or blocks merge. | FR-15, FR-17 |
| **AC-3** | **Given** a merge to `main`, **When** `deploy.yaml` runs, **Then** `kubectl apply -f k8s/app/ -f k8s/frontend/ -f k8s/caddy/` succeeds and the new pods become Ready within 5 minutes. | FR-7, FR-9 |
| **AC-4** | **Given** any workflow finishes, **When** it completes, **Then** Webex receives a notification. | FR-6, FR-11, NFR-5 |

---

## 6. Edge Cases

| ID | Scenario | Expected behavior |
|---|---|---|
| **EC-1** | GHCR rejects push (token expired / permission removed) | Workflow fails clearly; Webex posts failure with run URL |
| **EC-2** | AKS API unreachable (firewall rule blocks the runner IP) | `deploy.yaml` fails on `aks-set-context`. The runner IP list must be authorized on the cluster API access profile — covered in FR-11 of `infra-v1.md` spec update |
| **EC-3** | AIBOM detects a brand-new AI dependency legitimately added | Operator updates the AIBOM baseline + re-runs the workflow |
| **EC-4** | A PDF is changed and Hubness scanner times out | Workflow fails; operator inspects logs; scanner is stateless, safe to retry |

---

## 7. Out of Scope (v1)

- Blue/green or canary deploys — plain `kubectl apply` with rolling update.
- ArgoCD / Flux GitOps — deferred, CLAUDE.md §"Deferred to v2".
- Image signing (cosign) — v2.
- SBOM generation via syft — v2.
- PR comments with deployment preview URLs — v2.
