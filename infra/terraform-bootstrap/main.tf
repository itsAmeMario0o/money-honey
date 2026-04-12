// Bootstrap resources: RG, storage account, container, role assignment.
// Subscription is read from the operator's current `az login` session.

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

// Who are we running as? Used to scope the Storage Blob Data Contributor
// role assignment below.
data "azurerm_client_config" "current" {}

// --- Resource group ---
resource "azurerm_resource_group" "tfstate" {
  name     = var.resource_group_name
  location = var.location

  tags = {
    project    = "money-honey"
    purpose    = "terraform-state"
    managed_by = "terraform-bootstrap"
  }
}

// --- Storage account ---
// Locked down per terraform-patterns + cloud-security defaults.
resource "azurerm_storage_account" "tfstate" {
  name                            = var.storage_account_name
  resource_group_name             = azurerm_resource_group.tfstate.name
  location                        = azurerm_resource_group.tfstate.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  account_kind                    = "StorageV2"
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = true  # required by azurerm provider for container creation
  public_network_access_enabled   = true  # state read/write needs this; lock via RBAC

  blob_properties {
    versioning_enabled = true
    delete_retention_policy {
      days = var.soft_delete_retention_days
    }
    container_delete_retention_policy {
      days = var.soft_delete_retention_days
    }
  }

  tags = azurerm_resource_group.tfstate.tags
}

// --- Container ---
resource "azurerm_storage_container" "tfstate" {
  name                  = var.container_name
  storage_account_id    = azurerm_storage_account.tfstate.id
  container_access_type = "private"
}

// --- Role assignment ---
// Data-plane RBAC so the operator (authenticated via `az login`) can read
// and write the .tfstate blob. Subscription-level Contributor does NOT
// include data-plane blob access; this closes that gap.
resource "azurerm_role_assignment" "tfstate_blob" {
  scope                = azurerm_storage_account.tfstate.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}
