// Input variables for the Money Honey Azure stack.
// Every variable has a description and a type per CLAUDE.md Terraform rules.

// ---- Placement ----
//
// Subscription comes from the operator's current `az login` session or
// the ARM_SUBSCRIPTION_ID environment variable. Never pin it in code.

variable "resource_group_name" {
  description = "Name of the single resource group that contains the whole stack."
  type        = string
  default     = "money-honey-rg"
}

variable "location" {
  description = "Azure region for all resources."
  type        = string
  default     = "eastus"
}

variable "environment" {
  description = "Environment tag applied to every resource (demo, dev, prod)."
  type        = string
  default     = "demo"
}

// ---- Networking ----

variable "vnet_name" {
  description = "Name of the shared VNet used by both AKS and the Splunk VM."
  type        = string
  default     = "money-honey-vnet"
}

variable "vnet_cidr" {
  description = "Address space for the shared VNet."
  type        = string
  default     = "10.0.0.0/16"
}

variable "aks_subnet_cidr" {
  description = "Subnet CIDR for AKS worker nodes. Used as the source for the Splunk HEC NSG rule."
  type        = string
  default     = "10.0.0.0/22"
}

variable "splunk_subnet_cidr" {
  description = "Subnet CIDR for the Splunk VM NIC."
  type        = string
  default     = "10.0.4.0/28"
}

// ---- AKS ----

variable "cluster_name" {
  description = "Name of the AKS cluster."
  type        = string
  default     = "money-honey-aks"
}

variable "kubernetes_version" {
  description = "AKS Kubernetes version."
  type        = string
  default     = "1.34"
}

variable "node_count" {
  description = "Number of nodes in the default node pool. Cilium requires >= 3."
  type        = number
  default     = 3
}

variable "node_sku" {
  description = "VM SKU for AKS worker nodes."
  type        = string
  default     = "Standard_B2als_v2"
}

// ---- Key Vault ----

variable "key_vault_name_prefix" {
  description = "Prefix for the Key Vault name. A random suffix is appended to satisfy Azure's global uniqueness rule."
  type        = string
  default     = "mh-kv"
}

// ---- Tetragon ----

variable "tetragon_chart_version" {
  description = "Version of the tetragon Helm chart from helm.cilium.io."
  type        = string
  default     = "1.3.0"
}

// ---- Splunk VM ----

variable "splunk_vm_name" {
  description = "Hostname / Azure resource name for the Splunk VM."
  type        = string
  default     = "money-honey-splunk"
}

variable "splunk_vm_sku" {
  description = "VM SKU for the Splunk host."
  type        = string
  default     = "Standard_B2ms"
}

variable "splunk_disk_gb" {
  description = "Size of the Splunk data disk in GB."
  type        = number
  default     = 64
}

variable "splunk_admin_username" {
  description = "Linux admin username on the Splunk VM."
  type        = string
  default     = "azureuser"
}

variable "splunk_image_publisher" {
  description = "Image publisher for the Splunk VM."
  type        = string
  default     = "Canonical"
}

variable "splunk_image_offer" {
  description = "Image offer for the Splunk VM."
  type        = string
  default     = "0001-com-ubuntu-server-jammy"
}

variable "splunk_image_sku" {
  description = "Image SKU for the Splunk VM."
  type        = string
  default     = "22_04-lts-gen2"
}

variable "splunk_image_version" {
  description = "Pinned image version. Bump deliberately; do not use latest."
  type        = string
  default     = "22.04.202410020"
}

// ---- Admin access ----

variable "admin_source_cidr_override" {
  description = "Optional CIDR for SSH/Splunk Web access. When null, the operator's current public IP is auto-detected via https://api.ipify.org."
  type        = string
  default     = null
}
