#!/usr/bin/env bash
# Bootstrap the Azure Storage Account that holds Terraform remote state.
#
# Run once per subscription, before the first `terraform init`. Safe to
# re-run — every step is idempotent.
#
# Requires: az CLI, authenticated via `az login`.

set -euo pipefail

# Defaults match backend.tf — change here AND there if you rename anything.
RG=${TFSTATE_RG:-money-honey-tfstate-rg}
SA=${TFSTATE_SA:-mhtfstatemjr26}
CONTAINER=${TFSTATE_CONTAINER:-tfstate}
LOCATION=${TFSTATE_LOCATION:-eastus}

# Quick sanity check — fail loud if the operator isn't logged in.
if ! az account show >/dev/null 2>&1; then
  echo "❌ Not logged in. Run: az login"
  exit 1
fi

SUB_NAME=$(az account show --query name -o tsv)
echo "✅ Using Azure subscription: $SUB_NAME"
echo ""

# --- Resource group ---
if az group show -n "$RG" >/dev/null 2>&1; then
  echo "✔  Resource group '$RG' already exists."
else
  echo "→  Creating resource group '$RG' in $LOCATION..."
  az group create -n "$RG" -l "$LOCATION" -o none
fi

# --- Storage account ---
if az storage account show -n "$SA" -g "$RG" >/dev/null 2>&1; then
  echo "✔  Storage account '$SA' already exists."
else
  echo "→  Creating storage account '$SA'..."
  az storage account create \
    --name "$SA" \
    --resource-group "$RG" \
    --location "$LOCATION" \
    --sku Standard_LRS \
    --kind StorageV2 \
    --encryption-services blob \
    --allow-blob-public-access false \
    --min-tls-version TLS1_2 \
    -o none
fi

# --- Blob versioning + soft-delete (spec FR-4) ---
echo "→  Enabling blob versioning + soft-delete..."
az storage account blob-service-properties update \
  --account-name "$SA" \
  --resource-group "$RG" \
  --enable-versioning true \
  --enable-delete-retention true \
  --delete-retention-days 14 \
  -o none

# --- Container ---
if az storage container show --account-name "$SA" --name "$CONTAINER" --auth-mode login >/dev/null 2>&1; then
  echo "✔  Container '$CONTAINER' already exists."
else
  echo "→  Creating container '$CONTAINER'..."
  az storage container create \
    --account-name "$SA" \
    --name "$CONTAINER" \
    --auth-mode login \
    --public-access off \
    -o none
fi

echo ""
echo "🎉 Backend ready. Next:"
echo "   cd infra/terraform"
echo "   terraform init"
