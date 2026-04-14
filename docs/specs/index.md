---
layout: default
title: Specifications
---

# 📐 Specifications

Design specs for each layer of Money Honey. Every spec was written before the code per the `spec-driven-workflow` skill, and stays in sync with the implementation as the project evolves.

| Spec | Scope |
|---|---|
| [Chatbot v1](chatbot-v1.html) | FastAPI + LangChain + FAISS + Claude application layer. |
| [Infrastructure v1](infra-v1.html) | Terraform modules, AKS topology, Key Vault, networking, Splunk VM. |
| [Kubernetes v1](k8s-v1.html) | Manifests, CiliumNetworkPolicies, Tetragon TracingPolicies, CSI SecretProviderClasses. |
| [CI/CD v1](cicd-v1.html) | GitHub Actions workflows: quality, docker-build, deploy, aibom, hubness-scan. |
| [Cloudflare Access v1](cloudflare-access-v1.html) | Layer 8 public-edge spec: tunnels, hostnames, Access policies. |

Changes to the system start with a PR that updates the relevant spec first, then the code follows.
