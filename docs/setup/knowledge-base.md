---
layout: default
title: Managing the knowledge base
---

# 📚 Managing the knowledge base

Money Honey's answers come from PDFs stored on an Azure File share mounted into the FastAPI pods. Adding, replacing, or removing documents is a three-step process: copy the file, restart the pods, verify the index rebuilt.

## How it works

```
Your machine                    Azure File share               FastAPI pod
┌──────────┐   kubectl cp      ┌──────────────┐   PVC mount   ┌──────────┐
│ new.pdf  │ ─────────────────>│ knowledge-   │ ─────────────>│ /app/    │
└──────────┘                   │ base share   │               │ knowledge│
                               └──────────────┘               │ _base/   │
                                                               │ pdfs/   │
                                                               └──────────┘
```

The Azure File share persists across pod restarts, redeployments, and node replacements. You upload once. Every current and future pod sees the files.

## Upload a new PDF

```zsh
POD=$(kubectl -n money-honey get pods -l app=fastapi -o jsonpath='{.items[0].metadata.name}')

kubectl -n money-honey cp /path/to/your-document.pdf $POD:/app/knowledge_base/pdfs/your-document.pdf
```

Tips:
- Avoid spaces and special characters in filenames. `kubectl cp` uses tar under the hood and can silently fail on brackets or spaces. Rename first if needed.
- The file lands on the Azure File share, not the container filesystem. Both pods see it immediately.

## Rebuild the index

The FAISS index is built at startup from whatever PDFs are in the directory. A restart triggers a rebuild:

```zsh
kubectl -n money-honey rollout restart deployment/fastapi
```

Wait for both pods to show `1/1 Running`:

```zsh
kubectl -n money-honey get pods -l app=fastapi -w
```

Then verify the index picked up the new content:

```zsh
kubectl -n money-honey exec deploy/fastapi -- python -c "import urllib.request; print(urllib.request.urlopen('http://localhost:8000/api/health').read().decode())"
```

`index_ready: true` means the rebuild succeeded.

## Remove a PDF

```zsh
POD=$(kubectl -n money-honey get pods -l app=fastapi -o jsonpath='{.items[0].metadata.name}')
kubectl -n money-honey exec $POD -- rm /app/knowledge_base/pdfs/unwanted-document.pdf
kubectl -n money-honey rollout restart deployment/fastapi
```

## List current PDFs

```zsh
kubectl -n money-honey exec deploy/fastapi -- ls -la /app/knowledge_base/pdfs/
```

## Upload multiple PDFs at once

Copy an entire local directory:

```zsh
kubectl -n money-honey cp /path/to/pdf-folder/. $POD:/app/knowledge_base/pdfs/
kubectl -n money-honey rollout restart deployment/fastapi
```

## Scaling considerations

| Corpus size | Startup time | Memory peak | Action needed |
|---|---|---|---|
| Up to 50 MB (current) | ~10 min | ~1.5 GiB | None |
| 50-100 MB | ~15-20 min | ~2.5 GiB | Watch startup probe budget |
| 100+ MB | 20+ min | 3+ GiB | Increase `failureThreshold` and `memory` limit in deployment.yaml |
| 50+ documents | Any | Any | Consider hybrid search (BM25 + vector) per the v2 roadmap |

The startup probe currently allows 15 minutes (`failureThreshold: 90`, `periodSeconds: 10`). If your corpus grows past what fits in that window, increase `failureThreshold` in `k8s/app/deployment.yaml`.

## Adapting for other RAG use cases

This pattern works for any RAG pipeline that reads documents from a filesystem at startup. To adapt it:

1. Replace the PDFs with your domain-specific documents (legal contracts, medical records, product manuals, etc.)
2. Update the system prompt in `app/personality.py` to match the new domain
3. Adjust the chunking parameters in `app/rag.py` if the document structure differs (e.g., shorter chunks for dense legal text, longer chunks for narrative content)
4. The embedding model (`sentence-transformers/all-MiniLM-L6-v2`) is domain-agnostic and works well for general text. For specialized domains with technical vocabulary, consider a domain-specific model.

The infrastructure (Azure Files, PVC mounts, FAISS, Cilium network policy, Tetragon audit) stays the same regardless of the documents or the domain.

## CI integration

PDFs committed to `app/knowledge_base/pdfs/` in the Git repo trigger the Hubness Detector workflow (`hubness-scan.yaml`), which checks for adversarial documents designed to skew retrieval. PDFs uploaded directly to the Azure File share via `kubectl cp` bypass this check. For production use, consider a CI-gated upload path.
