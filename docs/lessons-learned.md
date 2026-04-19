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

With a 1 GiB memory limit, the pod was killed mid-embedding. The first symptom was empty logs (the process died before producing any output) and a `137` exit code in `kubectl describe pod`. Bumped to 2 GiB, same result. Finally resolved at 3 GiB, but the original `Standard_B2s` nodes (4 GB RAM each) could not fit two 3 GiB pods alongside system workloads. Upgraded to `Standard_B4ms` (16 GB RAM per node).

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

## Tetragon doubled log path

The Tetragon Helm chart concatenates `exportFilename` onto its own `exportDirectory`. Passing a full path like `/var/run/cilium/tetragon/tetragon.log` as `exportFilename` produced a doubled path: `/var/run/cilium/tetragon/var/run/cilium/tetragon/tetragon.log`. Fluent Bit was configured to tail the doubled path, so it worked, but the setup was fragile and confusing.

The fix: set `exportFilename` to the bare filename `tetragon.log`. The chart produces the clean path `/var/run/cilium/tetragon/tetragon.log`. Updated both `tetragon.tf` and the Fluent Bit ConfigMap to match.
