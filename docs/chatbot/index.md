---
layout: default
title: Chatbot internals
---

# 💬 Chatbot internals

Money Honey is a financial-education chatbot grounded in a small set of PDFs. The chatbot is the demo; the security architecture is the lesson — but the demo still has to work.

| Page | What it covers |
|---|---|
| [RAG pipeline](rag-pipeline.html) | LangChain + FAISS + Claude integration. PDF ingestion, chunking, retrieval, prompt construction. |
| [Money Honey personality](personality.html) | The system-prompt design — voice, traits, conversational guardrails. |

The full application spec lives at [`docs/specs/chatbot-v1.md`](../specs/chatbot-v1.html).
