---
layout: default
title: Cloudflare Tunnel outage
---

# ☁️ Cloudflare Tunnel outage

Cloudflare Tunnel (Layer 8) is the only public path to Money Honey. No backup path. If a tunnel goes down, the corresponding app is unreachable from the internet, but the cluster and Splunk are still healthy and reachable from inside the VNet.

There are two named tunnels:

| Tunnel | Connector lives on | Origin |
|---|---|---|
| `money-honey-splunk` | Splunk VM (systemd) | `http://localhost:8000` (Splunk web) |
| `money-honey-chatbot` | AKS Deployment in `money-honey` ns | `http://caddy.money-honey.svc.cluster.local:80` |

## Symptom

- Public hostname returns Cloudflare error 1033 (no origins online), 502, or 530.
- Cloudflare Zero Trust dashboard shows the tunnel as DEGRADED or DOWN.
- `cloudflared` pod is `CrashLoopBackOff` or the systemd unit is `failed`.

## Pre-checks

1. Is it Cloudflare itself? Check https://www.cloudflarestatus.com/. If there is an active incident on Workers / Tunnel, wait it out.
2. Which tunnel is affected? Check the dashboard tunnel status (Networks, Tunnels). If both are down at once, suspect Cloudflare or your DNS upstream, not the origins.
3. Is the origin app actually up? A tunnel cannot proxy to a dead backend.

```zsh
# Chatbot origin reachable from inside the cluster?
kubectl -n money-honey run curl-test --rm -it --restart=Never \
  --image=curlimages/curl -- \
  curl -sS -o /dev/null -w "%{http_code}\n" \
  http://caddy.money-honey.svc.cluster.local:80/

# Splunk origin reachable from the Splunk VM itself?
ssh azureuser@$SPLUNK_VM_IP 'curl -sS -o /dev/null -w "%{http_code}\n" http://localhost:8000/'
```

If the origin returns non-200, fix the origin first (see [recover-splunk.md](recover-splunk.md) or [rollback-deploy.md](rollback-deploy.md)). The tunnel recovers automatically once the backend is healthy.

## Procedure

### Case A: Chatbot tunnel pod is CrashLoopBackOff

```zsh
kubectl -n money-honey get pods -l app=cloudflared
kubectl -n money-honey logs -l app=cloudflared --tail=80
```

Most common causes + fixes:

| Log line contains | Fix |
|---|---|
| `error="Login token does not contain a token"` | Token in Key Vault is wrong / placeholder. Re-populate `cloudflare-tunnel-chatbot-token` and follow [rotate-kv-secret.md](rotate-kv-secret.md). |
| `dial tcp: lookup caddy.money-honey... no such host` | Caddy Service is missing. `kubectl -n money-honey apply -f k8s/caddy/`. |
| `Unauthorized: Failed to get tunnel` | The named tunnel was deleted in the dashboard. Re-create it, generate a new token, rotate. |
| `connection refused` to upstream | Caddy pod is down. See [rollback-deploy.md](rollback-deploy.md). |

### Case B: Splunk-VM cloudflared (systemd) is failed

```zsh
ssh azureuser@$SPLUNK_VM_IP <<'EOS'
sudo systemctl status cloudflared
sudo journalctl -u cloudflared -n 100 --no-pager
sudo systemctl restart cloudflared
sleep 5
sudo systemctl status cloudflared
EOS
```

If the unit is missing or the binary is gone, re-run the installer with the token exported (the installer is idempotent for everything except Splunk itself):

```zsh
CLOUDFLARED_TOKEN=$(az keyvault secret show --vault-name mh-kv-w8fxwb \
  --name cloudflare-tunnel-splunk-token --query value -o tsv) \
  VM_IP=$SPLUNK_VM_IP \
  SPLUNK_ADMIN_PASSWORD='unused-but-required' \
  ./infra/scripts/install-splunk.sh
```

### Case C: Public Hostname routes broken

If the tunnel is HEALTHY but the public URL still 404s/502s, the Public Hostname mapping in the Cloudflare dashboard is wrong.

1. Cloudflare Zero Trust → Networks → Tunnels → click the tunnel
2. Public Hostnames tab → confirm:
   - `money-honey-chatbot` → service `http://caddy.money-honey.svc.cluster.local:80`
   - `money-honey-splunk` → service `http://localhost:8000`
3. If you don't have a custom domain attached, the URL is `<tunnel-id>.cfargotunnel.com`.

### Case D: Cloudflare Access blocking legitimate traffic

If users hit a Cloudflare Access login screen and their email is not on the allowlist:

1. Zero Trust, Access, Applications, click the app
2. Edit the policy, add the email or domain to the Include list
3. Save. The policy propagates within ~30s.

## Verification

```zsh
# Public path end-to-end (replace with your real hostname).
curl -sS -o /dev/null -w "HTTP %{http_code}\n" https://chatbot.<your-domain>/
curl -sS -o /dev/null -w "HTTP %{http_code}\n" https://splunk.<your-domain>/

# Tunnel says HEALTHY in the dashboard.
# (No CLI for this on Free plan. Visual check.)
```

## Rollback

For the chatbot tunnel: `kubectl -n money-honey rollout undo deployment/cloudflared` reverts to the previous pod template if a config change broke it.

For the Splunk-VM connector: SSH to the VM and `sudo systemctl restart cloudflared`. The prior token in `/etc/cloudflared/config.yml` is still there unless you overwrote it.

There is no rollback for Cloudflare dashboard changes. Undo manually using the audit log timestamps you captured.
