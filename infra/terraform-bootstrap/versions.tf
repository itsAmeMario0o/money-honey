// Bootstrap module: creates the Azure Storage Account that holds the
// main Terraform state. Uses LOCAL state (default) to sidestep the
// chicken-and-egg: you can't store your backend's own state in the
// backend you haven't created yet.
//
// Local state file (terraform.tfstate) lives next to this file and
// is gitignored. It's small and only contains the storage account +
// role assignment IDs.

terraform {
  required_version = ">= 1.5.0, < 2.0.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.14"
    }
  }
}
