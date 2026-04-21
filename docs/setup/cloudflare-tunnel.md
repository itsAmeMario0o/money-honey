---
layout: default
title: Cloudflare Tunnel Setup
---

# ☁️ Cloudflare Tunnel setup (Layer 8)

Wire the Money Honey chatbot and the Splunk dashboard behind Cloudflare Zero Trust. When you finish, both apps are reachable over public URLs gated by an email-domain allowlist, and neither origin has a public inbound app port.

## Prerequisites

- Zero Trust account already created (free plan) with team domain `money-honey.cloudflareaccess.com`
- Two named tunnels created in the dashboard: `money-honey-splunk` and `money-honey-chatbot`
- Both connector tokens saved somewhere safe (password manager)
- `terraform apply` + `install-splunk.sh` already run
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

## Step 2: run the Splunk VM's cloudflared installer

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

## Step 4: confirm both tunnels are Healthy in Cloudflare

Open https://dash.cloudflare.com, Networks, Connectors, Cloudflare Tunnels. Both `money-honey-splunk` and `money-honey-chatbot` should show the green HEALTHY indicator within 60 seconds of step 2 / step 3.

Verify cloudflared pods are stable (zero restarts, 1/1 Running). If the pods crash-loop, check:
- The metrics server must bind to `0.0.0.0:20241` (not localhost). The deployment args should include `--metrics 0.0.0.0:20241`.
- Probe ports must match: readiness and liveness probes hit port `20241`, path `/ready`.

## Step 5: update nameservers (if using a custom domain)

If you have a domain registered elsewhere (e.g. Squarespace), update the nameservers to Cloudflare's. In Cloudflare: add the domain (Websites, Add a site), then update the nameservers at your registrar to the pair Cloudflare assigns. DNS propagation takes minutes to hours.

If you're using `*.cfargotunnel.com` hostnames, skip this step.

## Step 6: configure Published Application Routes

The public hostname config lives inside the tunnel, not under the top-level Routes page.

1. Networks, Connectors, Cloudflare Tunnels
2. Click the tunnel name (e.g. `money-honey-chatbot`)
3. Go to **Published application routes** (not "Hostname routes" which creates private WARP-only routes)
4. Add a route:

### `money-honey-chatbot`

| Field | Value |
|---|---|
| Subdomain | `moneyhoney` (or whatever you chose) |
| Domain | `rooez.com` (pick from dropdown; must be added to Cloudflare first) |
| Service type | HTTP |
| URL | `caddy.money-honey.svc.cluster.local:80` |

### `money-honey-splunk`

| Field | Value |
|---|---|
| Subdomain | `splunk` |
| Domain | `rooez.com` |
| Service type | HTTP |
| URL | `localhost:8000` |

Save each. The route automatically creates the DNS CNAME record. Do not create a manual CNAME first or the route will fail with "A record with that host already exists."

## Step 7: attach Access policies (email allowlist)

For each tunnel's Application in Zero Trust, Access, Applications:

1. Click the app, then Policies tab, then Add a policy.
2. Name: `email-allowlist`
3. Action: Allow
4. Include, Emails ending in, add `@cisco.com`, `@gmail.com`, `@outlook.com`, etc.
5. Save

Visitors now authenticate (Google, Microsoft, or one-time email PIN) before the tunnel forwards the request. Only emails matching the allowlist get through.

## Step 8: smoke-test end-to-end

From your browser:

- `https://chatbot.<your-domain>/`: Cloudflare Access login, then email PIN, then Money Honey UI.
- `https://splunk.<your-domain>/`: Access login, then Splunk login prompt.

If either URL errors with "1033: Argo Tunnel error", the origin is not reachable from the cloudflared pod. Check:

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

## 🧭 No custom domain yet?

Cloudflare Zero Trust Free assigns a `*.cfargotunnel.com` hostname to each tunnel. Ugly, but fully functional. You can still attach Access policies. A custom domain is optional for v1; the Cloudflare team domain `money-honey.cloudflareaccess.com` handles the Access login regardless.
