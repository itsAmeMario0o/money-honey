// Outputs exposed after `terraform apply`.
// The sensitive private key output is used to recover the local PEM file
// if the operator loses it — see docs/specs/infra-v1.md EC-10.

output "resource_group_name" {
  description = "Resource group containing all Money Honey resources."
  value       = azurerm_resource_group.money_honey.name
}

output "aks_cluster_name" {
  description = "Name of the AKS cluster."
  value       = azurerm_kubernetes_cluster.money_honey.name
}

output "key_vault_name" {
  description = "Name of the Key Vault used by the app for secrets."
  value       = azurerm_key_vault.money_honey.name
}

output "key_vault_uri" {
  description = "Vault URI used by the CSI Secret Store Driver."
  value       = azurerm_key_vault.money_honey.vault_uri
}

output "splunk_vm_public_ip" {
  description = "Public IP for SSH + Splunk Web access."
  value       = azurerm_public_ip.splunk.ip_address
}

output "splunk_ssh_private_key" {
  description = "SSH private key for the Splunk VM. Used for recovery if infra/private_key/splunk.pem is lost."
  value       = tls_private_key.splunk.private_key_pem
  sensitive   = true
}

output "operator_ip_cidr" {
  description = "The CIDR used for admin NSG rules. Handy for confirming auto-detect worked."
  value       = local.operator_ip_cidr
}

output "ingress_public_ip" {
  description = "Public IP of the Kubernetes ingress load balancer. Populated in step 4 (K8s manifests)."
  value       = null
}

output "knowledge_storage_account" {
  description = "Storage account name for the knowledge-base and hf-cache file shares."
  value       = azurerm_storage_account.knowledge.name
}

output "knowledge_storage_key" {
  description = "Primary access key for the knowledge storage account. Used by the K8s Secret that backs the PV."
  value       = azurerm_storage_account.knowledge.primary_access_key
  sensitive   = true
}
