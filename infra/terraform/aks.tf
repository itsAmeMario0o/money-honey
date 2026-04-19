// AKS cluster with Azure CNI powered by Cilium (managed, not BYOCNI).
// Configuration is locked to the values pinned in CLAUDE.md §Architecture
// Decisions and docs/specs/infra-v1.md (FR-5 through FR-12, FR-29).

// Client context is used for tenant ID and current user object ID (KV admin).
data "azurerm_client_config" "current" {}

# tfsec:ignore:azure-container-logging -- Splunk (via Fluent Bit + OTel) is the log pipeline, not Azure Monitor. See CLAUDE.md Layer 7.
# tfsec:ignore:azure-container-limit-authorized-ips -- API server is public by design for v1; identity gate is Azure AD + Azure RBAC for Kubernetes. Private cluster + self-hosted runners is the v2 path. See comment in aks.tf where api_server_access_profile would live.
resource "azurerm_kubernetes_cluster" "money_honey" {
  name                = var.cluster_name
  location            = azurerm_resource_group.money_honey.location
  resource_group_name = azurerm_resource_group.money_honey.name
  dns_prefix          = var.cluster_name
  kubernetes_version  = var.kubernetes_version

  // Default node pool — 3 nodes so Cilium has quorum.
  default_node_pool {
    name                        = "system"
    node_count                  = var.node_count
    vm_size                     = var.node_sku
    temporary_name_for_rotation = "tmppool"
    vnet_subnet_id              = azurerm_subnet.aks_nodes.id
    os_disk_size_gb             = 32
    os_disk_type                = "Managed"
    type                        = "VirtualMachineScaleSets"
    tags                        = local.common_tags
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
    // Service CIDR is a cluster-internal range for ClusterIP Services.
    // Must NOT overlap the VNet (10.0.0.0/16) or AKS rejects the config.
    service_cidr   = var.aks_service_cidr
    dns_service_ip = var.aks_dns_service_ip
  }

  // Azure AD + Azure RBAC for Kubernetes. No local accounts.
  azure_active_directory_role_based_access_control {
    azure_rbac_enabled = true
    tenant_id          = data.azurerm_client_config.current.tenant_id
  }
  // v1 demo: admin kubeconfig kept enabled so Terraform's Helm provider
  // can authenticate via kube_admin_config. Azure AD + Azure RBAC for
  // Kubernetes remains the primary identity path for human users.
  // Production path: set local_account_disabled = true and use kubelogin
  // exec plugin in providers.tf to authenticate Terraform via az login.
  local_account_disabled            = false
  role_based_access_control_enabled = true

  // CSI Secret Store Driver add-on. Mounts Key Vault secrets as volumes.
  key_vault_secrets_provider {
    secret_rotation_enabled  = true
    secret_rotation_interval = "5m"
  }

  // API server access:
  //   - Identity: Azure AD + Azure RBAC for Kubernetes (primary gate).
  //   - Network: public, no IP allowlist. GitHub Actions runners need
  //     to reach the API to kubectl apply, and their CIDRs are too
  //     broad/churny to maintain as an allowlist. Azure RBAC + SP
  //     scoping is the real perimeter here.
  //   - v2 hardening path: private AKS cluster + self-hosted runners
  //     inside the VNet. That's the only way to have both a narrow
  //     network perimeter AND working CI.
  // No api_server_access_profile block = no IP restriction (Azure default).

  tags = local.common_tags
}
