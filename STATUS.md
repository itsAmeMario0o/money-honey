# 📊 Current Build Status

Last updated 2026-04-21. Live docs at https://itsamemario0o.github.io/money-honey/.

The chatbot is live. Splunk is live. Both are reachable through Cloudflare tunnels with no public inbound ports on either origin.

- Chatbot: https://moneyhoney.rooez.com
- Splunk: https://splunk.rooez.com

## ✅ Azure resources live

| Resource | Status | Cost |
|---|---|---|
| AKS `money-honey-aks` (K8s 1.34, 3x `Standard_D2s_v3`, Cilium v1.18.6) | ✅ Running | ~$87/mo |
| Tetragon DaemonSet (kube-system, 3/3 pods) | ✅ Running | $0 |
| VNet `money-honey-vnet` + 2 subnets | ✅ | $0 |
| Key Vault `mh-kv-w8fxwb` | ✅ | <$1/mo |
| Splunk VM (Ubuntu 22.04, `Standard_B2ms`) + Splunk Enterprise Free installed | ✅ Running | ~$70/mo |
| Splunk public IP (SSH only; web/HEC internal) | ✅ | $3.60/mo |
| Terraform state SA `mhtfstatemjr26` | ✅ | <$1/mo |
| Azure federated Service Principal `money-honey-ci` (OIDC for CI) | ✅ | $0 |
| Azure Files (knowledge-base + hf-cache) | Standard LRS | <$0.01/mo |
| **Running total** | | **~$165/mo** |

## ✅ AKS workloads live

| Resource | Namespace | Status |
|---|---|---|
| CiliumNetworkPolicies (default-deny + 7 allows) | money-honey | 8 valid |
| TracingPolicies (exec allowlist, tcp_connect, secrets-file, network events, DNS tracking) | money-honey | 5 active |
| SecretProviderClass `money-honey-secrets` | money-honey | ✅ |
| SecretProviderClass `observability-secrets` | kube-system | ✅ |
| Fluent Bit DaemonSet (3/3, tailing Tetragon log, Splunk HEC delivery confirmed) | kube-system | ✅ flowing (event_index=main, sourcetype=tetragon:json) |
| OTel Collector Deployment (scraping Tetragon `:2112`) | kube-system | ✅ running |
| fastapi Deployment (3 GiB limit, 15 min startup probe) | money-honey | ✅ Running, answering questions |
| react Deployment | money-honey | ✅ Running |
| caddy Deployment | money-honey | ✅ Running, proxying /api/* and /* |
| cloudflared Deployment (chatbot tunnel) | money-honey | ✅ HEALTHY, metrics on 0.0.0.0:20241 |
| cloudflared systemd (Splunk tunnel) | Splunk VM | ✅ HEALTHY |

## 🔐 Key Vault secrets

| Secret | Status |
|---|---|
| `splunk-hec-token` | ✅ populated (real HEC UUID) |
| `anthropic-api-key` | ✅ populated |
| `cloudflare-tunnel-splunk-token` | ✅ populated |
| `cloudflare-tunnel-chatbot-token` | ✅ populated |

## 🤖 CI/CD state

| Workflow | Status |
|---|---|
| `quality.yaml` (pytest, vitest, ruff, black, mypy, eslint, prettier, gitleaks, tfsec, Trivy fs + k8s) | ✅ green. 19 pytest cases across /api/chat + /api/health + CORS. 3 demo suites (CodeGuard, Tetragon, trivyignore). Webex notification on failure only. |
| `docker-build.yaml` (build + Trivy image scan + push to GHCR) | ✅ green on both frontend and backend. Webex notification wired. |
| `deploy.yaml` (OIDC Azure login + kubelogin + kubectl apply, 15m fastapi rollout timeout) | ✅ green. Deploys all workloads. Webex notification wired. |
| `aibom.yaml` (Cisco AIBOM via uv tool install) | ⏳ iterating on cisco-aibom 0.5.2 CLI flags (kb download added, latest run pending). Webex notification wired. |
| `hubness-scan.yaml` (Cisco adversarial-hubness-detector) | ✅ wired to real `ahd scan` CLI. Triggers on `app/knowledge_base/**`. Advisory today; flip to blocking after first calibration run. Webex notification wired. |
| `pages-build-deployment` (GitHub-managed, builds Jekyll from /docs) | ✅ live. Auto-rebuilds on every push to `docs/`. |
| Webex bot (`money-honey-ci`) | ✅ bot created, token + room ID in GitHub secrets. All 5 workflows post to "Money Honey 💸🍯" space. |

## 🛡️ Repo security posture

- Branch protection on `main`: force-push blocked, deletion blocked
- GitHub Secret Protection + Push Protection: enabled
- Local pre-commit hook: gitleaks + tfsec + ruff + black (runs on every commit)
- `.trivyignore.yaml`: 3 scoped ignores. starlette DoS on fastapi 0.115 (no multipart parser exposed); langchain-core `load_prompt` we don't call; OTel AVD-KSV-0109 (Trivy pattern-matches the literal `token:` key name, but the value is an OTel `${file:...}` source-expansion pointing at the CSI mount, no secret in the ConfigMap).
- `.gitleaksignore`: 2 scoped ignores (tenant ID in SPC YAMLs)
- CoSAI CodeGuard plugin applied in every Claude Code session; secure-coding rules injected at generation time
- `.trivyignore.yaml` anti-amnesty guard in pytest: every entry must have `expiredAt` within 1 year (enforced by `app/tests/demos/trivy_ignore/`)
- Issue + PR templates added under `.github/` (bug, feature, security-non-sensitive); private vuln reporting enabled via GitHub Security tab
- All docs humanized via blader/humanizer skill (Option B: keep emojis, strip AI writing patterns)
- CLAUDE.md freshness audit complete (stale repo tree, workflow count, Tetragon path, OTel token all corrected)
- 3 per-layer demos under `app/tests/demos/`: CodeGuard path-traversal (10 tests), Tetragon TracingPolicy structure (4 tests), trivyignore anti-amnesty (4 tests)
- 4 ops runbooks under `docs/runbooks/`: KV rotation, Splunk recovery, tunnel outage, deploy rollback
- Splunk "Money Honey Security" dashboard with 8 panels (Dashboard Studio JSON at `splunk/dashboards/`)
- Cisco Security Cloud Splunk app v3.6.4 installed

---

## 🧹 Dependabot PR triage (manual close/merge recommended)

| # | What | Recommendation |
|---|---|---|
| #15 | langchain-anthropic range bump, likely 1.x | Close. Would break our 0.3.x langchain pin. |
| #16 | langchain-huggingface range bump, likely 1.x | Close. Same reason. |
| #13 | vite 5, 8 (major) | Review. Major jump; needs build test. |
| #18 | jsdom 25, 29 (major) | Review. Affects vitest test runner; needs test run. |
| #19 | azure/aks-set-context 4, 5 (major) | Review. Known to change inputs. |
| #21 | python-minor-patch group | Rebase onto current main (our fixes make this pass). |
| #17 | react + @types/react | Review, check compat with React 18 choices. |
| #14 | pytest-asyncio 0.25, 1.3 (major) | Review, might need test adjustments. |
| #12 | pypdf 5.1, 6.10 (major) | Review, API changes possible. |
| #10 | eslint-plugin-react-hooks 5.1, ? | Likely safe. Merge if CI green. |

After closing #15 and #16, the rest will clear naturally as they either pass CI or expire. Open list: https://github.com/itsAmeMario0o/money-honey/pulls

---

## 🧭 What's next, ordered

### Phase 1 ✅ COMPLETE, chatbot unblocked

All four steps done. Anthropic key in Key Vault. Images in GHCR. deploy.yaml green. Chat path tested end-to-end through Caddy.

### Phase 2 ✅ COMPLETE, public access via Cloudflare

All five steps done. Both tunnel tokens in Key Vault. cloudflared running on the Splunk VM (systemd) and inside AKS (Deployment). Published application routes configured. rooez.com DNS moved from Squarespace to Cloudflare nameservers.

### Phase 3, polish + hardening (in progress)

1. **AIBOM workflow**: iterating on cisco-aibom 0.5.2 CLI flags. kb download added, latest run pending.
2. **Zero Trust Access policies**: both tunnels currently open. Attach email-domain allowlists (`*@cisco.com`, `*@gmail.com`).
3. **Tighten branch protection**: require passing status checks (`Quality`, `Docker Build`, `Deploy`) on `main`.
4. **Flip advisory gates to blocking**: `trivy-k8s` job, `aibom.yaml`, `hubness-scan.yaml`.
5. **Tetragon index investigation**: events only deliver to `main`, not to a dedicated `tetragon` index. HEC token was updated but events didn't flow. Root cause unknown, reverted to `main`.
6. **Tier 2 agentic tools**: compound_interest, debt_payoff, budget_breakdown, tax_bracket calculators for the chatbot.
7. **v1.1 backlog** in `docs/roadmap.md`: CSI cross-namespace architecture cleanup. _(OTel token refactor and Tetragon exportFilename simplification landed 2026-04-13. CLAUDE.md freshness audit landed 2026-04-16. Humanizer pass landed 2026-04-14. Notebooks/ removed 2026-04-16.)_

---

## 🩺 Known quirks (for my own memory)

- Tetragon log lives at `/var/run/cilium/tetragon/tetragon.log` on each node. `exportFilename` in tetragon.tf is now just the filename (not a full path) so the Helm chart produces a clean directory layout.
- Fluent Bit runs as uid 0 because Tetragon writes the log as root and hostPath doesn't honor fsGroup. Still read-only rootfs + all caps dropped + no privesc.
- Fluent Bit `Read_from_Head` only applies when no DB entry exists for the file. If you change configs and want to re-read, delete the DB file or remove the DB directive entirely.
- Fluent Bit `event_index=tetragon` did not deliver despite creating the index and updating the HEC token. Root cause unknown. Reverted to `event_index=main`.
- CodeGuard (OASIS/CoSAI) plugin added to the CLAUDE.md skills section on 2026-04-14. Operator runs `/plugin marketplace add cosai-oasis/project-codeguard` + `/plugin install codeguard-security@project-codeguard` once per machine, no repo artifact required.
- GitHub Pages source is `/docs`, so Jekyll only processes files under that path. Theme overrides live at `docs/assets/css/style.scss` and `docs/_includes/head_custom.html`, NOT at the repo root, where Jekyll would silently ignore them.
- Caddy needs `CAP_NET_BIND_SERVICE` to bind port 80 as uid 1000.
- AKS API server is public (no IP allowlist), AAD + RBAC is the gate. V2 path: private cluster + self-hosted runners.
- `local_account_disabled = false` on AKS so Terraform's Helm provider can auth via `kube_admin_config`. Kubelogin+exec is the v2 hardening.
- Helm `set` blocks in Terraform cannot handle commas or JSON values. Use `values` with `yamlencode` instead.
- Tetragon Helm release timeout exceeded multiple times during apply. Bumped to 600s, eventually had to import state after context-deadline-exceeded errors.
- Cisco Security Cloud Splunk app expects Hubble Enterprise fluentd exporter, not raw Fluent Bit. It looks for `cisco:isovalent*` sourcetypes, but we send `tetragon:json`. The app installed cleanly but its pre-built dashboards will not populate until we bridge the sourcetype gap (or ACNS/Isovalent lands in v2).
- rooez.com DNS is on Cloudflare nameservers (moved from Squarespace). Domain registration stays at Squarespace.
- cloudflared metrics must bind to `0.0.0.0:20241` (not localhost) for Kubernetes probes to reach the `/ready` endpoint.
- 4 PDFs in the knowledge base (personalfinancefordummies.pdf added as the 4th).
