# 📊 Current Build Status

Last updated by the autonomous work block on 2026-04-12.

## ✅ What's live in Azure right now

| Resource | Status | Cost |
|---|---|---|
| AKS `money-honey-aks` (K8s 1.34, 3× `Standard_B2s`, Cilium v1.18.6) | ✅ Running | ~$90/mo |
| Tetragon DaemonSet (kube-system, 3/3 pods ready) | ✅ Running | $0 (on AKS nodes) |
| VNet `money-honey-vnet` + subnets | ✅ | $0 |
| Key Vault `mh-kv-w8fxwb` + 4 secret shells | ✅ | <$1/mo |
| Splunk VM (Ubuntu 22.04, `Standard_B2ms`) | ✅ Running, Splunk not yet installed | ~$70/mo |
| Splunk public IP (SSH only) | ✅ | $3.60/mo |
| Terraform state SA `mhtfstatemjr26` | ✅ | <$1/mo |
| **Rough total** | | **~$165/mo** |

Well under the $250/mo cap.

## ✅ What's live in AKS

| Resource | Namespace | Count |
|---|---|---|
| CiliumNetworkPolicies (default-deny + 7 allows) | money-honey | 8 |
| TracingPolicyNamespaced (exec audit, tcp_connect audit, secrets-file audit) | money-honey | 3 |
| SecretProviderClass (money-honey-secrets) | money-honey | 1 |

Everything is `VALID = True`. Default-deny is active — any new pod starts with zero connectivity until an explicit allow matches it.

## 📦 Manifests written but NOT yet applied

All committed to main (`docs/specs/k8s-v1.md` has the rationale), all pass `kubectl apply --dry-run=client`:

| Folder | Manifests | Why not applied |
|---|---|---|
| `k8s/app/` | `fastapi` Deployment + Service | Image `ghcr.io/itsamemario0o/money-honey-app:latest` not yet built — step 5 |
| `k8s/frontend/` | `react` Deployment + Service | Same — step 5 |
| `k8s/caddy/` | Caddy ConfigMap + Deployment + Service | Waits on upstreams (app + frontend) to exist |
| `k8s/fluent-bit/` | ConfigMap + SA + DaemonSet | Needs a real `splunk-hec-token` in KV + the actual Splunk VM IP in the ConfigMap |
| `k8s/otel/` | ConfigMap + SA + ClusterRole + Binding + Deployment | Same Splunk dependency |
| `k8s/cloudflared/` | Deployment (2 replicas) | Needs real tunnel token populated in KV |

## 🔜 Next steps (in order)

### Step 5: CI/CD workflows — ✅ written, needs repo secrets before first real run
Four workflows committed alongside the existing `quality.yaml`:
- `docker-build.yaml` — Buildx + GHCR push, SHA + `:latest` tags, GHA cache
- `deploy.yaml` — OIDC Azure login + `kubectl apply` scoped to `k8s/{app,frontend,caddy}`
- `aibom.yaml` — Cisco AIBOM scan placeholder (verify action interface)
- `hubness-scan.yaml` — Cisco Hubness Detector placeholder

**Repo secrets operator must set:**
- `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID` (OIDC federated SP)
- `WEBEX_BOT_TOKEN`, `WEBEX_ROOM_ID` (both gated with `if: secrets.X != ''` so absence is non-blocking)

### Step 6: Jekyll docs site — ✅ core pages written
- `docs/index.md` — landing page with three-domain framework
- `docs/architecture/{overview,infrastructure,ai-security,developer-workflow}.md` — layer deep-dives
- Setup + chatbot sub-pages are placeholders, fill in before public launch
- Enable Pages: repo Settings → Pages → Source: `main` / `/docs`

### Post-step-5 operator tasks (once CI has built images)
1. Install Splunk on the VM:
   ```bash
   VM_IP=$(terraform -chdir=infra/terraform output -raw splunk_vm_public_ip)
   CLOUDFLARED_TOKEN=$(az keyvault secret show \
     --vault-name mh-kv-w8fxwb \
     --name cloudflare-tunnel-splunk-token --query value -o tsv)
   SPLUNK_ADMIN_PASSWORD='...' VM_IP=$VM_IP CLOUDFLARED_TOKEN=$CLOUDFLARED_TOKEN \
     infra/scripts/install-splunk.sh
   ```
2. In the Splunk UI, create an HEC token for Fluent Bit.
3. Populate the KV secrets:
   ```bash
   az keyvault secret set --vault-name mh-kv-w8fxwb --name anthropic-api-key --value 'sk-ant-...'
   az keyvault secret set --vault-name mh-kv-w8fxwb --name splunk-hec-token --value '...'
   az keyvault secret set --vault-name mh-kv-w8fxwb --name cloudflare-tunnel-chatbot-token --value '...'
   ```
4. Update the Fluent Bit + OTel ConfigMaps with the real Splunk VM private IP.
5. Apply the app, observability, and cloudflared manifests.
6. Configure the Public Hostname on each Cloudflare tunnel (dashboard step).

## 🔬 Trivy baseline (local run before merging the workflow)

| Scan | Result |
|---|---|
| `trivy fs` (dep scan) | ✅ **0 findings** after bumping `langchain-community` 0.3.5 → 0.3.27 (CVE-2025-6984 insecure XML parsing) and `black` 24.10.0 → 26.3.1 (CVE-2026-32274 arbitrary file writes). Would have blocked CI otherwise. |
| `trivy config k8s/` (manifest scan, advisory) | ⚠️ 1 HIGH: `otel/configmap.yaml` has `token` as a YAML key (OTel exporter's required field name). Actual value is `${SPLUNK_HEC_TOKEN}` template placeholder substituted from env at runtime. Accepted as advisory — not a real secret leak. |

## 🩺 Diagnostics captured

- Cilium connectivity test: 54/56 tests passed. 2 failures both are test-harness issues (encryption-test N/A; `/bin/sh` missing in distroless container). Actual networking is healthy.
- Azure vCPU quota for `standardBasv2Family` was exhausted; pivoted to `standardBSFamily` (Standard_B2s). Documented in `project_design_decisions.md` memory.
- AKS `local_account_disabled=false` for v1 so Terraform's Helm provider can auth via kube_admin_config; post-v1 hardening path uses kubelogin exec plugin.
- Terraform state lock flakiness when runs are interrupted. Workaround: `az storage blob lease break` when `terraform force-unlock` won't do it.

## 🛡️ Pre-flight rules I'm following now

From `.claude/memory/project_design_decisions.md`:
1. Grep for stale refs (`seven layers`, `CFP`, `OpenAI`, hardcoded UUIDs) before doc-touching commits
2. State implications before acting, not only when asked
3. Update the design-decisions memory whenever a non-obvious choice lands
4. Walk non-obvious decisions through proactively
