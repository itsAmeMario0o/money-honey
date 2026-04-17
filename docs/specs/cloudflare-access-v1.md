# 🔐 Spec: Cloudflare Tunnel + Zero Trust (v1)

## 1. Title and Metadata

| Field | Value |
|---|---|
| Feature | Identity-gated edge for Money Honey chatbot and Splunk dashboard |
| Author | Mario Ruiz + Claude Code |
| Status | 🚧 In progress. Tunnels created in Cloudflare dashboard; wiring into Terraform + install scripts now. |
| Reviewers | Mario Ruiz |
| Skills used | `spec-driven-workflow`, `cloud-security`, `senior-secops`, `terraform-patterns` |
| Depends on | `docs/specs/infra-v1.md`, `docs/specs/chatbot-v1.md` |

---

## 2. Context

Money Honey exposes two apps that need to be reachable from outside the cluster:

1. Chatbot: FastAPI + React behind Caddy in AKS
2. Splunk dashboard: Web UI on port 8000 of the Ubuntu VM

The v1 path uses Cloudflare Tunnel (via `cloudflared`) running on each origin. Each origin dials outbound to the Cloudflare edge, so the origins need no public inbound app ports. Cloudflare Zero Trust Free tier covers everything needed: two tunnels, Access apps, email-domain policies.

Account state (done manually by operator):
- Zero Trust Free plan enabled
- Team domain assigned: `money-honey.cloudflareaccess.com`
- Two named tunnels created:
  - `money-honey-splunk` (Debian target, runs on the Splunk VM)
  - `money-honey-chatbot` (Docker target, runs as a K8s Deployment)
- Connector tokens saved locally by operator; values will be placed in Azure Key Vault

Open question (deferred to after tunnels connect): how to attach a clickable URL to each tunnel. Options: add a Cloudflare zone (any domain added to CF DNS), buy a domain on Cloudflare Registrar ($10/yr), or use an Access Self-Hosted Application via the team domain. We decide once the tunnels show green.

---

## 3. Functional Requirements (RFC 2119)

### Token storage

| ID | Requirement |
|---|---|
| FR-1 | Two `azurerm_key_vault_secret` resources MUST be declared with names `cloudflare-tunnel-splunk-token` and `cloudflare-tunnel-chatbot-token`. |
| FR-2 | Both secrets MUST use `lifecycle { ignore_changes = [value, version] }` so the operator-supplied token values never appear in Terraform state updates. |
| FR-3 | Secret values MUST be set out-of-band via `az keyvault secret set` or the Azure Portal. They MUST NOT appear in any file under version control. |

### Origin: Splunk VM

| ID | Requirement |
|---|---|
| FR-4 | `install-splunk.sh` MUST install the `cloudflared` Debian package from `https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb`. |
| FR-5 | After installation, `install-splunk.sh` MUST run `cloudflared service install "$CLOUDFLARED_TOKEN"` where `CLOUDFLARED_TOKEN` is an env var the operator supplies (sourced from Key Vault). |
| FR-6 | The Splunk NSG MUST NOT expose port `8000/tcp` to any inbound source. The tunnel handles UI reachability. |
| FR-7 | The Splunk VM MAY keep its public IP for SSH administration. SSH (`22/tcp`) stays scoped to the operator IP only. |

### Origin: AKS chatbot (implemented in step 4, not here)

| ID | Requirement |
|---|---|
| FR-8 | A `cloudflared` Deployment MUST run in the AKS cluster, reading its connector token from the Key Vault via CSI. (Step 4.) |
| FR-9 | The Caddy Service MUST be `type: ClusterIP` in step 4. No public LoadBalancer IP. |

### Access policies (deferred, tunnel connectivity first)

| ID | Requirement |
|---|---|
| FR-10 | Once clickable URLs exist, each tunnel MUST be fronted by a Cloudflare Access Self-Hosted Application with policy "allow if email in `var.access_email_domains`". Defaults: `["cisco.com", "gmail.com"]`. |

---

## 4. Non-Functional Requirements

| ID | Requirement | Threshold |
|---|---|---|
| NFR-1 (security) | Tunnel tokens MUST NOT appear in logs, shell history exports, or Terraform state. | 0 occurrences |
| NFR-2 (availability) | `cloudflared` systemd unit MUST auto-restart on failure (native cloudflared behavior). | Verified via `systemctl` |
| NFR-3 (cost) | Cloudflare Zero Trust Free plan is $0/month. Credit card is on file for verification only. | $0 / 50 users |

---

## 5. Acceptance Criteria (Given / When / Then)

| ID | Criterion | Refs |
|---|---|---|
| AC-1 | Given tokens are set in KV, When the operator runs `install-splunk.sh` with `CLOUDFLARED_TOKEN` exported, Then `cloudflared` is installed as a systemd service and the tunnel shows HEALTHY on the Cloudflare dashboard within 60 seconds. | FR-4, FR-5 |
| AC-2 | Given the Splunk tunnel is healthy, When the operator scans the Splunk VM's public IP on port `8000`, Then the port is closed (NSG block). | FR-6 |
| AC-3 | Given both tunnel secrets exist in KV, When the operator runs `terraform plan`, Then no secret value is shown in the plan output, only `(known after apply)` for newly created secrets and `(sensitive)` thereafter. | FR-2, NFR-1 |
| AC-4 | Given the operator accidentally commits a `terraform.tfvars` containing a token, When they run `git commit`, Then the pre-commit hook (gitleaks) blocks the commit. | NFR-1 |

---

## 6. Edge Cases

| ID | Scenario | Expected behavior |
|---|---|---|
| EC-1 | Tunnel token is rotated in Cloudflare | Operator updates the KV secret; `cloudflared` picks up on service restart. `terraform plan` still shows no drift. |
| EC-2 | Operator loses the token | Rotate: delete the tunnel in Cloudflare, create a new one, store the new token. |
| EC-3 | `cloudflared` can't reach Cloudflare (firewall between VM and internet) | Systemd keeps retrying. Operator confirms outbound `443/tcp` egress from the VM is allowed. |
| EC-4 | Token leaks in chat / docs / git log | Rotate immediately. `git filter-repo` to scrub if committed (same pattern as the subscription-ID incident). |

---

## 7. API Contracts

No Cloudflare Terraform provider in v1. Tunnels and Access apps are created in the Cloudflare dashboard. Terraform's job is narrow: store tokens in KV and expose them to origins.

```hcl
// keyvault.tf — new secret shells
resource "azurerm_key_vault_secret" "cloudflare_tunnel_splunk_token" {
  name            = "cloudflare-tunnel-splunk-token"
  value           = "set-me-in-portal"
  key_vault_id    = azurerm_key_vault.money_honey.id
  content_type    = "text/plain"
  expiration_date = "2027-01-01T00:00:00Z"

  lifecycle { ignore_changes = [value, version] }
  depends_on = [azurerm_key_vault_access_policy.operator]
}

resource "azurerm_key_vault_secret" "cloudflare_tunnel_chatbot_token" {
  # identical shape, different name
}
```

---

## 8. Data Models (additions to v1 infra)

| Resource | Terraform type | Count |
|---|---|---|
| KV secret (Splunk tunnel token) | `azurerm_key_vault_secret` | 1 |
| KV secret (chatbot tunnel token) | `azurerm_key_vault_secret` | 1 |

Removed: the NSG `security_rule` for `8000/tcp` ingress is deleted from `splunk-vm.tf`.

---

## 9. Out of Scope (this spec)

| ID | Excluded | When |
|---|---|---|
| OS-1 | Full Cloudflare IaC via `cloudflare/cloudflare` provider | Later. v1 is manual in dashboard, Terraform only touches tokens. |
| OS-2 | Clickable URL routing (Access Self-Hosted Application config) | After tunnels show green; dashboard step |
| OS-3 | SSH-via-Cloudflare tunnel | Later. Keep public-IP SSH for v1. |
| OS-4 | Cloudflare WARP client for operator-only access | Not needed |
| OS-5 | AKS LoadBalancer removal | Lives in step 4 spec (k8s manifests) |

---

## 10. Self-Review Checklist

- [x] Every FR has at least one AC
- [x] No secret values in code or state
- [x] Pre-commit hook enforces NFR-1
- [x] Edge cases cover token rotation + leak scenarios
- [x] Out of Scope is explicit about what's deferred
- [x] No DNS or zone requirements (removed from earlier draft)

---

## 11. Operator runbook (after Terraform applies)

```bash
# Set the tokens in Key Vault (one time, from your terminal)
az keyvault secret set \
  --vault-name $(terraform -chdir=infra/terraform output -raw key_vault_name) \
  --name cloudflare-tunnel-splunk-token \
  --value "eyJ...splunk-token-from-password-manager..."

az keyvault secret set \
  --vault-name $(terraform -chdir=infra/terraform output -raw key_vault_name) \
  --name cloudflare-tunnel-chatbot-token \
  --value "eyJ...chatbot-token-from-password-manager..."

# Install Splunk + cloudflared on the VM
VM_IP=$(terraform -chdir=infra/terraform output -raw splunk_vm_public_ip)
CLOUDFLARED_TOKEN=$(az keyvault secret show \
  --vault-name $(terraform -chdir=infra/terraform output -raw key_vault_name) \
  --name cloudflare-tunnel-splunk-token --query value -o tsv)

VM_IP=$VM_IP \
  SPLUNK_ADMIN_PASSWORD='your-strong-password' \
  CLOUDFLARED_TOKEN=$CLOUDFLARED_TOKEN \
  infra/scripts/install-splunk.sh

# Verify tunnel on the dashboard, should show HEALTHY within ~60s
```
