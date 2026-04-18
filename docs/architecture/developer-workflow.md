---
layout: default
title: Developer Workflow Security
---

# 👩‍💻 Developer workflow security (Layer 6)

A compromised CI/CD system can ship arbitrary code to production. The third domain protects the path from a developer's laptop to the running cluster with the same layering philosophy as the runtime itself.

## Three lines of defense for secrets

A secret committed to Git is a secret in the wild. One layer can miss it. Three layers, operating independently, make "I accidentally committed a secret" nearly impossible.

| Layer | Where | Tool |
|---|---|---|
| 1 | Developer's machine | `.pre-commit-config.yaml`: gitleaks (with Azure-specific rules in `.gitleaks.toml`), tfsec, black, ruff, private-key detection |
| 2 | CI on every PR + push | `.github/workflows/quality.yaml`: pytest, vitest, mypy, ruff, black, tsc, eslint, prettier, plus gitleaks + tfsec again |
| 3 | GitHub server side | Secret Protection with Push Protection: vendor-maintained patterns, blocks pushes at the wire |

## Four deploy-time workflows

| Workflow | Trigger | Purpose |
|---|---|---|
| [`docker-build.yaml`](https://github.com/itsAmeMario0o/money-honey/blob/main/.github/workflows/docker-build.yaml) | Push/PR to `app/` or `frontend/` | Build + push images to GHCR, tagged with commit SHA + `:latest` on main |
| [`deploy.yaml`](https://github.com/itsAmeMario0o/money-honey/blob/main/.github/workflows/deploy.yaml) | Push to `main` affecting k8s app manifests | `azure/login` (OIDC, no client secrets) + `aks-set-context` + `kubectl apply` |
| [`aibom.yaml`](https://github.com/itsAmeMario0o/money-honey/blob/main/.github/workflows/aibom.yaml) | PR affecting `app/` or `frontend/` | Cisco AIBOM scan, blocks on untracked AI deps |
| [`hubness-scan.yaml`](https://github.com/itsAmeMario0o/money-honey/blob/main/.github/workflows/hubness-scan.yaml) | PR affecting `app/knowledge_base/` | Cisco Hubness Detector for RAG poisoning |

Each posts to Webex on completion, pass or fail.

## Scope deliberately limited

`deploy.yaml` applies only `k8s/app/`, `k8s/frontend/`, `k8s/caddy/`. Network policies, tracing policies, SecretProviderClass, Fluent Bit, OTel, and cloudflared are operator-controlled. Changes there require explicit human review, not a merge-to-main.

CI stays fast (no large rollouts on every commit), and the security controls are harder to weaken through an accidental PR.

## Spec-driven discipline

Every non-trivial feature lives at `docs/specs/<feature>-vN.md` before any code is written. The spec has 9 mandatory sections: context, FRs with RFC 2119 keywords, NFRs with measurable thresholds, ACs in Given/When/Then, edge cases, API contracts, data models, explicit out-of-scope, and a self-review checklist. Skills from the `engineering-skills` and `engineering-advanced-skills` plugins drive implementation. No freeform code.
