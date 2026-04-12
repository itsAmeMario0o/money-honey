---
layout: default
title: AI and LLM Security
---

# 🤖 AI / LLM Security (Layer 5)

AI projects have a unique threat surface: poisoned models, poisoned retrieval corpora, and AI-generated code that slips past traditional static analysis. Layer 5 wires three independent Cisco AI Defense tools across the AI lifecycle.

## AIBOM — AI Bill of Materials

`.github/workflows/aibom.yaml` runs on every pull request that touches `app/` or `frontend/`. It produces a machine-readable manifest of every AI component, model version, and dependency involved in the PR. An untracked component fails the workflow and blocks merge.

Think of it as an SBOM but specifically for the AI side: frameworks, models, retrieval corpus, prompt libraries, evaluation datasets.

## Adversarial Hubness Detector

`.github/workflows/hubness-scan.yaml` runs on every PR that modifies anything under `app/knowledge_base/`. It computes hubness scores across the retrieval corpus to detect documents engineered to skew RAG retrieval toward attacker-preferred content. Threshold exceedance blocks the PR.

RAG poisoning is a real and under-appreciated risk. This closes it at the PR gate, before the content ever reaches production.

## IDE AI Security Scanner

Runs locally in VS Code while developers write code. Catches common AI-adjacent anti-patterns early: prompt-injection vectors, unsafe tool invocations, overly permissive system-prompt structures, and leaking of prompt context back to the user.

Combined with Layer 6's pre-commit hook (gitleaks for secrets, tfsec for infrastructure), this gives the developer three fast feedback loops before code even leaves their laptop.

## Why it matters for this project

The chatbot runs a local sentence-transformers embedding model and retrieves from a small, local PDF corpus. Even in that minimal surface, every path matters:
- A poisoned PDF could bias answers toward fraudulent guidance.
- A prompt-injection payload in a user message could exfiltrate the system prompt.
- A rogue dependency pulling in a compromised model could leak user prompts off-cluster.

Layer 5 guards all three. Layer 1 (Cilium) provides the network backstop if any of them fail open.
