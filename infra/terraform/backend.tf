// Remote state lives in an Azure Blob container that is created out-of-band
// by infra/scripts/bootstrap-state.sh. The storage account name is shared
// across all operators of this repo.
//
// To switch accounts, override at init time:
//   terraform init -backend-config="storage_account_name=<name>"

terraform {
  backend "azurerm" {
    resource_group_name  = "money-honey-tfstate-rg"
    storage_account_name = "mhtfstate"
    container_name       = "tfstate"
    key                  = "money-honey.tfstate"
    use_azuread_auth     = true
  }
}
