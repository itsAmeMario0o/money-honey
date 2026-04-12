// These outputs double as a sanity check — the names here must match
// infra/terraform/backend.tf exactly.

output "resource_group_name" {
  description = "RG that holds the state storage account."
  value       = azurerm_resource_group.tfstate.name
}

output "storage_account_name" {
  description = "Storage account that holds the state blob."
  value       = azurerm_storage_account.tfstate.name
}

output "container_name" {
  description = "Blob container that holds the state."
  value       = azurerm_storage_container.tfstate.name
}
