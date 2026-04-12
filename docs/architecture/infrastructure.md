---
layout: default
title: Infrastructure Security
---

# 🏗️ Infrastructure Security (Layers 1, 2, 3, 7)

The platform controls that protect the cluster itself.

## Layer 1 — Cilium network identity

- AKS with `network_plugin = "azure"` + `network_data_plane = "cilium"` + `network_policy = "cilium"` (Cilium v1.18.6, Azure-managed build).
- Default-deny on the `money-honey` namespace. Every pod-to-pod and pod-to-external flow is explicitly allowed by a `CiliumNetworkPolicy`.
- No Hubble (requires ACNS, deferred).
- Egress allowlist: Claude API via 443/TCP, Splunk HEC on the private subnet (`10.0.4.0/28:8088`), Cloudflare edge (443 + 7844).

## Layer 2 — Tetragon runtime enforcement

- DaemonSet, installed via Helm chart `1.3.0` from `helm.cilium.io`.
- Three `TracingPolicyNamespaced` CRDs active in `money-honey`:
  - `process-exec-audit` — logs exec of any binary outside the allowlist (python, uvicorn, node, nginx, caddy, sh, bash).
  - `network-connect-audit` — logs every `tcp_connect()`.
  - `secrets-file-audit` — logs every file open under `/mnt/secrets/`.
- Policies are audit-only in v1; switch to SIGKILL enforcement after the allowlist is validated against real traffic.
- JSON events written to `/var/run/cilium/tetragon/tetragon.log` on each node.

## Layer 3 — Key Vault + CSI Secret Store Driver

- Azure Key Vault `mh-kv-w8fxwb`, Standard SKU, purge protection on, soft-delete 7 days.
- `network_acls.default_action = "Deny"`. Only the operator IP and the AKS node subnet are allowed at the network layer.
- AKS add-on `azurekeyvaultsecretsprovider` provisions a user-assigned managed identity; the `aks_csi` access policy gives it `Get`/`List` on secrets.
- Pods mount the `money-honey-secrets` `SecretProviderClass` as a volume; files appear under `/mnt/secrets/`. Matching K8s `Secrets` are synthesised for env-var use.
- Secrets managed: `anthropic-api-key`, `splunk-hec-token`, `cloudflare-tunnel-splunk-token`, `cloudflare-tunnel-chatbot-token`.

## Layer 7 — Splunk observability

- Splunk Enterprise Free on a dedicated Ubuntu 22.04 VM (`Standard_B2ms`).
- Fluent Bit DaemonSet in `kube-system` tails Tetragon's JSON log and ships to Splunk HEC via `https://<splunk-private-ip>:8088/services/collector`.
- OpenTelemetry Collector scrapes Tetragon Prometheus metrics on port 2112 and forwards to the same Splunk HEC with `sourcetype=prometheus`.
- Splunk UI reachable via its own Cloudflare Tunnel (no direct public port exposure); SSH stays on the public IP scoped to operator IP only.
