// AKS cluster with Azure CNI powered by Cilium (managed, not BYOCNI).
// Configuration is locked to the values pinned in CLAUDE.md §Architecture
// Decisions and docs/specs/infra-v1.md (FR-5 through FR-12, FR-29).

// Client context is used for tenant ID and current user object ID (KV admin).
data "azurerm_client_config" "current" {}

# tfsec:ignore:azure-container-logging -- Splunk (via Fluent Bit + OTel) is the log pipeline, not Azure Monitor. See CLAUDE.md Layer 7.
# tfsec:ignore:azure-container-limit-authorized-ips -- tfsec v1.28 checks the legacy api_server_authorized_ip_ranges attribute; we use api_server_access_profile.authorized_ip_ranges (AzureRM 4.x) which is equivalent and set to local.operator_ip_cidr below.
resource "azurerm_kubernetes_cluster" "money_honey" {
  name                = var.cluster_name
  location            = azurerm_resource_group.money_honey.location
  resource_group_name = azurerm_resource_group.money_honey.name
  dns_prefix          = var.cluster_name
  kubernetes_version  = var.kubernetes_version

  // Default node pool — 3 nodes so Cilium has quorum.
  default_node_pool {
    name           = "system"
    node_count     = var.node_count
    vm_size        = var.node_sku
    vnet_subnet_id = azurerm_subnet.aks_nodes.id
    os_disk_size_gb = 32
    os_disk_type    = "Managed"
    type            = "VirtualMachineScaleSets"
    tags            = local.common_tags
  }

  // Cluster identity. System-assigned so we don't manage service principal
  // passwords (CLAUDE.md Layer 3 rule).
  identity {
    type = "SystemAssigned"
  }

  // Azure CNI + Cilium data plane. These four fields are the CLAUDE.md
  // non-negotiables (lines 283-291).
  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_data_plane  = "cilium"
    network_policy      = "cilium"
    load_balancer_sku   = "standard"
  }

  // Azure AD + Azure RBAC for Kubernetes. No local accounts.
  azure_active_directory_role_based_access_control {
    azure_rbac_enabled = true
    tenant_id          = data.azurerm_client_config.current.tenant_id
  }
  local_account_disabled = true
  role_based_access_control_enabled = true

  // CSI Secret Store Driver add-on. Mounts Key Vault secrets as volumes.
  key_vault_secrets_provider {
    secret_rotation_enabled  = true
    secret_rotation_interval = "5m"
  }

  // Limit Kubernetes API access to the operator's current IP. Anyone else
  // hitting the API server gets a network-level reject. In step 5 we'll
  // add the GitHub Actions runner CIDRs here so CI can kubectl apply.
  api_server_access_profile {
    authorized_ip_ranges = [local.operator_ip_cidr]
  }

  tags = local.common_tags
}
