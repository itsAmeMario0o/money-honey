---
layout: default
title: Roll back a Kubernetes deploy
---

# ⏪ Roll back a Kubernetes deploy

New image crashlooping. Behavior regressed. Post-deploy smoke test failed. K8s keeps the previous ReplicaSet, so rollback is one command for the common case.

## Symptom

- A `Deployment` shows pods in `CrashLoopBackOff`, `ImagePullBackOff`, or `Error` after a recent `kubectl apply`/`rollout`.
- `/api/health` returns 5xx, or the chat path returns garbage / errors that were not there yesterday.
- `deploy.yaml` succeeded in CI but the smoke test failed.

## Pre-checks

```zsh
# Which workloads are unhealthy?
kubectl -n money-honey get deploy
kubectl -n money-honey get pods

# What did the most recent rollout actually do?
kubectl -n money-honey rollout history deployment/<name>
kubectl -n money-honey describe deployment/<name> | head -40

# Capture the failing pod's recent logs BEFORE rolling back. You'll need them for the postmortem.
kubectl -n money-honey logs deploy/<name> --previous --tail=200 > /tmp/<name>-failed-$(date +%s).log
```

If pods are stuck on `ImagePullBackOff` and the image tag is correct, the GHCR package may have been switched back to private. See `Case D` below before rolling back.

## Procedure

### Case A: Roll back to the previous ReplicaSet (most common)

```zsh
# Show available revisions.
kubectl -n money-honey rollout history deployment/<name>

# Roll back one revision.
kubectl -n money-honey rollout undo deployment/<name>

# OR roll back to a specific revision number.
kubectl -n money-honey rollout undo deployment/<name> --to-revision=<N>

# Watch the rollout finish.
kubectl -n money-honey rollout status deployment/<name> --timeout=120s
```

### Case B: Pin to an older image tag explicitly

Use this when the offending image is `:latest` or a moving tag and you want to lock to a known-good SHA.

```zsh
# Find a known-good tag (e.g. from the last successful deploy run in GitHub Actions).
GOOD=ghcr.io/itsamemario0o/money-honey-app:<sha>

kubectl -n money-honey set image deployment/fastapi fastapi=$GOOD
kubectl -n money-honey rollout status deployment/fastapi --timeout=120s
```

### Case C: Pause further rollouts while you investigate

```zsh
kubectl -n money-honey rollout pause deployment/<name>
# ... investigate ...
kubectl -n money-honey rollout resume deployment/<name>
```

A paused Deployment ignores `kubectl set image` until resumed. Useful to prevent a CI re-run from clobbering your manual revert.

### Case D: `ImagePullBackOff` with the right tag

The GHCR package visibility may have flipped to private (Trivy or a manual click in the GitHub UI).

1. Repo Settings → Packages → click the affected package (`money-honey-app` or `money-honey-frontend`)
2. Package settings → Change visibility → Public
3. Wait 30s, then `kubectl -n money-honey delete pod -l app=<name>` to force a re-pull

### Case E: Both fastapi AND react regressed at once

Suspect Caddy or the shared ConfigMap, not the apps. Roll back caddy first; the app pods will recover when their upstream is back.

```zsh
kubectl -n money-honey rollout undo deployment/caddy
```

## Verification

```zsh
# Pods are Ready.
kubectl -n money-honey get pods -l app=<name>

# Health endpoint passes.
kubectl -n money-honey port-forward svc/caddy 8080:80 &
curl -sS http://localhost:8080/api/health
curl -sS -X POST http://localhost:8080/api/chat \
  -H 'content-type: application/json' \
  -d '{"message":"smoke test"}' | jq '.response' | head -c 200
kill %1   # stop the port-forward
```

For the LLM path specifically, also check:

- Tetragon TracingPolicy did not kill the pod (look for `process_kprobe` events with `policy_name` matching one of yours in the last 5 min in Splunk).
- CSI mount did not fail (`kubectl describe pod`, no `MountVolume.SetUp failed`).

## Rollback (yes, of the rollback)

If the rollback itself made things worse (e.g. the previous ReplicaSet's image was also broken and you did not realize):

```zsh
# Roll FORWARD to a specific revision.
kubectl -n money-honey rollout history deployment/<name>
kubectl -n money-honey rollout undo deployment/<name> --to-revision=<good-N>
```

If history has been pruned (default `revisionHistoryLimit: 10`), trigger a fresh deploy from CI by re-running the last green `deploy.yaml` workflow run in GitHub Actions.
