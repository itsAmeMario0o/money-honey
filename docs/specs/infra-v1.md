# 🏗️ Spec: Money Honey Infrastructure v1

## 1. Title and Metadata

| Field | Value |
|---|---|
| **Feature** | Azure infrastructure v1 (Terraform, plan-only) |
| **Author** | Mario Ruiz + Claude Code |
| **Status** | ✅ Approved — proceeding to implementation (commits B–F) |
| **Reviewers** | Mario Ruiz |
| **Skills used** | `spec-driven-workflow`, `terraform-patterns`, `azure-cloud-architect` |
| **Subscription** | Supplied at runtime via `az login` + `az account set`. Never pinned in code. |
| **Depends on** | `docs/specs/chatbot-v1.md` (application layer) |

---

## 2. Context

Step 3 of the build plan defines every Azure resource Money Honey needs as Terraform code. **No `terraform apply` runs during this step** — the deliverable is a valid `terraform plan` against the real subscription.

CLAUDE.md §"Tech Stack" and §"Architecture Decisions" pin the choices:
- Managed AKS with Azure CNI powered by Cilium (no BYOCNI, no Hubble, no ACNS) — lines 202–212
- Tetragon installed via Helm, chart `1.3.0` — lines 217–218
- Worker nodes: 3× `Standard_B2als_v2` — line 221
- Splunk on its own VM (`Standard_B2ms`) — lines 351–353
- Squarespace CNAME is managed manually; Terraform only outputs the LB IP — line 196

**Why Terraform and not Bicep:** CLAUDE.md line 192 pins Terraform. The `azure-cloud-architect` skill's Bicep examples translate 1:1 to `azurerm` resources.

---

## 3. Functional Requirements (RFC 2119)

### Resource group + state

| ID | Requirement |
|---|---|
| **FR-1** | Terraform MUST read the subscription from the operator's active `az login` session (or `ARM_SUBSCRIPTION_ID` env var). Subscription ID MUST NOT appear in any file under version control. |
| **FR-2** | All resources MUST live in a single resource group named `money-honey-rg` in region `eastus`. |
| **FR-3** | Terraform state MUST be stored in an Azure Storage Account container (remote backend). The storage account itself MUST be created by a separate `infra/terraform-bootstrap/` module that uses LOCAL state (resolves the chicken-and-egg). The bootstrap module also grants the signed-in operator `Storage Blob Data Contributor` on the state SA. |
| **FR-4** | The state backend MUST have blob versioning and soft-delete enabled. |

### AKS cluster

| ID | Requirement |
|---|---|
| **FR-5** | The cluster name MUST be `money-honey-aks`. |
| **FR-6** | Kubernetes version MUST be `1.34` or newer (line 184). |
| **FR-7** | The cluster MUST use `network_plugin = "azure"`, `network_plugin_mode = "overlay"`, `network_data_plane = "cilium"`, `network_policy = "cilium"` (line 287). |
| **FR-8** | The default node pool MUST have 3 nodes of SKU `Standard_B2als_v2` (line 221). |
| **FR-9** | The cluster MUST use System-Assigned Managed Identity (no service principal passwords, line 59). |
| **FR-10** | RBAC MUST be enabled with Azure AD integration (Entra ID). |
| **FR-11** | The cluster MUST have the `azurekeyvaultsecretsprovider` (CSI Secret Store Driver) add-on enabled. |
| **FR-12** | The cluster's load balancer MUST be SKU `Standard` with a static public IP for the ingress. |

### Key Vault

| ID | Requirement |
|---|---|
| **FR-13** | A Key Vault named `mh-kv-<random-suffix>` MUST be created in the same resource group. |
| **FR-14** | The Key Vault MUST grant `get`/`list` on secrets to the AKS kubelet Managed Identity (used by the CSI driver). |
| **FR-15** | Key Vault MUST enable soft-delete and purge protection. |
| **FR-16** | `ANTHROPIC_API_KEY` and `SPLUNK_HEC_TOKEN` MUST be declared as `azurerm_key_vault_secret` resources with `lifecycle.ignore_changes = [value]` so the actual values are set manually in the Azure portal, never committed to state. (Embeddings run locally — no embedding API key needed.) |

### Tetragon (Helm)

| ID | Requirement |
|---|---|
| **FR-17** | Tetragon MUST be installed via `helm_release`, chart `tetragon` version `1.3.0` from `https://helm.cilium.io`, namespace `kube-system` (lines 298–318). |
| **FR-18** | Helm values MUST set: `tetragon.enableProcessCred=true`, `tetragon.enableProcessNs=true`, `tetragon.prometheus.enabled=true`, `tetragon.prometheus.port=2112`, `tetragon.prometheus.serviceMonitor.enabled=false`, `rthooks.enabled=true`, `rthooks.interface=oci-hooks`, plus resource requests/limits (CPU `100m`/`500m`, memory `128Mi`/`512Mi`). |

### Splunk VM

| ID | Requirement |
|---|---|
| **FR-19** | A **Ubuntu 22.04 LTS (Jammy)** VM of SKU `Standard_B2ms` named `money-honey-splunk` MUST be created with an attached `64 GB` Standard SSD (line 352). The OS image MUST be `Canonical / 0001-com-ubuntu-server-jammy / 22_04-lts-gen2`, pinned by version (not `latest`). |
| **FR-20** | The VM MUST use SSH key authentication only (no password). Terraform MUST generate a fresh RSA 4096-bit keypair using the `tls_private_key` resource. The public key MUST be written to the VM's `admin_ssh_key` block. |
| **FR-21** | The VM's NSG MUST allow inbound `22/tcp` and `8000/tcp` (Splunk Web) only from the operator's current public IP, auto-detected at plan time via the `http` data source against `https://api.ipify.org` (IP returned as `/32`). An optional variable `admin_source_cidr_override` MAY be set to bypass auto-detection (e.g. for CI). `8088/tcp` (HEC) MUST be allowed only from the AKS node subnet CIDR. |
| **FR-27** | AKS and the Splunk VM MUST live in the same VNet so AKS worker nodes have L3 reachability to Splunk with no peering, no public hop, and no Private Link. One VNet `money-honey-vnet` (CIDR `10.0.0.0/16`) MUST contain two subnets: `aks-nodes` (`10.0.0.0/22`, used by the AKS default node pool) and `splunk` (`10.0.4.0/28`, used by the Splunk VM NIC). |
| **FR-28** | The Splunk NSG's `8088/tcp` ingress rule source prefix MUST be the `aks-nodes` subnet CIDR (`10.0.0.0/22`). The NSG MUST NOT expose `8088/tcp` to the public internet or to the operator IP. |
| **FR-29** | The AKS cluster's default node pool MUST attach to the `aks-nodes` subnet via `vnet_subnet_id`, so worker node primary IPs fall in `10.0.0.0/22` and match FR-28's source prefix. |
| **FR-22** | Splunk itself is NOT installed by Terraform. A companion script `infra/scripts/install-splunk.sh` is delivered as-is and runs manually via SSH in step 7 (deploy). |
| **FR-25** | The generated SSH private key MUST be written to `infra/private_key/splunk.pem` (file permissions `0600`) via the `local_sensitive_file` resource. This is the sole on-disk persistence mechanism. The `infra/private_key/` folder MUST be listed in `.gitignore` before any `terraform apply` runs. |
| **FR-26** | If the local key file is lost, the operator MUST be able to recover it with `terraform output -raw splunk_ssh_private_key > infra/private_key/splunk.pem && chmod 600 infra/private_key/splunk.pem`. The `splunk_ssh_private_key` output MUST be marked `sensitive = true`. |

### DNS / outputs

| ID | Requirement |
|---|---|
| **FR-23** | Terraform MUST output `aks_cluster_name`, `resource_group_name`, `key_vault_uri`, `splunk_vm_public_ip`, and `ingress_public_ip` (once the k8s LB service is created in step 4; in v1 this output is null). |
| **FR-24** | DNS records in Squarespace are set manually. Terraform MUST NOT manage Squarespace. |

---

## 4. Non-Functional Requirements

| ID | Requirement | Threshold |
|---|---|---|
| **NFR-1** (security) | No secret values MUST appear in `.tf` files, `terraform.tfvars`, or state blobs. | 0 findings in `tfsec` / `gitleaks` |
| **NFR-2** (security) | All storage, Key Vault, and databases MUST have encryption at rest enabled. | 100% |
| **NFR-3** (security) | NSG rules MUST NOT allow `0.0.0.0/0` on management ports (`22`, `8000`). | 0 findings |
| **NFR-4** (repeatability) | `terraform plan` MUST be clean (0 changes) on a second run immediately after apply. | 0 drift |
| **NFR-5** (versioning) | `azurerm`, `helm`, `kubernetes`, and `random` providers MUST be pinned with the pessimistic operator (`~>`). | All providers pinned |
| **NFR-6** (cost) | Monthly run-cost MUST stay within ±10% of the CLAUDE.md estimate (~$153–155/month when running). | ≤ $170/month |
| **NFR-7** (portability) | The root module MUST accept `location` and `environment` variables so the whole stack can be redeployed in another region or named `prod` later. | Variable-driven |

---

## 5. Acceptance Criteria (Given / When / Then)

| ID | Criterion | Refs |
|---|---|---|
| **AC-1** | **Given** no Azure resources exist, **When** an operator runs `infra/scripts/bootstrap-state.sh`, **Then** a storage account + container for Terraform state is created and the container name is printed. | FR-3 |
| **AC-2** | **Given** state backend exists, **When** `terraform init` runs in `infra/terraform/`, **Then** it succeeds and downloads `azurerm`, `helm`, `kubernetes`, `random` providers. | FR-1, NFR-5 |
| **AC-3** | **Given** `terraform init` succeeded, **When** `terraform plan` runs, **Then** it exits 0 and proposes creating: 1 RG, 1 AKS, 1 KV, 2 KV secrets (with ignored values), 1 Helm release, 1 Ubuntu VM + NSG + PIP + NIC + disk + `tls_private_key` + `local_sensitive_file`. | FR-2, FR-5, FR-13, FR-17, FR-19, FR-25 |
| **AC-4** | **Given** the plan output, **When** reviewed, **Then** no resource has a hardcoded secret value. | NFR-1 |
| **AC-5** | **Given** the plan output, **When** reviewed, **Then** AKS has `network_data_plane = "cilium"`. | FR-7 |
| **AC-6** | **Given** the plan output, **When** reviewed, **Then** the Tetragon `helm_release` pins `version = "1.3.0"` and sets all required values from FR-18. | FR-17, FR-18 |
| **AC-7** | **Given** the plan output, **When** reviewed, **Then** the Splunk NSG's `22/tcp` rule source prefix is a single IP `/32` obtained from the `http` data source (not `0.0.0.0/0`). | FR-21, NFR-3 |
| **AC-13** | **Given** the plan output, **When** reviewed, **Then** one VNet `money-honey-vnet` (CIDR `10.0.0.0/16`) exists with subnets `aks-nodes` (`10.0.0.0/22`) and `splunk` (`10.0.4.0/28`). | FR-27 |
| **AC-14** | **Given** the plan output, **When** reviewed, **Then** the AKS default node pool sets `vnet_subnet_id` to the `aks-nodes` subnet. | FR-29 |
| **AC-15** | **Given** the plan output, **When** reviewed, **Then** the Splunk NSG's `8088/tcp` rule has source prefix `10.0.0.0/22` (the `aks-nodes` subnet) and destination port `8088`. | FR-28 |
| **AC-11** | **Given** a successful `terraform apply`, **When** the operator inspects `infra/private_key/splunk.pem`, **Then** the file exists with permissions `0600` and the folder is listed in `.gitignore`. | FR-25 |
| **AC-12** | **Given** the local key file is deleted, **When** `terraform output -raw splunk_ssh_private_key` runs, **Then** a valid RSA private key in PEM format is returned. | FR-26 |
| **AC-8** | **Given** `terraform validate` runs, **When** executed, **Then** it exits 0. | NFR-5 |
| **AC-9** | **Given** `tfsec` runs on the module, **When** executed, **Then** it reports 0 HIGH or CRITICAL findings. | NFR-1, NFR-2, NFR-3 |
| **AC-10** | **Given** outputs are declared, **When** `terraform output` runs after apply, **Then** the five names in FR-23 are present. | FR-23 |

---

## 6. Edge Cases

| ID | Scenario | Expected behavior |
|---|---|---|
| **EC-1** | State container already exists when `bootstrap-state.sh` runs | Script detects and exits 0 with an informational message. |
| **EC-2** | `https://api.ipify.org` is unreachable at plan time | `http` data source fails. Operator sets `admin_source_cidr_override` to unblock. |
| **EC-3** | Key Vault name collides globally (KV names are Azure-wide unique) | `random_string` suffix appended (FR-13). |
| **EC-4** | Tetragon Helm chart `1.3.0` is removed from the repo | Plan fails with a clear error. Operator pins a new version and updates spec. |
| **EC-5** | AKS quota exhausted in the region | `terraform apply` fails with a quota error. Operator requests a quota increase — no retry logic needed. |
| **EC-6** | Operator runs `plan` from a different machine | Remote state backend ensures consistency. No local state file exists. |
| **EC-7** | Secret value changes manually in the Azure portal | `lifecycle.ignore_changes = [value]` keeps Terraform from reverting it. |
| **EC-8** | Operator's IP changes (coffee shop WiFi) | NSG stops allowing SSH. Operator re-runs `terraform apply`; `http` data source refreshes the IP and the NSG rule updates. |
| **EC-9** | Two operators apply from different IPs in sequence | The NSG rule toggles to whichever operator ran `apply` most recently. Expected behavior — only one operator has SSH access at a time. |
| **EC-10** | Operator loses `infra/private_key/splunk.pem` | Recover from Terraform state: `terraform output -raw splunk_ssh_private_key > infra/private_key/splunk.pem && chmod 600 infra/private_key/splunk.pem`. |

---

## 7. API Contracts

Terraform has no HTTP API, but the module's **input and output interface** is the contract:

```hcl
# Inputs (variables.tf)
variable "subscription_id"     { type = string }
variable "resource_group_name" { type = string, default = "money-honey-rg" }
variable "location"            { type = string, default = "eastus" }
variable "environment"         { type = string, default = "demo" }

variable "cluster_name"        { type = string, default = "money-honey-aks" }
variable "kubernetes_version"  { type = string, default = "1.34" }
variable "node_count"          { type = number, default = 3 }
variable "node_sku"            { type = string, default = "Standard_B2als_v2" }

variable "key_vault_name_prefix" { type = string, default = "mh-kv" }

variable "tetragon_chart_version" { type = string, default = "1.3.0" }

variable "splunk_vm_sku"        { type = string, default = "Standard_B2ms" }
variable "splunk_disk_gb"       { type = number, default = 64 }
variable "splunk_image_publisher" { type = string, default = "Canonical" }
variable "splunk_image_offer"     { type = string, default = "0001-com-ubuntu-server-jammy" }
variable "splunk_image_sku"       { type = string, default = "22_04-lts-gen2" }
variable "splunk_image_version"   { type = string, default = "22.04.202410020" }  # pinned; bump deliberately
# SSH keypair is generated by Terraform — no operator-supplied key path
# Admin source CIDR is auto-detected from https://api.ipify.org at plan time
variable "admin_source_cidr_override" { type = string, default = null }  # optional, for CI

# Outputs (outputs.tf)
output "aks_cluster_name"     { value = azurerm_kubernetes_cluster.money_honey.name }
output "resource_group_name"  { value = azurerm_resource_group.money_honey.name }
output "key_vault_uri"        { value = azurerm_key_vault.money_honey.vault_uri }
output "splunk_vm_public_ip"  { value = azurerm_public_ip.splunk.ip_address }
output "splunk_ssh_private_key" {
  value     = tls_private_key.splunk.private_key_pem
  sensitive = true  # for recovery via `terraform output -raw splunk_ssh_private_key`
}
output "ingress_public_ip"    { value = null }  # populated in step 4
```

---

## 8. Data Models (resource inventory)

| Resource | Terraform type | Count |
|---|---|---|
| Resource group | `azurerm_resource_group` | 1 |
| Log analytics workspace (optional, for diagnostic settings) | `azurerm_log_analytics_workspace` | 1 |
| AKS cluster | `azurerm_kubernetes_cluster` | 1 |
| Key Vault | `azurerm_key_vault` | 1 |
| Key Vault secret (API key placeholders) | `azurerm_key_vault_secret` | 2 (`anthropic`, `splunk-hec`) |
| SSH keypair generation | `tls_private_key` | 1 |
| Local private-key file (gitignored) | `local_sensitive_file` | 1 |
| Operator IP lookup | `http` data source | 1 |
| Key Vault access policy (kubelet MI) | `azurerm_key_vault_access_policy` | 1 |
| Tetragon Helm release | `helm_release` | 1 |
| Splunk VM (Ubuntu 22.04 LTS) | `azurerm_linux_virtual_machine` | 1 |
| Splunk NIC | `azurerm_network_interface` | 1 |
| Splunk public IP | `azurerm_public_ip` | 1 |
| Splunk OS disk (implicit) | — | 1 |
| Splunk data disk | `azurerm_managed_disk` + attach | 1 |
| Shared VNet (AKS + Splunk) | `azurerm_virtual_network` | 1 (`10.0.0.0/16`) |
| Subnets | `azurerm_subnet` | 2 (`aks-nodes` 10.0.0.0/22, `splunk` 10.0.4.0/28) |
| Splunk NSG + rules | `azurerm_network_security_group` + 3 rules | 1 NSG, 3 rules |
| Random suffix for KV name | `random_string` | 1 |

**Total: ~17 resources.**

---

## 9. Out of Scope (v1)

| ID | Excluded | Why / when |
|---|---|---|
| **OS-1** | Multiple environments (dev/staging/prod) | Single environment. Use workspaces in v2 if needed. |
| **OS-2** | ACR (private container registry) | Using GHCR (CLAUDE.md line 194). |
| **OS-3** | ACNS (Hubble, FQDN filtering, L7 policies) | CLAUDE.md deferred to v2 (line 471). |
| **OS-4** | Isovalent Enterprise | Deferred to v2 (line 471). |
| **OS-5** | Splunk installation automation | Manual via `install-splunk.sh` in step 7. |
| **OS-6** | Squarespace DNS management | Manual (CLAUDE.md line 196). |
| **OS-7** | Secret rotation automation | Deferred to v2 (line 477). |
| **OS-8** | Azure DevOps pipelines | Using GitHub Actions (CLAUDE.md line 193). |
| **OS-9** | Diagnostic settings / Azure Monitor | Telemetry goes to Splunk; Azure Monitor is v2. |
| **OS-10** | Backup / disaster recovery | Demo project. Rebuild from code in 15 min. |
| **OS-11** | *(moved into v1)* Cloudflare Tunnel + Access is now part of v1 — see [`cloudflare-access-v1.md`](./cloudflare-access-v1.md). Splunk NSG drops `8000/tcp`; tunnel token secrets are added to Key Vault. Clickable URL routing is still open. |

---

## 10. Self-Review Checklist

- [x] Every FR has at least one AC
- [x] Every AC references at least one FR or NFR
- [x] Inputs and outputs documented (§7)
- [x] All resources enumerated (§8)
- [x] Edge cases cover external deps (state backend, Helm repo, SSH keys, quotas)
- [x] Out of Scope is explicit
- [x] NFRs have measurable thresholds
- [x] RFC 2119 keywords used

---

## 11. File layout (to be created after spec approval)

```
infra/
├── terraform/
│   ├── versions.tf              # terraform {}, required_providers
│   ├── providers.tf             # azurerm, helm, kubernetes provider configs
│   ├── variables.tf             # all inputs from §7
│   ├── outputs.tf               # all outputs from §7
│   ├── terraform.tfvars.example # sample values, no secrets
│   ├── main.tf                  # resource group + random_string
│   ├── aks.tf                   # AKS cluster per FR-5..FR-12
│   ├── keyvault.tf              # KV + access policy + secret placeholders
│   ├── tetragon.tf              # helm_release per FR-17..FR-18
│   ├── splunk-vm.tf             # VM + NIC + NSG + PIP + disk
│   ├── network.tf               # VNet + subnets (if not reusing AKS VNet)
│   └── backend.tf               # Azure Blob state config
├── scripts/
│   ├── bootstrap-state.sh       # one-time storage account for TF state
│   ├── tf-init.sh               # wraps `terraform init`
│   ├── tf-plan.sh               # wraps `terraform plan`
│   └── install-splunk.sh        # manual post-apply script for Splunk VM
└── private_key/
    ├── .gitkeep                 # the only file that ever gets committed here
    └── splunk.pem               # ⚠️ generated by terraform apply — gitignored
```

Note: `infra/private_key/` is added to `.gitignore` (pattern `infra/private_key/*` with `!.gitkeep` exception) before the first `terraform apply`.

---

## 12. Bounded autonomy decisions

Per `spec-driven-workflow` §Bounded Autonomy, these items would require STOP-and-ask if they came up:

- 🛑 **State backend creation.** This is a chicken-and-egg problem — the script runs `az` CLI, which touches shared state. Proposing `bootstrap-state.sh` as a one-time manual step to keep it visible.
- ✅ **Operator IP auto-detection** via `http` data source is safe — the IP is always scoped to `/32`, never `0.0.0.0/0`. If the lookup fails (EC-2), `admin_source_cidr_override` is the escape hatch.
- ✅ **Private key in state.** Yes, the `tls_private_key.private_key_pem` attribute lives in Terraform state. Mitigations: (1) state is in an encrypted Azure Blob with access-controlled, (2) local file copy is `0600` and gitignored, (3) state serves as the authoritative backup for recovery (EC-10). Acceptable for a demo; revisit if we ever handle real prod secrets.
- ✅ **All other values** have safe defaults from CLAUDE.md and can proceed autonomously after spec approval.
