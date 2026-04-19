---
layout: default
title: Terraform Apply Walkthrough
---

# 🌍 Terraform apply walkthrough

Provisioning happens in two modules because the state backend is itself an Azure resource you have to create first:

1. `infra/terraform-bootstrap/`: creates the Azure Storage Account that holds remote state. Uses local state. Only runs once.
2. `infra/terraform/`: the main stack (AKS, Key Vault, Splunk VM, etc.). Uses remote state in the SA created above.

## Bootstrap module (one-time)

```bash
cd infra/terraform-bootstrap
terraform init
terraform apply          # review the 4-resource plan; type 'yes'
```

Creates:
- Resource group `money-honey-tfstate-rg`
- Storage account `mhtfstatemjr26` (globally unique; change the default if taken)
- Container `tfstate`
- Role assignment: operator gets `Storage Blob Data Contributor` on the SA

## Main stack

```bash
cd ../terraform
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

Creates ~23 resources including AKS, Cilium, Tetragon via Helm, Key Vault + secrets, Splunk VM, VNet + subnets, NSG.

Estimated duration: ~10–12 minutes. AKS is the slowest component.

## Known gotchas

- Stale state lock. If a previous run was interrupted, `terraform apply` fails with "state blob is already locked." Recovery:
  ```bash
  az storage blob lease break \
    --account-name mhtfstatemjr26 \
    --container-name tfstate \
    --blob-name money-honey.tfstate \
    --auth-mode login
  ```
- AKS service CIDR overlap. The cluster's service CIDR (`172.16.0.0/16` in variables) must not overlap the VNet. Change `aks_service_cidr` and `aks_dns_service_ip` if your VNet sits in the 172.16.x range.
- vCPU quota. Default `node_sku` is `Standard_B4ms` (4 vCPU / 16 GB RAM). If `standardBSFamily` quota is exhausted in your region, switch to `Standard_D4s_v3`. Any region should have plenty of `standardDSv3Family` quota.
- Helm provider auth. The Terraform Helm provider reads `kube_admin_config[0]` from the cluster output. Requires `local_account_disabled = false` (the v1 default). Flipping to `true` means switching to kubelogin exec (documented in `aks.tf`).

## Outputs

After apply succeeds:

```bash
terraform output
```

Exposes:
- `aks_cluster_name`
- `resource_group_name`
- `key_vault_name`
- `key_vault_uri`
- `splunk_vm_public_ip`
- `operator_ip_cidr`: the `/32` that ended up in the NSG rules

And a sensitive output (never print to logs):
- `splunk_ssh_private_key`: recovery path for `infra/private_key/splunk.pem`

## Teardown

```bash
cd infra/terraform
terraform destroy       # ~8 minutes

cd ../terraform-bootstrap
terraform destroy       # ~1 minute
```

Soft-delete on the Key Vault and blob container means the names stick around for a few days after destroy. To recycle the storage account name immediately, purge via Azure Portal.
