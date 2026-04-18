---
layout: default
title: RAG Pipeline
---

# 🔍 RAG pipeline

Every user question triggers a similarity search over a small local PDF corpus. The top matches are stitched into the system prompt before Claude sees the message. The frontend sends the full conversation history with each request so Claude can reference prior turns. Deliberately minimal.

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

OpenAI's `text-embedding-3-small` was the obvious alternative. Two reasons tipped the decision toward local:

1. Security surface. Local embeddings means one fewer external FQDN on the Cilium egress allowlist. The only outbound API call from the backend is to Claude.
2. Single-vendor AI dependency. Anthropic is the only AI provider. Anthropic does not offer an embeddings API, so local `sentence-transformers` was the cleanest fit.

Trade-offs:
- Pod memory: `all-MiniLM-L6-v2` is ~80 MB. FastAPI pod memory limit is 1 GiB. Plenty of headroom.
- First-request latency: the model loads from the HuggingFace cache on first use. Cold-start adds 2-5 s; every request after that is cached.
- Retrieval quality: MiniLM is a 384-dim model; OpenAI's is 1536-dim. For a small corpus (3-5 PDFs), the quality difference is negligible. If corpus size grows past ~50 documents, revisit.

## Chunking

`RecursiveCharacterTextSplitter` with:
- `chunk_size = 1000` characters
- `chunk_overlap = 150` characters (15%)

The splitter tries to break on paragraph, then sentence, then word, then character. Semantically coherent blocks stay together when possible. The 15% overlap prevents context loss at chunk boundaries.

## Retrieval

```python
# From app/rag.py
def retrieve_context(index: FAISS, question: str, k: int = 4) -> str:
    results = index.similarity_search(question, k=k)
    return "\n\n---\n\n".join(doc.page_content for doc in results)
```

Top 4 chunks by cosine similarity, joined with a delimiter, passed to the LLM as the `{context}` placeholder in the Money Honey system prompt. Retrieval uses only the current message, not the full conversation history. This keeps retrieval focused on the immediate question and avoids context dilution from prior turns.

Four chunks × ~1000 chars each = ~4000 chars of retrieval context per turn. Well under Claude's input budget even accounting for the system prompt, conversation history, and the current message.

## Index lifecycle

FAISS is in-memory only. On pod startup:

1. Load every `*.pdf` in `app/knowledge_base/pdfs/` via `PyPDFLoader`
2. Split into chunks
3. Embed each chunk (slow on first run; fast after the HuggingFace cache is warm)
4. Build a FAISS `IndexFlatL2`
5. Done. Serve `/api/health` + `/api/chat`.

On pod restart, steps 1-4 repeat. No persistence between pod lifetimes. Conscious trade-off for v1:

- Pro: pods are stateless at the infrastructure level. No PVC, no external dependencies. Conversation history lives in the frontend's component state, not on the server, so pod restarts do not lose user data.
- Con: cold-start is a few seconds slower than warm.
- v2 option: persist the FAISS index to a mounted Azure File share or a PVC to skip rebuild.

## Error behavior

Per `docs/specs/chatbot-v1.md` edge cases:

- No PDFs: `build_index()` returns `None`. `/api/health` reports `index_ready: false`. `/api/chat` returns 503. Pod does not crash.
- Bad PDF: `PyPDFLoader` raises, pod fails to start. You replace the file. Fail loud, not silent.
- Claude API fails: surfaces as 500. Retry logic is a future hardening task.

## Conversation memory

The frontend maintains a list of prior messages (`{role, content}` pairs) in React component state and sends them with every `/api/chat` request. The backend assembles the Claude message chain as: system prompt → trimmed history → current message.

Key constraints per the agentic-v1 spec:

- History is session-scoped. Closing the browser tab clears it. No server-side persistence.
- History is capped at 20 turns (10 user + 10 assistant). Older turns are dropped first.
- RAG retrieval uses only the current message, not the history. Claude sees the history for conversational coherence, but the vector search stays focused.
- The `history` field is optional. Omitting it or sending `[]` preserves backward compatibility with one-shot API clients.
- Only `"user"` and `"assistant"` roles are accepted. Sending `"system"` in the history array returns 422.

## What Tetragon sees

The `secrets-file-audit` TracingPolicy (Layer 2) watches every file open under `/mnt/secrets/`. The FastAPI pod reads `/mnt/secrets/anthropic-api-key` on startup and (depending on LangChain's behavior) on each request. Every read lands in Splunk.

The `network-connect-audit` TracingPolicy captures every `tcp_connect()` from the pod. That is the ledger for "did FastAPI actually only talk to Claude's API today?"
