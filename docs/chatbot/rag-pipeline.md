---
layout: default
title: RAG Pipeline
---

# 🔍 RAG pipeline

Money Honey answers with retrieval-augmented generation: every user question triggers a similarity search over a small local PDF corpus, and the top matches are stitched into the system prompt before Claude sees the message. The design is deliberately minimal.

## Components at a glance

| Stage | Tool | Where it runs |
|---|---|---|
| PDF loading | `PyPDFLoader` (LangChain) | FastAPI pod startup |
| Chunking | `RecursiveCharacterTextSplitter` | FastAPI pod startup |
| Embedding | `sentence-transformers/all-MiniLM-L6-v2` | In-process inside the FastAPI pod |
| Vector store | FAISS in-memory | FastAPI pod |
| Retrieval | FAISS `similarity_search(k=4)` | Per chat request |
| Generation | Anthropic Claude (Haiku 4.5) | Per chat request |

No external embedding API. No external vector database. The whole stack runs in-process inside the FastAPI container.

## Why local embeddings

The project originally considered OpenAI's `text-embedding-3-small` but went with local embeddings for two reasons:

1. Security surface. Local embeddings means one less external FQDN on the Cilium egress allowlist. The only outbound API call from the backend is to Claude.
2. Single-vendor AI dependency. The project targets Anthropic as the only AI provider. Anthropic doesn't offer an embeddings API, so local `sentence-transformers` was the cleanest answer.

Trade-offs:
- Pod memory: `all-MiniLM-L6-v2` is ~80 MB. FastAPI pod memory limit is 1 GiB, so plenty of headroom.
- First-request latency: the model loads from the HuggingFace cache on first use. Cold-start adds 2–5 s; every request after that is cached.
- Retrieval quality: MiniLM is a 384-dim model; OpenAI's is 1536-dim. For a small corpus (3–5 PDFs), the quality difference is negligible. If corpus size grows past ~50 documents, revisit.

## Chunking

`RecursiveCharacterTextSplitter` with:
- `chunk_size = 1000` characters
- `chunk_overlap = 150` characters (15%)

The splitter tries to break on paragraph, then sentence, then word, then character. This keeps semantically coherent blocks together when possible. The 15% overlap prevents context from being lost at chunk boundaries.

## Retrieval

```python
# From app/rag.py
def retrieve_context(index: FAISS, question: str, k: int = 4) -> str:
    results = index.similarity_search(question, k=k)
    return "\n\n---\n\n".join(doc.page_content for doc in results)
```

Top 4 chunks by cosine similarity, joined with a delimiter, passed to the LLM as the `{context}` placeholder in the Money Honey system prompt.

Four chunks × ~1000 chars each = ~4000 chars of retrieval context per turn. Well under Claude's input budget even accounting for the system prompt and history.

## Index lifecycle

FAISS is in-memory only. On pod startup:

1. Load every `*.pdf` in `app/knowledge_base/pdfs/` via `PyPDFLoader`
2. Split into chunks
3. Embed each chunk (slow on first run; fast after the HuggingFace cache is warm)
4. Build a FAISS `IndexFlatL2`
5. Done. Serve `/api/health` + `/api/chat`.

On pod restart, steps 1–4 repeat. No persistence between pod lifetimes. This is a conscious trade-off for v1:

- Pro: stateless pods, no PVC, no external dependencies.
- Con: cold-start is a few seconds slower than warm.
- v2 option: persist the FAISS index to a mounted Azure File share or a PVC to skip rebuild.

## Error behavior

Per `docs/specs/chatbot-v1.md` edge cases:

- No PDFs: `build_index()` returns `None`. `/api/health` reports `index_ready: false`. `/api/chat` returns 503. Pod doesn't crash.
- Bad PDF: `PyPDFLoader` raises, pod fails to start. Operator replaces the file. Fail loud, not silent.
- Claude API fails: current behavior is to surface as 500. Retry logic is a future hardening task.

## What Tetragon sees

The `secrets-file-audit` TracingPolicy (Layer 2) watches every file open under `/mnt/secrets/`. The FastAPI pod reads `/mnt/secrets/anthropic-api-key` on startup and (depending on LangChain's behavior) on each request. Every read lands in Splunk.

The `network-connect-audit` TracingPolicy captures every `tcp_connect()` from the pod. That's the ledger for "did FastAPI actually only talk to Claude's API today?"
