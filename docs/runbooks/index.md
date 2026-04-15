---
layout: default
title: Runbooks
---

# 🚑 Runbooks

Operational playbooks for Money Honey. Each runbook follows the same shape:

1. Symptom: what you're seeing
2. Pre-checks: confirm the diagnosis before changing anything
3. Procedure: the actual fix
4. Verification: prove it worked
5. Rollback: what to do if the fix made things worse

| Runbook | When to use |
|---|---|
| [Rotate a Key Vault secret](rotate-kv-secret.md) | Suspected leak, scheduled rotation, or a token expired |
| [Recover the Splunk VM](recover-splunk.md) | Splunk web is down, HEC stops accepting events, or VM is unreachable |
| [Cloudflare Tunnel outage](tunnel-outage.md) | A public Cloudflare hostname returns 502/1033, or `cloudflared` is unhealthy |
| [Roll back a Kubernetes deploy](rollback-deploy.md) | A new image is crashlooping, regressed behavior, or post-deploy smoke test failed |

## House rules during an incident

- Read before you write. Confirm symptom + pre-checks before mutating anything. Production cluster, single operator, no second pair of eyes.
- One change at a time. If two things look broken, fix one, verify, then move on.
- Never `git push --force` or `terraform destroy` during an incident. The Splunk VM and Key Vault contain non-reproducible state.
- Capture timestamps. Note the start and end of every change in your incident log. You'll need them for Splunk searches.
