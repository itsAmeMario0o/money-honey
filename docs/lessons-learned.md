---
layout: default
title: Lessons learned
---

# 🧠 Lessons learned

Every security demo is also a systems integration project. This page captures the problems that cost real time during the Money Honey build, what caused them, and what to do differently next time.

## ARM images on an x86_64 cluster

The chatbot ran fine in local testing. Pushed to AKS, the pod crashed instantly: `exec format error`.

Apple Silicon Macs build ARM container images by default. AKS nodes run x86_64. The mismatch is invisible until the pod tries to start because the image pull succeeds (GHCR stores whatever you push, regardless of architecture). The first sign of trouble is a one-line error in the pod logs.

Colima, the lightweight container runtime used on this project, locks its VM architecture at creation time. You cannot convert an existing ARM VM to x86_64. The fix: `colima delete`, install QEMU and lima-additional-guestagents via Homebrew, then `colima start --arch x86_64 --cpu 4 --memory 8`. Builds take 10-15 min under emulation but produce images that run on AKS without issues.

Docker Desktop handles this transparently with `--platform linux/amd64`. If you use Docker Desktop, none of this applies. If you use Colima, the setup is documented in [prerequisites](setup/prerequisites.html).

## OOMKill during PDF embedding

The FastAPI pod loads sentence-transformers (~80 MB model), reads 28 MB of PDFs, splits them into ~1500 chunks, and embeds every chunk into a 384-dimensional vector. All of this happens during module-level initialization before uvicorn even starts.

With a 1 GiB memory limit, the pod was killed mid-embedding. The first symptom was empty logs (the process died before producing any output) and a `137` exit code in `kubectl describe pod`. Bumped to 2 GiB, same result. Finally resolved at 3 GiB, but the original `Standard_B2s` nodes (4 GB RAM each) could not fit two 3 GiB pods alongside system workloads. First tried `Standard_B4ms` (16 GB RAM) but hit vCPU quota limits on the `standardBSFamily` in eastus. Landed on `Standard_D2s_v3` (8 GB RAM per node, `standardDSv3Family` with 50 vCPUs available).

The lesson: if your RAG pipeline embeds at startup, the memory limit must account for the peak of the embedding run, not the steady-state serving footprint. sentence-transformers with MiniLM and ~1500 chunks peaks around 2.5 GB. Adding a safety margin puts the limit at 3 GiB.

## Read-only root filesystem vs. HuggingFace cache

The deployment sets `readOnlyRootFilesystem: true`, which is the right security posture. But sentence-transformers downloads the embedding model to `~/.cache/huggingface/` on first run. The download fails with `OSError: Read-only file system` and no useful stack trace unless you read the full traceback.

The fix is an `emptyDir` (or PVC) mounted at `/home/honey/.cache`. The model downloads once, and subsequent container restarts within the same pod reuse the cached copy. With Azure Files backing the mount, the model persists across pod replacements too, so only the very first pod ever downloads it.

## emptyDir overlays baked-in files

An `emptyDir` volume mounted at a path that already exists in the container image replaces the image contents with an empty directory. If you bake PDFs into the image at `/app/knowledge_base/pdfs/` and then mount an emptyDir at the same path, the pod sees zero PDFs.

This is Kubernetes working as designed, but easy to overlook when iterating between "bake it in" and "mount it externally." The fix was to commit to one strategy (Azure Files PVC) and remove the emptyDir.

## .dockerignore silently excludes PDFs

The `.dockerignore` file contained `knowledge_base/pdfs/*.pdf` to keep PDFs out of CI-built images (CI does not have access to the actual PDF files). During the local build where PDFs were intentionally baked in, this rule silently dropped all three PDFs from the image. The pod started successfully, the LLM connected, but the index stayed empty.

The only clue was `index_ready: false` in the health endpoint. The fix: `kubectl exec` into the pod and `ls /app/knowledge_base/pdfs/` to confirm the files were missing.

## kubectl cp and special characters in filenames

`kubectl cp` uses tar under the hood. Filenames with spaces and brackets (like `The Enlightened Accountant [Master Financial Accounting].pdf`) fail silently or produce tar errors. The fix: rename the file to remove special characters before copying, or copy from a path without spaces.

## Webex bot action with broken inputs

The `chrivand/action-webex-js@v1.0.1` GitHub Action accepted our `token`, `roomId`, and `message` inputs without error, ran to completion, and showed a green checkmark in the Actions UI. But it sent nothing. The debug log revealed: `Warning: Unexpected input(s) 'token', 'roomId', 'message', valid inputs are ['']`. The action's interface changed after the version we pinned to, and the inputs were silently ignored.

Replaced with a direct `curl` POST to `https://webexapis.com/v1/messages`. Four lines, zero dependencies, works reliably.

## Stale image tag with IfNotPresent

The Deployment used `imagePullPolicy: IfNotPresent`. After pushing a new `:latest` image to GHCR, AKS kept running the old image because the node already had a `:latest` cached. The pod looked healthy, the image pull succeeded (from cache), but the new code was not running.

Switched to `imagePullPolicy: Always`. Every pod start pulls from the registry. Slightly slower cold-start, but guaranteed to run the image you pushed.

## PersistentVolume requires cluster-admin RBAC

Creating a static PV (cluster-scoped resource) with the Azure RBAC Writer role fails with `User does not have access to the resource in Azure`. PVs are cluster-scoped; namespace-scoped roles cannot create them.

Switched to dynamic provisioning via the built-in `azurefile` StorageClass. PVCs are namespace-scoped and create the file share automatically. No cluster-admin role needed.

## Terraform state lock after interrupted apply

A `terraform apply` interrupted mid-run (Ctrl+C, network drop, or timeout) leaves an Azure Blob lease on the state file. The next `terraform apply` fails with "state blob is already locked."

The fix: `az storage blob lease break --account-name mhtfstatemjr26 --container-name tfstate --blob-name money-honey.tfstate --auth-mode login`. Documented in [terraform setup](setup/terraform.html).

## Corporate network blocks AKS API

From a remote office, `kubectl` commands failed with `read: connection reset by peer`. The AKS API server allowlist was empty (open to all IPs), so the block was not on the Azure side. The corporate network's TLS inspection proxy was resetting connections to `*.azmk8s.io`.

No server-side fix. Options: personal hotspot, VPN, or asking IT to allowlist the AKS FQDN. The project documents this in STATUS.md so future operators don't spend hours debugging the wrong layer.

## CI deploy timeout vs startup probe budget

The `deploy.yaml` workflow waited 5 minutes for the fastapi rollout to finish. The pod's startup probe allows 15 minutes because embedding 28 MB of PDFs into 1500 FAISS chunks takes ~10 minutes. The workflow timed out and reported failure, even though the pod was healthy and still embedding.

The fix: match the workflow's `--timeout` to the startup probe budget. FastAPI gets 15 minutes. React and Caddy keep 5 minutes since they start in seconds.

## AKS node pool VM size change requires temporary pool

Changing `vm_size` on the default node pool is not an in-place update. AKS needs `temporary_name_for_rotation` in the Terraform config. It creates a temporary node pool with the new SKU, drains the old nodes, migrates all workloads, then deletes the old pool. Without the field, Terraform fails with a clear error listing every property that requires rotation.

The rotation takes 15-20 minutes. All pods restart on the new nodes. PVCs, Secrets, and ConfigMaps survive because they are cluster-scoped state, not node-local state.

## Cloudflare Tunnel setup is not where the docs say it is

Cloudflare's dashboard reorganized. The old "Public Hostnames" tab on the tunnel detail page no longer exists. The new flow:

1. **Networks → Connectors → Cloudflare Tunnels** (not "Networks → Tunnels")
2. Click the tunnel name to open it
3. The tunnel detail page has tabs: Overview, CIDR routes, Hostname routes, Published application routes, Live logs
4. **Hostname routes** (beta) creates private routes that require the Cloudflare One WARP client. That's NOT what you want for a public-facing app.
5. **Published application routes** is where public hostname config lives. Add the subdomain, pick the domain from the dropdown, set service type HTTP, and point to the in-cluster origin.

The published application route creates the DNS CNAME automatically. If you already created a manual CNAME record in DNS, delete it first or the route creation fails with "A record with that host already exists."

## cloudflared metrics server binds to localhost by default

cloudflared's `--metrics` flag defaults to `127.0.0.1:20241`. Kubernetes liveness and readiness probes connect from outside the container and can't reach localhost. The pod registers all 4 QUIC connections to Cloudflare's edge, runs for ~90 seconds, then gets killed by the probe. The fix: add `--metrics 0.0.0.0:20241` to the container args so the `/ready` endpoint is reachable from the kubelet. Also confirm the probe port matches (20241, not 2000).

## Full Cloudflare Tunnel setup sequence

1. Create the tunnel in Cloudflare dashboard (Networks → Connectors → Create a tunnel)
2. Copy the connector token
3. Store the token in Azure Key Vault (`az keyvault secret set`)
4. Deploy the cloudflared pod (`kubectl apply -f k8s/cloudflared/`)
5. Verify pods stabilize at 1/1 Running with zero restarts
6. Verify tunnel shows HEALTHY in the dashboard
7. If using a custom domain: update nameservers at your registrar (e.g. Squarespace) to point to Cloudflare
8. In the tunnel detail page → Published application routes: add the subdomain, domain, and service URL (`HTTP://caddy.money-honey.svc.cluster.local:80`). This creates the DNS record automatically.
9. Open `https://<subdomain>.<domain>` in a browser

## Tetragon doubled log path

The Tetragon Helm chart concatenates `exportFilename` onto its own `exportDirectory`. Passing a full path like `/var/run/cilium/tetragon/tetragon.log` as `exportFilename` produced a doubled path: `/var/run/cilium/tetragon/var/run/cilium/tetragon/tetragon.log`. Fluent Bit was configured to tail the doubled path, so it worked, but the setup was fragile and confusing.

The fix: set `exportFilename` to the bare filename `tetragon.log`. The chart produces the clean path `/var/run/cilium/tetragon/tetragon.log`. Updated both `tetragon.tf` and the Fluent Bit ConfigMap to match.
