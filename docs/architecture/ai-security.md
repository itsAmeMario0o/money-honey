---
layout: default
title: AI and LLM Security
---

# 🤖 AI / LLM Security (Layer 5)

AI projects have a unique threat surface: poisoned models, poisoned retrieval corpora, and AI-generated code that slips past traditional static analysis. Layer 5 wires four independent tools across the AI lifecycle: three from Cisco AI Defense plus CoSAI CodeGuard.

## AIBOM (AI Bill of Materials)

`.github/workflows/aibom.yaml` runs on every pull request that touches `app/` or `frontend/`. It produces a machine-readable manifest of every AI component, model version, and dependency involved in the PR. An untracked component fails the workflow and blocks merge.

Think of it as an SBOM but specifically for the AI side: frameworks, models, retrieval corpus, prompt libraries, evaluation datasets.

## Adversarial Hubness Detector

`.github/workflows/hubness-scan.yaml` runs on every PR that modifies anything under `app/knowledge_base/`. It computes hubness scores across the retrieval corpus to detect documents engineered to skew RAG retrieval toward attacker-preferred content. Threshold exceedance blocks the PR.

RAG poisoning is a real and under-appreciated risk. This closes it at the PR gate, before the content ever reaches production.

## IDE AI Security Scanner

Runs locally in VS Code while developers write code. Catches common AI-adjacent anti-patterns early: prompt-injection vectors, unsafe tool invocations, overly permissive system-prompt structures, and leaking of prompt context back to the user.

Combined with Layer 6's pre-commit hook (gitleaks for secrets, tfsec for infrastructure), this gives the developer three fast feedback loops before code even leaves their laptop.

## CodeGuard (OASIS / CoSAI)

[Project CodeGuard](https://github.com/cosai-oasis/project-codeguard) is an OASIS Open project under the Coalition for Secure AI. It ships as a Claude Code plugin (`codeguard-security@project-codeguard`) that injects a curated security rulebook into every Claude Code session as standing context. Rules cover eight domains: cryptography (including post-quantum), input validation, authn/authz, supply chain, cloud, platform, and data protection.

Where the Cisco IDE Scanner watches what the developer writes in VS Code, CodeGuard watches what Claude itself generates during agent-assisted coding. The two are complementary: the IDE Scanner catches patterns, CodeGuard prevents them from being written. Both pair with the post-write gates (gitleaks, tfsec, ruff) for three independent windows on the same bug class.

CoSAI sits in the same industry consortium as Cisco AI Defense. Choosing CodeGuard keeps this project's AI-security layer coherent with a single standards body rather than a pile of unrelated tools.

## Why it matters for this project

The chatbot runs a local sentence-transformers embedding model and retrieves from a small, local PDF corpus. Even in that minimal surface, every path matters:
- A poisoned PDF could bias answers toward fraudulent guidance.
- A prompt-injection payload in a user message could exfiltrate the system prompt.
- A rogue dependency pulling in a compromised model could leak user prompts off-cluster.

Layer 5 guards all three. Layer 1 (Cilium) provides the network backstop if any of them fail open.
