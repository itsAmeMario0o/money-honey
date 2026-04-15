---
layout: default
title: Cloudflare Tunnel Setup
---

# ☁️ Cloudflare Tunnel setup (Layer 8)

Wiring the Money Honey chatbot and the Splunk dashboard behind Cloudflare Zero Trust. When this is done, both apps are reachable over public URLs gated by a Cloudflare Access email-domain allowlist, and neither origin has a public inbound app port.

## Prerequisites

- Zero Trust account already created (free plan) with team domain `money-honey.cloudflareaccess.com`
- Two named tunnels already created in the dashboard: `money-honey-splunk` and `money-honey-chatbot`
- The two connector tokens saved somewhere safe (password manager)
- Terraform apply + `install-splunk.sh` already run
- `kubectl` authenticated against `money-honey-aks`

## Step 1: populate Key Vault with the two tunnel tokens

```zsh
read -s "SPLUNK_TOKEN?Splunk tunnel token (eyJ...): "
echo
az keyvault secret set \
  --vault-name mh-kv-w8fxwb \
  --name cloudflare-tunnel-splunk-token \
  --value "$SPLUNK_TOKEN"
unset SPLUNK_TOKEN

read -s "CHATBOT_TOKEN?Chatbot tunnel token (eyJ...): "
echo
az keyvault secret set \
  --vault-name mh-kv-w8fxwb \
  --name cloudflare-tunnel-chatbot-token \
  --value "$CHATBOT_TOKEN"
unset CHATBOT_TOKEN
```

`read -s` hides the input. `unset` clears the variable from the shell after the `az keyvault secret set` call.

## Step 2: run the Splunk VM's `cloudflared` installer

`install-splunk.sh` skips the tunnel step if `CLOUDFLARED_TOKEN` is empty. Re-running with the token set adds the tunnel without reinstalling Splunk.

```zsh
SPLUNK_ADMIN_PASSWORD='<the password you set earlier>' \
  VM_IP=$(terraform -chdir=infra/terraform output -raw splunk_vm_public_ip) \
  CLOUDFLARED_TOKEN=$(az keyvault secret show \
    --vault-name mh-kv-w8fxwb \
    --name cloudflare-tunnel-splunk-token \
    --query value -o tsv) \
  ./infra/scripts/install-splunk.sh
```

Verify:

```zsh
ssh -i infra/private_key/splunk.pem azureuser@$(terraform -chdir=infra/terraform output -raw splunk_vm_public_ip) \
  "systemctl is-active cloudflared"
# expect: active
```

## Step 3: deploy the chatbot tunnel pod into AKS

The `k8s/cloudflared/` manifest reads the tunnel token from the CSI-mounted Key Vault Secret and dials out to Cloudflare.

```zsh
kubectl apply -f k8s/cloudflared/
kubectl -n money-honey get pods -l app=cloudflared -w
# wait for 2/2 Running
```

If the pod crash-loops with an auth error, the token in KV is likely stale. Rotate by deleting and recreating the tunnel in Cloudflare, then re-run step 1.

## Step 4: confirm both tunnels are "Healthy" in Cloudflare

Open https://one.dash.cloudflare.com → Networks → Tunnels. Both `money-honey-splunk` and `money-honey-chatbot` should show the green "HEALTHY" indicator within 60 seconds of step 2 / step 3.

## Step 5: configure Public Hostnames

For each tunnel, click in and add a Public Hostname:

### `money-honey-chatbot`

| Field | Value |
|---|---|
| Subdomain | `chatbot` |
| Domain | your custom domain (if you've added one) OR leave blank for a tunnel-assigned URL |
| Path | *(empty)* |
| Service type | HTTP |
| URL | `caddy.money-honey.svc.cluster.local:80` |

### `money-honey-splunk`

| Field | Value |
|---|---|
| Subdomain | `splunk` |
| Domain | same as above |
| Path | *(empty)* |
| Service type | HTTP |
| URL | `localhost:8000` |

Save each. The tunnel now routes public requests to the internal service.

## Step 6: attach Access policies (email allowlist)

For each tunnel's Application in Zero Trust → Access → Applications:

1. Click the app, then Policies tab, then Add a policy.
2. Name: `email-allowlist`
3. Action: Allow
4. Include → Emails ending in → add `@cisco.com`, `@gmail.com`, `@outlook.com`, etc.
5. Save

Now any visitor is prompted to authenticate (Google, Microsoft, or one-time email PIN) before the tunnel forwards their request. Only emails matching the allowlist get through.

## Step 7: smoke-test end-to-end

From your browser:

- `https://chatbot.<your-domain>/`: Cloudflare Access login, then email PIN, then Money Honey UI.
- `https://splunk.<your-domain>/`: Access login, then Splunk login prompt.

If either URL errors with "1033: Argo Tunnel error", the origin isn't reachable from the cloudflared pod. Check:

```zsh
kubectl -n money-honey logs deploy/cloudflared --tail=50
kubectl -n money-honey get svc caddy   # Cluster IP + port 80
```

## 🔄 Rotating a tunnel token

If a token leaks, rotate it:

1. Cloudflare dashboard → the tunnel → Delete tunnel → create a new one with the same name
2. `az keyvault secret set --vault-name mh-kv-w8fxwb --name cloudflare-tunnel-<x>-token --value '<new token>'`
3. Restart the consumer:
   - Chatbot tunnel: `kubectl -n money-honey rollout restart deployment/cloudflared`
   - Splunk tunnel: `ssh ... sudo systemctl restart cloudflared` (or re-run step 2)

## 🧭 If you don't have a custom domain yet

Cloudflare Zero Trust Free assigns a `*.cfargotunnel.com` hostname to each tunnel. Ugly, but fully functional. You can still attach Access policies. A custom domain is optional for v1; the Cloudflare team domain `money-honey.cloudflareaccess.com` handles the Access login regardless.
