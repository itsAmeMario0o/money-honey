---
layout: default
title: Infrastructure Security
---

# 🏗️ Infrastructure security (Layers 1, 2, 3, 7)

Platform controls that protect the cluster itself. Each layer answers a different threat.

## Layer 1: Cilium network identity

Without network policy, any pod can talk to any other pod or any external IP. A compromised container becomes a pivot point for lateral movement.

Cilium closes that gap. AKS runs with `network_plugin = "azure"` + `network_data_plane = "cilium"` + `network_policy = "cilium"` (Cilium v1.18.6, Azure-managed build). Default-deny on the `money-honey` namespace. Every pod-to-pod and pod-to-external flow requires an explicit `CiliumNetworkPolicy`. No Hubble (requires ACNS, deferred).

Egress allowlist: Claude API via 443/TCP, Splunk HEC on the private subnet (`10.0.4.0/28:8088`), Cloudflare edge (443 + 7844). Anything else is dropped.

## Layer 2: Tetragon runtime enforcement

Network policy stops bad connections. It does not stop a bad process running inside a container that only talks to allowed IPs.

Tetragon watches the kernel. DaemonSet installed via Helm chart `1.3.0` from `helm.cilium.io`. Three `TracingPolicyNamespaced` CRDs are active in `money-honey`:

- `process-exec-audit`: logs exec of any binary outside the allowlist (python, uvicorn, node, nginx, caddy, sh, bash).
- `network-connect-audit`: logs every `tcp_connect()`.
- `secrets-file-audit`: logs every file open under `/mnt/secrets/`.

Policies are audit-only in v1. After the allowlist is validated against real traffic, they switch to SIGKILL enforcement. JSON events are written to `/var/run/cilium/tetragon/tetragon.log` on each node.

## Layer 3: Key Vault + CSI Secret Store Driver

Secrets in environment variables or ConfigMaps are readable by any process in the container, any crashdump collector, and any log pipeline that captures env. One misconfigured sidecar leaks everything.

Key Vault keeps secrets off the cluster entirely until mount time. Azure Key Vault `mh-kv-w8fxwb`, Standard SKU, purge protection on, soft-delete 7 days. `network_acls.default_action = "Deny"`. Only the operator IP and the AKS node subnet pass the network layer.

AKS add-on `azurekeyvaultsecretsprovider` provisions a user-assigned managed identity; the `aks_csi` access policy gives it `Get`/`List` on secrets. Pods mount the `money-honey-secrets` `SecretProviderClass` as a volume; files appear under `/mnt/secrets/`. Matching K8s `Secrets` are synthesized for env-var use.

Secrets managed: `anthropic-api-key`, `splunk-hec-token`, `cloudflare-tunnel-splunk-token`, `cloudflare-tunnel-chatbot-token`.

## Layer 7: Splunk observability

Layers 1-3 enforce. Layer 7 records. Without a single place to search audit events, you cannot tell whether enforcement is working or even firing.

Splunk Enterprise Free runs on a dedicated Ubuntu 22.04 VM (`Standard_B2ms`). Fluent Bit DaemonSet in `kube-system` tails Tetragon's JSON log and ships to Splunk HEC via `https://<splunk-private-ip>:8088/services/collector`. OpenTelemetry Collector scrapes Tetragon Prometheus metrics on port 2112 and forwards to the same Splunk HEC with `sourcetype=prometheus`.

Splunk UI is reachable via its own Cloudflare Tunnel (no direct public port exposure). SSH stays on the public IP, scoped to the operator IP only.
