---
layout: default
title: Recover the Splunk VM
---

# 📊 Recover the Splunk VM

The Splunk VM is the only stateful node outside AKS. If it dies, you lose the search head, HEC ingest, and the cloudflared sidecar that publishes Splunk web. The disk is persistent. Most failures are recoverable without data loss.

## Symptom

- Splunk web (via Cloudflare hostname or `:8000` over SSH tunnel) returns 502/504 or hangs.
- Fluent Bit / OTel logs show `dial tcp <splunk-private-ip>:8088: connect: connection refused` or `i/o timeout` on the HEC exporter.
- `ssh azureuser@$SPLUNK_VM_IP` itself hangs or refuses.

## Pre-checks

```zsh
SPLUNK_VM_IP=$(terraform -chdir=infra/terraform output -raw splunk_vm_public_ip)

# Is the VM running according to Azure?
az vm show -g money-honey-rg -n money-honey-splunk \
  --show-details --query "{powerState:powerState, provisioning:provisioningState}" -o table

# Is your IP currently allowed by the SSH NSG?
az network nsg rule show -g money-honey-rg \
  --nsg-name money-honey-splunk-nsg --name allow-ssh-operator \
  --query "sourceAddressPrefix" -o tsv
echo "Your public IP: $(curl -s https://api.ipify.org)"
```

If your IP doesn't match, fix it before SSH troubleshooting:

```zsh
terraform -chdir=infra/terraform apply -auto-approve \
  -target=azurerm_network_security_rule.splunk_ssh \
  -target=azurerm_key_vault.money_honey
```

## Procedure

### Case A: VM is stopped/deallocated

```zsh
az vm start -g money-honey-rg -n money-honey-splunk
# Wait ~60s for boot, then:
ssh azureuser@$SPLUNK_VM_IP 'sudo systemctl status splunk cloudflared'
```

### Case B: VM is running but Splunk is down

```zsh
ssh azureuser@$SPLUNK_VM_IP <<'EOS'
sudo systemctl status splunk
# Common failure: stuck pid, disk full
df -h /opt/splunk
sudo journalctl -u splunk -n 100 --no-pager
sudo systemctl restart splunk
EOS
```

If the disk is full, the culprit is almost always `/opt/splunk/var/log/splunk/`. Splunk Free has a 500 MB/day index quota. Over-quota does NOT delete on its own, but log churn from a restart loop can fill the disk. Trim the largest files in `/opt/splunk/var/log/splunk/` after stopping splunkd.

### Case C: VM is running, Splunk is up, HEC still refuses

```zsh
ssh azureuser@$SPLUNK_VM_IP <<'EOS'
# Confirm HEC listener is bound.
sudo ss -lntp | grep 8088 || echo "HEC NOT LISTENING"

# Check the HEC token is enabled (not disabled by Splunk on too many bad auths).
sudo /opt/splunk/bin/splunk http-event-collector list -auth admin:'<password>'
EOS
```

If HEC is listening but cluster pods still cannot reach it, the AKS subnet to Splunk subnet path is broken. Re-check the NSG `allow-hec-aks-subnet` rule allows `10.0.0.0/22` to port `8088`.

### Case D: VM is unreachable (full reboot needed)

```zsh
az vm restart -g money-honey-rg -n money-honey-splunk
# Wait 60-90s, then re-run pre-checks.
```

### Case E: Hard rebuild (last resort, data preserved)

The VM uses a managed OS disk separate from the data disk holding `/opt/splunk`. If the OS disk corrupts, you can re-create the VM and re-attach the data disk via Terraform. Because this is destructive, it is deliberately NOT scripted. Pause. Re-read `infra/terraform/splunk-vm.tf` before running. Confirm the data disk is excluded from any `taint` you apply.

## Verification

```zsh
# 1. Splunk web reachable.
ssh -L 8000:localhost:8000 azureuser@$SPLUNK_VM_IP
# Open http://localhost:8000 in browser, log in.

# 2. HEC ingest works from outside.
SPLUNK_HEC_TOKEN=$(az keyvault secret show --vault-name mh-kv-w8fxwb \
  --name splunk-hec-token --query value -o tsv)
ssh azureuser@$SPLUNK_VM_IP "curl -k -sS \
  https://localhost:8088/services/collector/event \
  -H 'Authorization: Splunk $SPLUNK_HEC_TOKEN' \
  -d '{\"event\":\"runbook-recovery-test\",\"sourcetype\":\"runbook\",\"index\":\"main\"}'"

# 3. From inside the cluster, fluent-bit picks up new events.
kubectl -n kube-system logs -l app=fluent-bit --tail=20 | grep -i splunk
```

## Rollback

Recovery is read-only on Azure-side state, so there is nothing to roll back. If a restart made things worse (e.g. systemd unit corrupt), the next step is Case E (rebuild).
