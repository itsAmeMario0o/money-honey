// Azure Key Vault holds the Claude API key and Splunk HEC token.
// Embeddings run locally, so no embedding-provider key lives here.
//
// Secret *values* are set manually in the Azure portal (or via `az`) —
// Terraform only creates the shells and ignores their values.

resource "azurerm_key_vault" "money_honey" {
  name                = "${var.key_vault_name_prefix}-${random_string.kv_suffix.result}"
  location            = azurerm_resource_group.money_honey.location
  resource_group_name = azurerm_resource_group.money_honey.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  // Use access policies (not RBAC) for simpler demo setup. In v2 we would
  // switch to RBAC + role assignments per senior-secops best practice.
  enable_rbac_authorization = false

  // Hard safety: deletions are recoverable, purges are blocked.
  soft_delete_retention_days = 7
  purge_protection_enabled   = true

  // Default-deny. Explicitly allow the operator IP and the AKS node subnet
  // (via Microsoft.KeyVault service endpoint). Everything else is rejected
  // at the network layer before it can try to authenticate.
  public_network_access_enabled = true
  network_acls {
    bypass                     = "AzureServices"
    default_action             = "Deny"
    ip_rules                   = [local.operator_ip_cidr]
    virtual_network_subnet_ids = [azurerm_subnet.aks_nodes.id]
  }

  tags = local.common_tags
}

// Operator access policy — whoever runs `terraform apply` gets full secret
// management so they can set the placeholder values in the portal.
resource "azurerm_key_vault_access_policy" "operator" {
  key_vault_id = azurerm_key_vault.money_honey.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id

  secret_permissions = [
    "Get", "List", "Set", "Delete", "Recover", "Purge", "Backup", "Restore",
  ]
}

// AKS CSI driver access policy — read-only access for the secret-mount flow.
resource "azurerm_key_vault_access_policy" "aks_csi" {
  key_vault_id = azurerm_key_vault.money_honey.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_kubernetes_cluster.money_honey.key_vault_secrets_provider[0].secret_identity[0].object_id

  secret_permissions = ["Get", "List"]
}

// --- Placeholder secrets ---
// Terraform creates the shells. Values are set manually in the portal or
// via `az keyvault secret set`. lifecycle.ignore_changes keeps Terraform
// from overwriting the real value on subsequent applies.

resource "azurerm_key_vault_secret" "anthropic_api_key" {
  name         = "anthropic-api-key"
  value        = "set-me-in-portal"
  key_vault_id = azurerm_key_vault.money_honey.id
  content_type    = "text/plain"
  // Rotate on or before this date. Update manually when rotating the real secret.
  expiration_date = "2027-01-01T00:00:00Z"

  lifecycle {
    ignore_changes = [value, version]
  }

  depends_on = [azurerm_key_vault_access_policy.operator]
}

resource "azurerm_key_vault_secret" "splunk_hec_token" {
  name         = "splunk-hec-token"
  value        = "set-me-in-portal"
  key_vault_id = azurerm_key_vault.money_honey.id
  content_type    = "text/plain"
  // Rotate on or before this date. Update manually when rotating the real secret.
  expiration_date = "2027-01-01T00:00:00Z"

  lifecycle {
    ignore_changes = [value, version]
  }

  depends_on = [azurerm_key_vault_access_policy.operator]
}
