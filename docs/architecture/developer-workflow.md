---
layout: default
title: Developer Workflow Security
---

# 👩‍💻 Developer Workflow Security (Layer 6)

The third domain protects the path code takes from a developer's laptop to the running cluster. A compromised CI/CD system can ship arbitrary code to production, so it gets the same defense-in-depth treatment as the runtime.

## Three independent lines of defense for secrets

| Layer | Where | Tool |
|---|---|---|
| 1 | Developer's machine | `.pre-commit-config.yaml` — gitleaks (with Azure-specific rules in `.gitleaks.toml`), tfsec, black, ruff, private-key detection |
| 2 | CI on every PR + push | `.github/workflows/quality.yaml` — pytest, vitest, mypy, ruff, black, tsc, eslint, prettier, plus gitleaks + tfsec again |
| 3 | GitHub server side | Secret Protection with Push Protection — vendor-maintained patterns, blocks pushes at the wire |

Any one of them catches a typical mistake. All three together make "I accidentally committed a secret" nearly impossible.

## Four deploy-time workflows

| Workflow | Trigger | Purpose |
|---|---|---|
| [`docker-build.yaml`](https://github.com/itsAmeMario0o/money-honey/blob/main/.github/workflows/docker-build.yaml) | Push/PR to `app/` or `frontend/` | Build + push images to GHCR, tagged with commit SHA + `:latest` on main |
| [`deploy.yaml`](https://github.com/itsAmeMario0o/money-honey/blob/main/.github/workflows/deploy.yaml) | Push to `main` affecting k8s app manifests | `azure/login` (OIDC, no client secrets) + `aks-set-context` + `kubectl apply` |
| [`aibom.yaml`](https://github.com/itsAmeMario0o/money-honey/blob/main/.github/workflows/aibom.yaml) | PR affecting `app/` or `frontend/` | Cisco AIBOM scan, blocks on untracked AI deps |
| [`hubness-scan.yaml`](https://github.com/itsAmeMario0o/money-honey/blob/main/.github/workflows/hubness-scan.yaml) | PR affecting `app/knowledge_base/` | Cisco Hubness Detector for RAG poisoning |

Each posts to Webex on completion (pass or fail).

## Scope deliberately limited

`deploy.yaml` applies **only** `k8s/app/`, `k8s/frontend/`, `k8s/caddy/`. Network policies, tracing policies, SecretProviderClass, Fluent Bit, OTel, and cloudflared are operator-controlled — changes require explicit human review, not a merge-to-main.

This keeps CI fast (no large rollouts on every commit) and makes the security controls themselves harder to accidentally weaken through a PR.

## Spec-driven discipline

Every non-trivial feature lives at `docs/specs/<feature>-vN.md` before any code is written. The spec has 9 mandatory sections (context, FRs with RFC 2119 keywords, NFRs with measurable thresholds, ACs in Given/When/Then, edge cases, API contracts, data models, explicit out-of-scope, self-review checklist). Skills from the `engineering-skills` and `engineering-advanced-skills` plugins drive implementation — no freeform code.
