// Inputs for the bootstrap module. Defaults match the values referenced
// in infra/terraform/backend.tf — if you change one, change the other.

variable "resource_group_name" {
  description = "Resource group that holds the Terraform state storage account."
  type        = string
  default     = "money-honey-tfstate-rg"
}

variable "storage_account_name" {
  description = "Globally unique storage account name. 3-24 lowercase alphanumerics."
  type        = string
  default     = "mhtfstatemjr26"

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    error_message = "Storage account names must be 3-24 chars, lowercase letters and digits only."
  }
}

variable "container_name" {
  description = "Name of the blob container that stores the .tfstate file."
  type        = string
  default     = "tfstate"
}

variable "location" {
  description = "Azure region for the state storage account."
  type        = string
  default     = "eastus"
}

variable "soft_delete_retention_days" {
  description = "How many days deleted blobs can be recovered."
  type        = number
  default     = 14
}
