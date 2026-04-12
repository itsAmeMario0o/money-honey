# 🔐 Spec: Cloudflare Tunnel + Access (v2)

## 1. Title and Metadata

| Field | Value |
|---|---|
| **Feature** | Zero-trust public edge for Money Honey chatbot and Splunk dashboard |
| **Author** | Mario Ruiz + Claude Code |
| **Status** | ⏸️ **Paused — resume after step 4 (k8s manifests)** |
| **DNS approach (decided)** | **Option 3** — use free `*.trycloudflare.com` hostnames for v1. No DNS delegation, no Squarespace changes, no new domain. Custom domain (`money-honey.mariojruiz.com`) deferred to a later pass when DNS is migrated (see §"Resume Point" below). |
| **Reviewers** | Mario Ruiz |
| **Skills to use** | `spec-driven-workflow`, `cloud-security`, `senior-secops`, `terraform-patterns` |
| **Depends on** | `docs/specs/infra-v1.md`, `docs/specs/chatbot-v1.md` |

---

## ⏸️ Resume Point (last updated mid-step 3)

**What's decided:**
- Cloudflare Tunnel + Access **is part of v1** (not v2 as originally written — doc name is a legacy artifact).
- DNS approach: **Option 3** — `*.trycloudflare.com` hostnames. No Squarespace changes, no custom domain in v1.
- Chatbot URL will be something like `https://money-honey.trycloudflare.com`.
- Splunk URL will be something like `https://splunk-money-honey.trycloudflare.com`.
- Cloudflare Access still enforces email-domain allowlist (`cisco.com`, `gmail.com`, etc.) on both hostnames.

**What's done:** nothing in code yet — infra step 3 (commits through `1e6b566`) does NOT include Cloudflare. Splunk VM still has a public IP; AKS will get a public LB when step 4 lands.

**What to do on resume (picked up in this order):**
1. Operator creates a Cloudflare account (if not already) and an API token with Tunnel + Access scopes. No DNS setup needed for Option 3.
2. Rewrite this spec: drop zone-delegation FRs (FR-1, FR-2), drop `cloudflare_zone` / `cloudflare_record` resources, keep tunnels + Access apps, point the Access apps at tunnel-generated `trycloudflare.com` hostnames.
3. Add `cloudflare.tf` to `infra/terraform/` with: provider, 2 tunnels, 2 Access applications, 2 Access policies.
4. Remove `azurerm_public_ip.splunk` and its NIC binding + NSG rule for 8000/tcp.
5. Add 2 new Key Vault secret shells: `cloudflare-api-token`, `cloudflare-tunnel-chatbot-token`, `cloudflare-tunnel-splunk-token`.
6. Update `install-splunk.sh` to install `cloudflared` as a systemd unit on the VM.
7. In step 4 (k8s), change Caddy Service from `LoadBalancer` to `ClusterIP` and add a `cloudflared` Deployment for the chatbot tunnel.
8. Update CLAUDE.md: move this from "Deferred to v2" into the layer list (becomes Layer 8); update tech stack table.

**Trade-off accepted for v1:** ugly URLs (`trycloudflare.com`) instead of `money-honey.mariojruiz.com`. Swap to custom DNS later when the domain is moved to Cloudflare DNS or a new Cloudflare-registered domain is purchased.

---

## 2. Context

v1 exposes two public surfaces:

1. The Money Honey chatbot at `money-honey.mariojruiz.com` (Azure public LB → Caddy → FastAPI / React)
2. The Splunk dashboard at the VM's public IP on port 8000 (operator-IP-only in v1)

Both are usable as-is, but neither has identity-based access control. For v2 we want:

- **Identity-gated access** — only callers with an email matching an allowlist (e.g. `*@cisco.com`, `*@gmail.com`) can reach either app.
- **No public inbound ports** — origins dial outbound to the edge. Splunk VM can drop its public IP entirely. AKS can drop its LoadBalancer.
- **Free tier coverage** — Cloudflare Access is free for up to 50 users.
- **Cost savings** — removing the AKS Standard LB public IP (~$18/mo) and the Splunk VM public IP (~$3.60/mo) nets ~$25/month off the bill.

This matches the "defense in depth" theme of the project: Cloudflare Access becomes a new layer in front of Caddy (chatbot) and Splunk Web, enforcing identity before traffic reaches our cluster or VM.

---

## 3. Functional Requirements (RFC 2119)

### DNS and zone setup

| ID | Requirement |
|---|---|
| **FR-1** | The subdomain `money-honey.mariojruiz.com` MUST be delegated from Azure DNS to Cloudflare via NS records. The parent zone `mariojruiz.com` MUST remain in Azure DNS untouched. |
| **FR-2** | Cloudflare MUST manage the following hostnames under the delegated subdomain: `money-honey.mariojruiz.com` (chatbot) and `splunk.money-honey.mariojruiz.com` (dashboard). |

### Tunnels

| ID | Requirement |
|---|---|
| **FR-3** | One `cloudflared` Deployment MUST run inside AKS, configured as a tunnel that forwards Cloudflare traffic for `money-honey.mariojruiz.com` to the Caddy ClusterIP Service on port 80. |
| **FR-4** | One `cloudflared` service (systemd unit) MUST run on the Splunk VM, configured as a tunnel that forwards Cloudflare traffic for `splunk.money-honey.mariojruiz.com` to `127.0.0.1:8000`. |
| **FR-5** | Tunnel credentials MUST be stored as Azure Key Vault secrets (`cloudflare-tunnel-chatbot-token`, `cloudflare-tunnel-splunk-token`) and injected at runtime via the CSI driver (chatbot) or cloud-init (Splunk VM). They MUST NOT appear in code or state. |

### Access policies

| ID | Requirement |
|---|---|
| **FR-6** | A Cloudflare Access application MUST protect `money-honey.mariojruiz.com` with the policy "allow if email matches any configured domain in `var.access_email_domains`". |
| **FR-7** | A Cloudflare Access application MUST protect `splunk.money-honey.mariojruiz.com` with the same email-domain policy. |
| **FR-8** | `var.access_email_domains` MUST default to `["cisco.com", "gmail.com"]` and be extendable without code changes. |
| **FR-9** | Session duration MUST be 24 hours. Users reauthenticate daily. |

### Origin hardening (applies after tunnels are live)

| ID | Requirement |
|---|---|
| **FR-10** | The Splunk VM's `azurerm_public_ip` and its `ip_configuration.public_ip_address_id` MUST be removed. The VM becomes reachable only from the Splunk subnet and via Cloudflare Tunnel. |
| **FR-11** | The AKS ingress Service MUST change from `type: LoadBalancer` to `type: ClusterIP`. The Standard SKU public LB IP is released. |
| **FR-12** | The Splunk NSG's `8000/tcp` rule MUST be removed (Cloudflare Tunnel is now the only path to the UI). The `22/tcp` operator rule MAY stay OR move to Cloudflare's SSH tunnel too (operator preference). |

### Infrastructure as code

| ID | Requirement |
|---|---|
| **FR-13** | Cloudflare resources MUST be managed by the `cloudflare/cloudflare` Terraform provider (`~> 4.x`). No click-ops. |
| **FR-14** | A Cloudflare API token scoped to `Zone.Zone Read`, `Zone.DNS Edit`, `Account.Cloudflare Tunnel Edit`, and `Account.Access: Apps and Policies Edit` MUST be stored in Azure Key Vault as `cloudflare-api-token`. |

---

## 4. Non-Functional Requirements

| ID | Requirement | Threshold |
|---|---|---|
| **NFR-1** (cost) | Monthly run-cost MUST be less than the v1 cost (i.e. net negative). | ≤ v1 cost − $20 |
| **NFR-2** (security) | No origin host MAY expose the app port (8000 for Splunk, 443 for chatbot) to the public internet. | `nmap` from external scanner returns no open port |
| **NFR-3** (latency) | Cloudflare-added latency on chat responses SHOULD be under 100 ms p95. | p95 < 100 ms |
| **NFR-4** (availability) | Tunnel MUST auto-reconnect on network blip. `cloudflared` handles this natively; no extra work. | Observed via Splunk |

---

## 5. Acceptance Criteria (Given / When / Then)

| ID | Criterion | Refs |
|---|---|---|
| **AC-1** | **Given** a visitor from `@cisco.com`, **When** they navigate to `money-honey.mariojruiz.com`, **Then** they see Cloudflare's Access login, authenticate via Google/Microsoft, and land on the chatbot. | FR-6, FR-8 |
| **AC-2** | **Given** a visitor from `@outlook.com` (not in allowlist), **When** they try the same URL, **Then** Cloudflare Access rejects them with a clear error. | FR-6, FR-8 |
| **AC-3** | **Given** tunnels are live, **When** `nmap` scans the AKS LB IP, **Then** no port is open. | NFR-2, FR-11 |
| **AC-4** | **Given** tunnels are live, **When** `nmap` scans the Splunk VM's former IP, **Then** the IP no longer resolves or is not assigned. | FR-10, NFR-2 |
| **AC-5** | **Given** a `cloudflared` pod is killed, **When** Kubernetes restarts it, **Then** the tunnel reconnects within 60 seconds with no manual step. | NFR-4 |

---

## 6. Edge Cases

| ID | Scenario | Expected behavior |
|---|---|---|
| **EC-1** | Cloudflare API token leaked | Rotate immediately via Cloudflare dashboard → push new value to KV → restart `cloudflared`. |
| **EC-2** | Azure DNS delegation drifts (TTL expiry, NS typo) | Cloudflare Access shows "domain not on Cloudflare" error. Operator re-validates NS records. |
| **EC-3** | AKS cluster is unreachable (cluster down, network issue) | Cloudflare Access shows origin unreachable. Users see 502 from Cloudflare's edge. |
| **EC-4** | A cisco.com employee's email is disabled | Cloudflare Access rejects on next session refresh (≤ 24 h). |
| **EC-5** | User wants to demo at Cisco Live without WiFi stable enough for Cloudflare auth | Operator temporarily adds their IP to a bypass policy; removes after demo. |

---

## 7. API Contracts (Terraform inputs/outputs)

```hcl
// New variables (cloudflare.tf)
variable "cloudflare_account_id" {
  type        = string
  description = "Cloudflare account ID. Read at apply time via `cloudflared tunnel create` or dashboard."
}

variable "cloudflare_zone_id" {
  type        = string
  description = "Zone ID for money-honey.mariojruiz.com (delegated subdomain)."
}

variable "access_email_domains" {
  type        = list(string)
  description = "Email domains allowed through Cloudflare Access. Applies to both chatbot and Splunk."
  default     = ["cisco.com", "gmail.com"]
}

// New outputs
output "chatbot_public_url"  { value = "https://money-honey.mariojruiz.com" }
output "splunk_public_url"   { value = "https://splunk.money-honey.mariojruiz.com" }
output "tunnel_chatbot_id"   { value = cloudflare_tunnel.chatbot.id }
output "tunnel_splunk_id"    { value = cloudflare_tunnel.splunk.id }
```

---

## 8. Data Models (new resources)

| Resource | Terraform type | Count |
|---|---|---|
| Delegated DNS zone (Cloudflare side) | `cloudflare_zone` | 1 (subdomain) |
| Access application (chatbot) | `cloudflare_access_application` | 1 |
| Access application (Splunk) | `cloudflare_access_application` | 1 |
| Access policy | `cloudflare_access_policy` | 2 (one per app) |
| Named tunnel (chatbot) | `cloudflare_tunnel` | 1 |
| Named tunnel (Splunk) | `cloudflare_tunnel` | 1 |
| Tunnel config | `cloudflare_tunnel_config` | 2 |
| DNS records | `cloudflare_record` | 2 (CNAMEs to `<tunnel-id>.cfargotunnel.com`) |
| KV secret (Cloudflare API token) | `azurerm_key_vault_secret` | 1 |
| KV secret (tunnel credentials) | `azurerm_key_vault_secret` | 2 |

**Total additions: ~13 resources.**

**Removals:** `azurerm_public_ip.splunk`, LB Service type → ClusterIP, Splunk NSG `8000/tcp` rule.

---

## 9. Out of Scope (v2 itself)

| ID | Excluded | When |
|---|---|---|
| **OS-1** | Cloudflare WAF rules | v3 — only needed if we see attack traffic |
| **OS-2** | Cloudflare Workers / edge logic | v3 |
| **OS-3** | Per-user audit trail from Cloudflare to Splunk | v3 (would need Cloudflare Logpush) |
| **OS-4** | SSH-via-Cloudflare (replacing port 22) | v2.1 — nice-to-have, not required |
| **OS-5** | Multi-identity providers (Okta, Azure AD) | v3 |

---

## 10. Manual / one-time steps

Before `terraform apply` can succeed:

1. Create a free Cloudflare account (or use existing)
2. Add `money-honey.mariojruiz.com` as a zone (**not** the parent `mariojruiz.com`)
3. Copy the two NS records Cloudflare assigns
4. In Azure Portal → DNS zones → `mariojruiz.com` → create an NS record set named `money-honey` pointing at Cloudflare's NS servers
5. Create a Cloudflare API token with scopes listed in FR-14; store it in Key Vault as `cloudflare-api-token`
6. Find the Cloudflare Account ID and Zone ID (visible on dashboard), supply as Terraform variables

---

## 11. File layout (v2)

```
infra/terraform/
├── cloudflare.tf           # NEW — provider + access apps + tunnels
└── (existing files updated: splunk-vm.tf drops public IP, keyvault.tf adds tokens)

k8s/cloudflared/            # NEW — cloudflared Deployment + ConfigMap
├── deployment.yaml
└── configmap.yaml
```

---

## 12. Cost impact

| Item | v1 | v2 | Delta |
|---|---|---|---|
| Standard LB + public IP (AKS) | $18 | $0 | **−$18** |
| Splunk VM public IP | $3.60 | $0 | **−$3.60** |
| Cloudflare Access + Tunnel | — | $0 (free tier) | 0 |
| **Net monthly change** | | | **−$21.60** |

---

## 13. Order of operations

1. v1 (current build) ships public — validates the whole stack works end-to-end
2. Add cloudflared + Access apps **in parallel** with the public path (zero-downtime migration)
3. Confirm Cloudflare-fronted URLs work with real cisco.com / gmail.com logins
4. Flip DNS: point `money-honey.mariojruiz.com` to the Cloudflare tunnel
5. Drop the Azure LB public IP and Splunk public IP
6. Celebrate the cost savings 🎉
