// Top-level resources: resource group, random suffix, and operator-IP lookup.
// Resource-specific files live next to this one (aks.tf, keyvault.tf, etc.).

// Shared tags applied to every resource for cost tracking and cleanup.
locals {
  common_tags = {
    project     = "money-honey"
    environment = var.environment
    managed_by  = "terraform"
  }

  // Admin source CIDR: either the operator override or the auto-detected IP.
  operator_ip_cidr = coalesce(
    var.admin_source_cidr_override,
    "${chomp(data.http.operator_public_ip.response_body)}/32",
  )
}

// Everything lives in one resource group for easy cleanup.
resource "azurerm_resource_group" "money_honey" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.common_tags
}

// Key Vault names are globally unique. Random suffix avoids collisions.
resource "random_string" "kv_suffix" {
  length  = 6
  special = false
  upper   = false
}

// Fetch the operator's current public IP at plan time. Used as the source
// for SSH and Splunk Web NSG rules so access is scoped to this machine only.
data "http" "operator_public_ip" {
  url = "https://api.ipify.org"
}
