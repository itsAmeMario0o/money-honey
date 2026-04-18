// Azure File share for the RAG knowledge base and HuggingFace model cache.
// Pods mount this via a PVC so PDFs and the embedding model persist across
// restarts, redeployments, and node replacements. Uploading new PDFs is
// just `az storage file upload-batch`, no Docker rebuild needed.

resource "azurerm_storage_account" "knowledge" {
  name                     = "mhknowledge${random_string.kv_suffix.result}"
  resource_group_name      = azurerm_resource_group.money_honey.name
  location                 = azurerm_resource_group.money_honey.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"

  tags = local.common_tags
}

resource "azurerm_storage_share" "knowledge_base" {
  name               = "knowledge-base"
  storage_account_id = azurerm_storage_account.knowledge.id
  quota              = 5
}

resource "azurerm_storage_share" "hf_cache" {
  name               = "hf-cache"
  storage_account_id = azurerm_storage_account.knowledge.id
  quota              = 1
}
