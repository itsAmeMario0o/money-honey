# 📊 Current Build Status

Last updated 2026-04-16. Live docs at https://itsamemario0o.github.io/money-honey/.

## ✅ Azure resources live

| Resource | Status | Cost |
|---|---|---|
| AKS `money-honey-aks` (K8s 1.34, 3× `Standard_B4ms`, Cilium v1.18.6) | ✅ Running | ~$120/mo |
| Tetragon DaemonSet (kube-system, 3/3 pods) | ✅ Running | $0 |
| VNet `money-honey-vnet` + 2 subnets | ✅ | $0 |
| Key Vault `mh-kv-w8fxwb` | ✅ | <$1/mo |
| Splunk VM (Ubuntu 22.04, `Standard_B2ms`) + Splunk Enterprise Free installed | ✅ Running | ~$70/mo |
| Splunk public IP (SSH only; web/HEC internal) | ✅ | $3.60/mo |
| Terraform state SA `mhtfstatemjr26` | ✅ | <$1/mo |
| Azure federated Service Principal `money-honey-ci` (OIDC for CI) | ✅ | $0 |
| Azure Files (knowledge-base + hf-cache) | Standard LRS | <$0.01/mo |
| **Running total** | | **~$200/mo** |

## ✅ AKS workloads live

| Resource | Namespace | Status |
|---|---|---|
| CiliumNetworkPolicies (default-deny + 7 allows) | money-honey | 8 valid |
| TracingPolicies (exec allowlist, tcp_connect audit, secrets-file audit) | money-honey | 3 valid |
| SecretProviderClass `money-honey-secrets` | money-honey | ✅ |
| SecretProviderClass `observability-secrets` | kube-system | ✅ |
| Fluent Bit DaemonSet (3/3, tailing Tetragon log, Splunk workers up) | kube-system | ✅ healthy, 0 events yet (TracingPolicies only emit on non-allowlisted exec) |
| OTel Collector Deployment (scraping Tetragon `:2112`) | kube-system | ✅ running |
| fastapi Deployment | money-honey | ⚠️ ImagePullBackOff — images not in GHCR yet |
| react Deployment | money-honey | ⚠️ ImagePullBackOff — same |
| caddy Deployment | money-honey | ⚠️ running 0/1 Ready (upstreams don't exist) |
| cloudflared Deployment | money-honey | ⏳ **not applied** — blocked on Cloudflare tunnel tokens |

## 🔐 Key Vault secrets

| Secret | Status |
|---|---|
| `splunk-hec-token` | ✅ **populated** (real HEC UUID) |
| `anthropic-api-key` | ⏳ placeholder (`set-me-in-portal`) |
| `cloudflare-tunnel-splunk-token` | ⏳ placeholder |
| `cloudflare-tunnel-chatbot-token` | ⏳ placeholder |

## 🤖 CI/CD state

| Workflow | Status |
|---|---|
| `quality.yaml` (pytest, vitest, ruff, black, mypy, eslint, prettier, gitleaks, tfsec, Trivy fs + k8s) | ✅ green. 19 pytest cases across /api/chat + /api/health + CORS. 3 demo suites (CodeGuard, Tetragon, trivyignore). Webex notification on failure only. |
| `docker-build.yaml` (build + Trivy image scan + push to GHCR) | ✅ green on frontend. Backend builds but image needs GHCR package flipped to public after first push. Webex notification wired. |
| `deploy.yaml` (OIDC Azure login + kubelogin + kubectl apply) | 🚧 SP verified; waits on images in GHCR. Webex notification wired. |
| `aibom.yaml` (Cisco AIBOM via uv tool install) | ⏳ blocked on `OPENAI_API_KEY` GitHub secret. Webex notification wired. |
| `hubness-scan.yaml` (Cisco adversarial-hubness-detector) | ✅ wired to real `ahd scan` CLI. Triggers on `app/knowledge_base/**`. Advisory today; flip to blocking after first calibration run. Webex notification wired. |
| `pages-build-deployment` (GitHub-managed, builds Jekyll from /docs) | ✅ live. Auto-rebuilds on every push to `docs/`. |
| Webex bot (`money-honey-ci`) | ✅ bot created, token + room ID in GitHub secrets. All 5 workflows post to "Money Honey 💸🍯" space. |

## 🛡️ Repo security posture

- Branch protection on `main`: force-push blocked, deletion blocked
- GitHub Secret Protection + Push Protection: enabled
- Local pre-commit hook: gitleaks + tfsec + ruff + black (runs on every commit)
- `.trivyignore.yaml`: 3 scoped ignores. starlette DoS on fastapi 0.115 (no multipart parser exposed); langchain-core `load_prompt` we don't call; OTel AVD-KSV-0109 (Trivy pattern-matches the literal `token:` key name, but the value is an OTel `${file:...}` source-expansion pointing at the CSI mount — no secret in the ConfigMap).
- `.gitleaksignore`: 2 scoped ignores (tenant ID in SPC YAMLs)
- CoSAI CodeGuard plugin applied in every Claude Code session; secure-coding rules injected at generation time
- `.trivyignore.yaml` anti-amnesty guard in pytest: every entry must have `expiredAt` within 1 year (enforced by `app/tests/demos/trivy_ignore/`)
- Issue + PR templates added under `.github/` (bug, feature, security-non-sensitive); private vuln reporting enabled via GitHub Security tab
- All docs humanized via blader/humanizer skill (Option B: keep emojis, strip AI writing patterns)
- CLAUDE.md freshness audit complete (stale repo tree, workflow count, Tetragon path, OTel token all corrected)
- 3 per-layer demos under `app/tests/demos/`: CodeGuard path-traversal (10 tests), Tetragon TracingPolicy structure (4 tests), trivyignore anti-amnesty (4 tests)
- 4 ops runbooks under `docs/runbooks/`: KV rotation, Splunk recovery, tunnel outage, deploy rollback

---

## 🧹 Dependabot PR triage (manual close/merge recommended)

| # | What | Recommendation |
|---|---|---|
| #15 | langchain-anthropic range bump → likely 1.x | **Close.** Would break our 0.3.x langchain pin. |
| #16 | langchain-huggingface range bump → likely 1.x | **Close.** Same reason. |
| #13 | vite 5 → 8 (major) | Review. Major jump; needs build test. |
| #18 | jsdom 25 → 29 (major) | Review. Affects vitest test runner; needs test run. |
| #19 | azure/aks-set-context 4 → 5 (major) | Review. Known to change inputs. |
| #21 | python-minor-patch group | Rebase onto current main (our fixes make this pass). |
| #17 | react + @types/react | Review — check compat with React 18 choices. |
| #14 | pytest-asyncio 0.25 → 1.3 (major) | Review — might need test adjustments. |
| #12 | pypdf 5.1 → 6.10 (major) | Review — API changes possible. |
| #10 | eslint-plugin-react-hooks 5.1 → ? | Likely safe. Merge if CI green. |

After closing #15 and #16, the rest will clear naturally as they either pass CI or expire. Open list: https://github.com/itsAmeMario0o/money-honey/pulls

---

## 🧭 What's next — ordered

### Phase 1 — unblock the chatbot (your side, ~10 min total)

1. **Anthropic API key** → store in Key Vault
   ```zsh
   read -s "ANTHROPIC_API_KEY?Anthropic key (sk-ant-...): "
   echo
   az keyvault secret set --vault-name mh-kv-w8fxwb --name anthropic-api-key --value "$ANTHROPIC_API_KEY"
   unset ANTHROPIC_API_KEY
   ```
   Source: https://console.anthropic.com/settings/keys

2. **Watch `docker-build.yaml`** finish. Expected: green on both backend + frontend. If Trivy catches Debian CVEs on the backend image, paste me the output and I'll bump `python:3.12-slim-bookworm` the same way I bumped the frontend.

3. **Manually trigger `deploy.yaml`** once images are in GHCR. Will pull images, roll out fastapi/react/caddy. fastapi pods should then pull the Anthropic key from the CSI mount and become Ready.

4. **Smoke-test the chat path from inside the cluster** (no public URL yet):
   ```zsh
   kubectl -n money-honey port-forward svc/caddy 8080:80
   # New terminal:
   curl -s -X POST http://localhost:8080/api/chat -H 'content-type: application/json' \
     -d '{"message":"Hey, should I max out my 401k?"}' | jq
   ```

### Phase 2 — public access via Cloudflare (your side, ~20 min)

5. **Populate the two Cloudflare tunnel tokens** (you already created them):
   ```zsh
   az keyvault secret set --vault-name mh-kv-w8fxwb --name cloudflare-tunnel-splunk-token  --value 'eyJ...splunk-tunnel-token...'
   az keyvault secret set --vault-name mh-kv-w8fxwb --name cloudflare-tunnel-chatbot-token --value 'eyJ...chatbot-tunnel-token...'
   ```

6. **Re-run `install-splunk.sh` with the token** so cloudflared starts on the Splunk VM:
   ```zsh
   CLOUDFLARED_TOKEN=$(az keyvault secret show --vault-name mh-kv-w8fxwb --name cloudflare-tunnel-splunk-token --query value -o tsv) \
     VM_IP=$(terraform -chdir=infra/terraform output -raw splunk_vm_public_ip) \
     SPLUNK_ADMIN_PASSWORD='...' \
     ./infra/scripts/install-splunk.sh
   ```
   Idempotent — won't reinstall Splunk, just adds the cloudflared service.

7. **Apply the cloudflared Kubernetes Deployment** for the chatbot:
   ```zsh
   kubectl apply -f k8s/cloudflared/
   ```
   I'll update it first to point at the `observability-secrets`-pattern SPC (same approach as Fluent Bit — needs the Cloudflare tunnel token in the money-honey namespace).

8. **Cloudflare dashboard: configure Public Hostname** for each tunnel once they show HEALTHY. Point `money-honey-chatbot` → `http://caddy.money-honey.svc.cluster.local:80`, `money-honey-splunk` → `http://localhost:8000`.

9. **Cloudflare Access**: attach email-domain allowlist to each tunnel's Application (e.g. `*@cisco.com`, `*@gmail.com`).

### Phase 3 — polish + public launch (both sides)

10. **Populate `OPENAI_API_KEY`** as a GitHub repo secret so `aibom.yaml` runs.
11. ~~**Finish `.github/workflows/hubness-scan.yaml`**~~ ✅ Wired to real Cisco `ahd scan` CLI (2026-04-14). Embeds PDFs with the same model as prod, runs adversarial hubness detection, uploads report artifacts.
12. ~~**Enable GitHub Pages**~~ ✅ Live at **https://itsamemario0o.github.io/money-honey/** (enabled 2026-04-14). Merlot theme restyled to match the frontend design system (honey palette, Space Grotesk, amber glow, dark Rouge code theme). Auto-rebuilds on every push that touches `docs/` or `_config.yml`.
13. **Tighten branch protection**: require passing status checks (`Quality`, `Docker Build`, `Deploy`) on `main` once CI has 2–3 clean runs.
14. **Flip advisory gates to blocking**: `trivy-k8s` job, `aibom.yaml`.
15. **Fix the v1.1 backlog** in `docs/roadmap.md`: CSI cross-namespace architecture cleanup. _(OTel `${file:...}` token refactor and Tetragon `exportFilename` simplification landed 2026-04-13. CLAUDE.md freshness audit landed 2026-04-16. Humanizer pass across all docs landed 2026-04-14. Notebooks/ removed 2026-04-16.)_

---

## 🩺 Known quirks (for my own memory)

- Tetragon log lives at `/var/run/cilium/tetragon/tetragon.log` on each node. `exportFilename` in tetragon.tf is now just the filename (not a full path) so the Helm chart produces a clean directory layout.
- Fluent Bit runs as uid 0 because Tetragon writes the log as root and hostPath doesn't honor fsGroup. Still read-only rootfs + all caps dropped + no privesc.
- CodeGuard (OASIS/CoSAI) plugin added to the CLAUDE.md skills section on 2026-04-14. Operator runs `/plugin marketplace add cosai-oasis/project-codeguard` + `/plugin install codeguard-security@project-codeguard` once per machine — no repo artifact required.
- GitHub Pages source is `/docs`, so Jekyll only processes files under that path. Theme overrides live at `docs/assets/css/style.scss` and `docs/_includes/head_custom.html` — **NOT** at the repo root, where Jekyll would silently ignore them.
- Caddy needs `CAP_NET_BIND_SERVICE` to bind port 80 as uid 1000.
- AKS API server is public (no IP allowlist) — AAD + RBAC is the gate. V2 path: private cluster + self-hosted runners.
- `local_account_disabled = false` on AKS so Terraform's Helm provider can auth via `kube_admin_config`. Kubelogin+exec is the v2 hardening.
