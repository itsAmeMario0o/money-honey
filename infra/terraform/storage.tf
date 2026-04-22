// Azure Storage account for the knowledge-base and hf-cache file shares.
// The actual file shares are dynamically provisioned by AKS via the
// built-in azurefile StorageClass (see k8s/app/storage.yaml). This
// storage account exists for the Terraform outputs (account name + key)
// but does not manage the shares themselves.

resource "azurerm_storage_account" "knowledge" {
  name                     = "mhknowledge${random_string.kv_suffix.result}"
  resource_group_name      = azurerm_resource_group.money_honey.name
  location                 = azurerm_resource_group.money_honey.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"

  tags = local.common_tags
}
