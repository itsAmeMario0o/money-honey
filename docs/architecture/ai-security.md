---
layout: default
title: AI and LLM Security
---

# 🤖 AI / LLM security (Layer 5)

AI projects have a threat surface that traditional infrastructure controls do not cover: poisoned models, poisoned retrieval corpora, and AI-generated code that slips past static analysis. Layer 5 wires four independent tools across the AI lifecycle, three from Cisco AI Defense plus CoSAI CodeGuard.

## AIBOM (AI Bill of Materials)

A new dependency sneaks into a PR. Nobody notices the model version changed or a prompt library was swapped.

`.github/workflows/aibom.yaml` catches that. It runs on every pull request touching `app/` or `frontend/`, producing a machine-readable manifest of every AI component, model version, and dependency in the PR. An untracked component fails the workflow and blocks merge. Same idea as an SBOM, but for the AI side: frameworks, models, retrieval corpus, prompt libraries, evaluation datasets.

## Adversarial Hubness Detector

Someone contributes a PDF that looks like legitimate financial guidance but is engineered to dominate retrieval results. Every user question now returns attacker-controlled content.

`.github/workflows/hubness-scan.yaml` runs on every PR that modifies anything under `app/knowledge_base/`. It computes hubness scores across the retrieval corpus to detect documents designed to skew RAG retrieval. Threshold exceedance blocks the PR, before the content ever reaches production.

## IDE AI Security Scanner

Runs locally in VS Code while you write code. Catches AI-adjacent anti-patterns early: prompt-injection vectors, unsafe tool invocations, overly permissive system-prompt structures, and leaking prompt context back to the user.

Combined with Layer 6's pre-commit hook (gitleaks for secrets, tfsec for infrastructure), that is three fast feedback loops before code leaves your laptop.

## CodeGuard (OASIS / CoSAI)

[Project CodeGuard](https://github.com/cosai-oasis/project-codeguard) is an OASIS Open project under the Coalition for Secure AI. It ships as a Claude Code plugin (`codeguard-security@project-codeguard`) that injects a curated security rulebook into every Claude Code session as standing context. Rules cover eight domains: cryptography (including post-quantum), input validation, authn/authz, supply chain, cloud, platform, and data protection.

The Cisco IDE Scanner watches what you write in VS Code. CodeGuard watches what Claude generates during agent-assisted coding. The two are complementary: the scanner catches patterns after they are typed, CodeGuard prevents them from being written in the first place. Both pair with the post-write gates (gitleaks, tfsec, ruff) for three independent windows on the same bug class.

CoSAI sits in the same industry consortium as Cisco AI Defense. CodeGuard keeps the AI-security layer coherent with a single standards body rather than a pile of unrelated tools.

## Why it matters here

The chatbot runs a local sentence-transformers embedding model and retrieves from a small PDF corpus. Even in that minimal surface, every path matters:
- A poisoned PDF could bias answers toward fraudulent guidance.
- A prompt-injection payload in a user message could exfiltrate the system prompt.
- A rogue dependency pulling in a compromised model could leak user prompts off-cluster.

Layer 5 guards all three paths. Layer 1 (Cilium) provides the network backstop if any of them fail open.
