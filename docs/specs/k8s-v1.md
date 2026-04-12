# ☸️ Spec: Kubernetes Manifests v1

## 1. Title and Metadata

| Field | Value |
|---|---|
| **Feature** | Kubernetes manifests to run Money Honey on AKS |
| **Author** | Mario Ruiz + Claude Code |
| **Status** | 🚧 **In progress** — manifests being written; safe subset applied to cluster |
| **Reviewers** | Mario Ruiz |
| **Skills used** | `spec-driven-workflow`, `senior-secops`, `secrets-vault-manager`, `observability-designer`, `senior-backend`, `senior-frontend` |
| **Depends on** | `docs/specs/infra-v1.md` (AKS + Cilium + Tetragon), `docs/specs/chatbot-v1.md` (app layer), `docs/specs/cloudflare-access-v1.md` (Layer 8 edge) |

---

## 2. Context

Step 3 put the AKS cluster and a Helm-installed Tetragon DaemonSet in Azure. Step 4 writes the Kubernetes manifests that turn that cluster into a running Money Honey stack: the React SPA, the FastAPI backend, the Caddy internal reverse proxy, the CSI secret mounts, the default-deny network policies, the Tetragon TracingPolicies, Fluent Bit for log shipping, OTel Collector for metrics, and the `cloudflared` Deployment that fronts the chatbot via Cloudflare Tunnel (Layer 8).

No images exist in GHCR yet — that's step 5. This spec focuses on the **manifest authoring** plus applying the subset that doesn't require runtime secrets or container images: network policies, tracing policies, SecretProviderClass shells, the `money-honey` namespace.

Everything else is reviewable, lintable, `kubectl apply --dry-run=client` clean, and ready to roll on step 5.

---

## 3. Functional Requirements (RFC 2119)

### Namespace + shared infra

| ID | Requirement |
|---|---|
| **FR-1** | All application workloads MUST live in the `money-honey` Kubernetes namespace. Observability workloads (Fluent Bit, OTel Collector) MAY live in `kube-system` to match Tetragon. |
| **FR-2** | Every resource MUST carry labels `app`, `component`, and `part-of=money-honey` (per CLAUDE.md Kubernetes rules). |
| **FR-3** | Every container MUST have resource `requests` and `limits` set. |
| **FR-4** | Every pod MUST run as non-root (`securityContext.runAsNonRoot: true`, `runAsUser` matching the image's non-root uid). |

### Application workloads

| ID | Requirement |
|---|---|
| **FR-5** | `fastapi-deployment` MUST run the backend image (`ghcr.io/itsAmeMario0o/money-honey-app:latest`), expose port `8000`, mount Key Vault secrets via CSI under `/mnt/secrets/`. 2 replicas. |
| **FR-6** | `react-deployment` MUST run the frontend image (`ghcr.io/itsAmeMario0o/money-honey-frontend:latest`), expose port `3000`. 2 replicas. |
| **FR-7** | `caddy-deployment` MUST run the official `caddy:2-alpine` image, mount its Caddyfile from a ConfigMap, expose port `80` as a ClusterIP Service named `caddy`. 2 replicas. |
| **FR-8** | A single `SecretProviderClass` named `money-honey-secrets` MUST define the mapping from Key Vault secrets to file paths in the CSI volume. It MUST reference the cluster's `key_vault_secrets_provider` add-on identity. |

### Network policies (Layer 1 — Cilium, default-deny)

| ID | Requirement |
|---|---|
| **FR-9** | A `CiliumNetworkPolicy` MUST set a default-deny ingress and egress for every pod in the `money-honey` namespace. |
| **FR-10** | A `CiliumNetworkPolicy` MUST allow `cloudflared` pods → Caddy (port 80). |
| **FR-11** | A `CiliumNetworkPolicy` MUST allow Caddy → FastAPI (8000) and Caddy → React (3000). |
| **FR-12** | A `CiliumNetworkPolicy` MUST allow FastAPI → the Claude API (egress to `api.anthropic.com`, CIDR-based since we don't have FQDN filtering without ACNS). |
| **FR-13** | A `CiliumNetworkPolicy` MUST allow FastAPI + Fluent Bit → Splunk HEC at `10.0.4.0/28:8088` (the `splunk` subnet CIDR). |
| **FR-14** | A `CiliumNetworkPolicy` MUST allow `cloudflared` pods to reach Cloudflare edge CIDRs (`198.41.128.0/17`, `173.245.48.0/20`, `103.21.244.0/22`, and the other Cloudflare blocks). |
| **FR-15** | DNS egress (CoreDNS on port 53 UDP/TCP) MUST be allowed for every pod — otherwise nothing resolves. |

### Tetragon TracingPolicies (Layer 2 — runtime)

| ID | Requirement |
|---|---|
| **FR-16** | A `TracingPolicy` MUST detect and log any `exec` of binaries outside a small allowlist (python, node, sh, the app binaries). Enforcement mode (`SIGKILL` on violation) is enabled for the `money-honey` namespace. |
| **FR-17** | A `TracingPolicy` MUST log every network connect() attempt from `money-honey` pods with source/dest/port metadata — this is the primary audit trail for the egress policy in FR-12/13/14. |
| **FR-18** | A `TracingPolicy` MUST log every file open under `/mnt/secrets/` — any unauthorized read of mounted KV secrets is visible in Splunk. |

### Observability

| ID | Requirement |
|---|---|
| **FR-19** | A Fluent Bit `DaemonSet` MUST run on every node, tail `/var/run/cilium/tetragon/tetragon.log`, and forward events to Splunk HEC at `https://<splunk-vm-private-ip>:8088/services/collector`. The HEC token comes from the CSI-mounted `splunk-hec-token` secret. |
| **FR-20** | An OpenTelemetry Collector `Deployment` MUST scrape Tetragon's Prometheus endpoint on every node (port `2112`) and forward metrics to Splunk. |

### Cloudflare tunnel (Layer 8)

| ID | Requirement |
|---|---|
| **FR-21** | A `cloudflared` `Deployment` MUST run 2 replicas in `money-honey`, reading its connector token from the CSI-mounted `cloudflare-tunnel-chatbot-token` secret. Points at `caddy:80` as its origin. |

---

## 4. Non-Functional Requirements

| ID | Requirement | Threshold |
|---|---|---|
| **NFR-1** (security) | No pod MAY run as root. | `runAsNonRoot: true` on all pods |
| **NFR-2** (security) | No Deployment MAY use `hostNetwork`, `hostPID`, or `privileged: true`. Tetragon's DaemonSet (already deployed via Helm) is exempt — it needs kernel access. | 0 exceptions in `money-honey` ns |
| **NFR-3** (security) | Every network connection MUST be explicitly allowed by a CiliumNetworkPolicy. Default-deny applies to the whole `money-honey` namespace. | `kubectl exec` reachability tests fail by default |
| **NFR-4** (reliability) | Each Deployment MUST define `readinessProbe` + `livenessProbe`. Pods with failing probes get cycled automatically. | 100% coverage |
| **NFR-5** (resource) | Total CPU requests across all app Deployments MUST fit comfortably on the 3-node `Standard_B2s` pool (6 vCPU total, ~4 vCPU available after Cilium + Tetragon). | < 3 vCPU requested |
| **NFR-6** (a11y) | `kubectl apply --dry-run=client` MUST succeed on every manifest. | 0 validation errors |
| **NFR-7** (observability) | Every Tetragon event MUST reach Splunk within 60 seconds of emission. | < 60 s log lag |

---

## 5. Acceptance Criteria (Given / When / Then)

| ID | Criterion | Refs |
|---|---|---|
| **AC-1** | **Given** all manifests are written, **When** `kubectl apply --dry-run=client -f k8s/` runs, **Then** it exits 0 with no validation errors. | NFR-6 |
| **AC-2** | **Given** the namespace + network policies are applied, **When** a test pod attempts egress to a non-whitelisted IP, **Then** the connection is refused at the Cilium layer. | FR-9, NFR-3 |
| **AC-3** | **Given** the `money-honey-secrets` SecretProviderClass exists and KV contains the named secrets, **When** a FastAPI pod mounts the CSI volume, **Then** the secret files appear at `/mnt/secrets/`. | FR-8 |
| **AC-4** | **Given** the TracingPolicy for exec is applied, **When** an attacker runs `bash` inside a FastAPI pod, **Then** Tetragon kills the process and emits a Splunk-visible event. | FR-16 |
| **AC-5** | **Given** Fluent Bit is running, **When** Tetragon emits a JSON event, **Then** the event lands in Splunk within 60 seconds. | FR-19, NFR-7 |
| **AC-6** | **Given** `cloudflared` Deployment has a valid tunnel token, **When** the Deployment starts, **Then** the Cloudflare Zero Trust dashboard shows the tunnel as **HEALTHY**. | FR-21 |

---

## 6. Edge Cases

| ID | Scenario | Expected behavior |
|---|---|---|
| **EC-1** | Key Vault secret values are empty (placeholders not yet replaced) | CSI mount still succeeds but files contain `set-me-in-portal`; FastAPI returns 503 on `/api/chat`. No crash loop. |
| **EC-2** | Splunk VM is down | Fluent Bit retries with exponential backoff; events buffer on node disk up to the buffer limit. |
| **EC-3** | Container image not in GHCR yet | Pod stuck in `ImagePullBackOff`. Not a bug — expected before step 5 builds the images. Don't apply app Deployments until then. |
| **EC-4** | Cilium policy misconfigured, app can't reach Claude | Health check shows `llm_ready: true` but chat returns 502/504. Operator inspects `cilium monitor` or Tetragon audit in Splunk to find the dropped flow. |
| **EC-5** | Cloudflared token is wrong | `cloudflared` pod crash-loops with auth error. Rotate in Cloudflare dashboard → update KV secret → restart the Deployment. |
| **EC-6** | Node runs out of memory (B2s has 4 GB) | Worst-case: pods get evicted. We've sized requests conservatively; NFR-5 caps total requests at ~3 vCPU across the app. Memory budget: app pods ≤ 512Mi each, Tetragon ≤ 512Mi, Cilium baseline ~300Mi. |

---

## 7. API Contracts (Kubernetes resource interfaces)

```yaml
# Inputs to the manifests (ConfigMaps / Secret references)
ConfigMap caddy-config:
  Caddyfile: |
    :80 {
      reverse_proxy /api/* fastapi:8000
      reverse_proxy /* react:3000
    }

SecretProviderClass money-honey-secrets:
  secretObjects:
    - secretName: app-api-keys (synthesised K8s Secret)
      data: [anthropic-api-key]
    - secretName: splunk-hec (synthesised K8s Secret)
      data: [splunk-hec-token]
    - secretName: cloudflare-chatbot (synthesised K8s Secret)
      data: [cloudflare-tunnel-chatbot-token]

# Services
Service fastapi    (ClusterIP, :8000)
Service react      (ClusterIP, :3000)
Service caddy      (ClusterIP, :80)   <- sole internal entry point
```

---

## 8. Data Models (resource inventory)

| Category | Resources |
|---|---|
| Namespace | `money-honey` |
| Deployments (in `money-honey`) | `fastapi`, `react`, `caddy`, `cloudflared` |
| Services (in `money-honey`) | `fastapi`, `react`, `caddy` |
| CiliumNetworkPolicies (in `money-honey`) | `default-deny`, `allow-cloudflared-to-caddy`, `allow-caddy-to-app`, `allow-fastapi-egress`, `allow-cloudflared-egress`, `allow-dns` |
| SecretProviderClass (in `money-honey`) | `money-honey-secrets` |
| TracingPolicies (cluster-scoped) | `process-exec-allowlist`, `network-connect-audit`, `secrets-file-audit` |
| DaemonSet (in `kube-system`) | `fluent-bit` |
| Deployment (in `kube-system`) | `otel-collector` |
| ConfigMaps | `caddy-config`, `fluent-bit-config`, `otel-config` |

**Total: ~20 resources across 4 namespaces (plus the already-present `tetragon` DaemonSet).**

---

## 9. Out of Scope (v1)

| ID | Excluded | When |
|---|---|---|
| **OS-1** | HorizontalPodAutoscaler | v2 — traffic is predictable for a demo |
| **OS-2** | PodDisruptionBudget | v2 |
| **OS-3** | Ingress controller (nginx, Traefik) | Cloudflare Tunnel replaces it |
| **OS-4** | Cert-Manager | Cloudflare terminates TLS |
| **OS-5** | ArgoCD / GitOps | Deferred; step 5 uses kubectl-apply CI |
| **OS-6** | Mutating admission webhooks (OPA, Kyverno) | v2 |
| **OS-7** | ServiceMonitor / Prometheus Operator CRs | OTel forwards metrics directly to Splunk |
| **OS-8** | ACNS-dependent features (Hubble, FQDN policy, L7 policy) | v2 (requires ACNS subscription) |

---

## 10. Self-Review Checklist

- [x] Every FR has at least one AC
- [x] No secret values in code; all via CSI + KV
- [x] Non-root + resource limits mandated on every workload
- [x] Default-deny network policy is explicit
- [x] Edge cases cover the image-not-yet-built state (EC-3)
- [x] Out of Scope excludes ACNS-dependent features
- [x] RFC 2119 keywords used consistently

---

## 11. Apply strategy (staged rollout)

1. **Safe now (can apply without images or real secrets):**
   - `namespace.yaml`
   - `k8s/network-policies/*.yaml` (default-deny + allows)
   - `k8s/tetragon/tracing-policies.yaml`
   - `k8s/secrets/secretproviderclass.yaml` (shell only)

2. **Needs real secrets in KV (blocked on operator):**
   - Fluent Bit DaemonSet (reads `splunk-hec-token`)
   - cloudflared Deployment (reads `cloudflare-tunnel-chatbot-token`)

3. **Needs container images in GHCR (blocked on step 5):**
   - FastAPI Deployment
   - React Deployment
   - Caddy Deployment (image is public, but depends on the other two)

We apply (1) during step 4, write + lint (2) and (3), and unblock them in steps 5–7.
