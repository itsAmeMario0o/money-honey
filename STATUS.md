# 📊 Current Build Status

Last updated 2026-04-13.

## ✅ Azure resources live

| Resource | Status | Cost |
|---|---|---|
| AKS `money-honey-aks` (K8s 1.34, 3× `Standard_B2s`, Cilium v1.18.6) | ✅ Running | ~$90/mo |
| Tetragon DaemonSet (kube-system, 3/3 pods) | ✅ Running | $0 |
| VNet `money-honey-vnet` + 2 subnets | ✅ | $0 |
| Key Vault `mh-kv-w8fxwb` | ✅ | <$1/mo |
| Splunk VM (Ubuntu 22.04, `Standard_B2ms`) + **Splunk Enterprise Free installed** | ✅ Running | ~$70/mo |
| Splunk public IP (SSH only; web/HEC internal) | ✅ | $3.60/mo |
| Terraform state SA `mhtfstatemjr26` | ✅ | <$1/mo |
| Azure federated Service Principal `money-honey-ci` (OIDC for CI) | ✅ | $0 |
| **Running total** | | **~$165/mo** |

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
| `quality.yaml` (pytest, vitest, ruff, black, mypy, eslint, prettier, gitleaks, tfsec, Trivy fs + k8s) | 🚧 wired up; iterating on first-run errors |
| `docker-build.yaml` (build + Trivy image scan + push to GHCR) | 🚧 in flight — just pushed the Alpine 3.23 + faiss-cpu 1.13.2 fixes |
| `deploy.yaml` (OIDC Azure login + kubelogin + kubectl apply) | 🚧 SP verified; waits on images in GHCR |
| `aibom.yaml` (Cisco AIBOM via uv tool install) | ⏳ blocked on `OPENAI_API_KEY` secret |
| `hubness-scan.yaml` (Cisco Hubness Detector) | 📝 placeholder; wire up once real action interface confirmed |

## 🛡️ Repo security posture

- Branch protection on `main`: force-push blocked, deletion blocked
- GitHub Secret Protection + Push Protection: enabled
- Local pre-commit hook: gitleaks + tfsec + ruff + black (runs on every commit)
- `.trivyignore.yaml`: 1 scoped ignore (OTel ConfigMap `token:` false positive)
- `.gitleaksignore`: 2 scoped ignores (tenant ID in SPC YAMLs)

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
11. **Finish `.github/workflows/hubness-scan.yaml`** — verify the real Cisco Hubness action interface.
12. **Enable GitHub Pages** (repo Settings → Pages → Source: `main` / `/docs`) — Jekyll docs site goes live.
13. **Tighten branch protection**: require passing status checks (`Quality`, `Docker Build`, `Deploy`) on `main` once CI has 2–3 clean runs.
14. **Flip advisory gates to blocking**: `trivy-k8s` job, `aibom.yaml`.
15. **Fix the v1.1 backlog** in `docs/roadmap.md`: OTel `token_file:` refactor, Tetragon exportFilename simplification, CSI cross-namespace architecture cleanup.

---

## 🩺 Known quirks (for my own memory)

- Tetragon log is at a doubled path (`/var/run/cilium/tetragon/var/run/cilium/tetragon/tetragon.log`) because the Helm chart concatenates `exportFilename` onto `exportDirectory`. Fluent Bit's tail config already accounts for it.
- Fluent Bit runs as uid 0 because Tetragon writes the log as root and hostPath doesn't honor fsGroup. Still read-only rootfs + all caps dropped + no privesc.
- Caddy needs `CAP_NET_BIND_SERVICE` to bind port 80 as uid 1000.
- AKS API server is public (no IP allowlist) — AAD + RBAC is the gate. V2 path: private cluster + self-hosted runners.
- `local_account_disabled = false` on AKS so Terraform's Helm provider can auth via `kube_admin_config`. Kubelogin+exec is the v2 hardening.
