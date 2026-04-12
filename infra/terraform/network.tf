// Shared VNet for AKS and the Splunk VM.
// One VNet with two subnets gives AKS worker nodes L3 reachability to
// Splunk on port 8088 (HEC) with no peering and no public hop.

resource "azurerm_virtual_network" "money_honey" {
  name                = var.vnet_name
  address_space       = [var.vnet_cidr]
  location            = azurerm_resource_group.money_honey.location
  resource_group_name = azurerm_resource_group.money_honey.name
  tags                = local.common_tags
}

// Holds the AKS default node pool. Sized to fit Cilium's overlay mode
// plus future scaling headroom.
// Microsoft.KeyVault service endpoint lets AKS nodes reach Key Vault
// through Azure's backbone, which is how the CSI driver works when the
// Key Vault network_acls default_action is "Deny".
resource "azurerm_subnet" "aks_nodes" {
  name                 = "aks-nodes"
  resource_group_name  = azurerm_resource_group.money_honey.name
  virtual_network_name = azurerm_virtual_network.money_honey.name
  address_prefixes     = [var.aks_subnet_cidr]
  service_endpoints    = ["Microsoft.KeyVault"]
}

// Holds the Splunk VM NIC. Small block — only one VM lives here.
resource "azurerm_subnet" "splunk" {
  name                 = "splunk"
  resource_group_name  = azurerm_resource_group.money_honey.name
  virtual_network_name = azurerm_virtual_network.money_honey.name
  address_prefixes     = [var.splunk_subnet_cidr]
}
