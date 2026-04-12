// Provider configurations.
// azurerm reads the subscription from the operator's current `az login`
// session (or ARM_SUBSCRIPTION_ID env var). The subscription ID is NEVER
// pinned in code — that avoids leaking tenant structure in a public repo
// and keeps the module portable across accounts.

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = false
      recover_soft_deleted_key_vaults = true
    }
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

// Helm talks to the AKS cluster we create in aks.tf. The host and
// credentials come from the cluster's kube_admin_config output.
provider "helm" {
  kubernetes {
    host                   = azurerm_kubernetes_cluster.money_honey.kube_admin_config[0].host
    client_certificate     = base64decode(azurerm_kubernetes_cluster.money_honey.kube_admin_config[0].client_certificate)
    client_key             = base64decode(azurerm_kubernetes_cluster.money_honey.kube_admin_config[0].client_key)
    cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.money_honey.kube_admin_config[0].cluster_ca_certificate)
  }
}

provider "kubernetes" {
  host                   = azurerm_kubernetes_cluster.money_honey.kube_admin_config[0].host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.money_honey.kube_admin_config[0].client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.money_honey.kube_admin_config[0].client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.money_honey.kube_admin_config[0].cluster_ca_certificate)
}
