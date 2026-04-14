# Demo fixtures for the Money Honey walkthrough

This directory is for **demo artifacts** — code and tests that exist to
illustrate one of Money Honey's security layers end-to-end, not to power
the chatbot itself.

Everything here is import-safe (no side effects, no network) and runs
as part of the regular `pytest` suite, so the demos stay honest: if a
demo regresses, CI breaks.

## Current demos

| Path | Layer it showcases | What it proves |
|---|---|---|
| [`codeguard/path_traversal.py`](codeguard/path_traversal.py) + [`test_path_traversal.py`](codeguard/test_path_traversal.py) | Layer 5 — CoSAI/OASIS CodeGuard agent rules | A deliberately risky prompt ("open a user-supplied filename") produced CodeGuard-compliant code: allowlist base dir, reject absolute paths, resolve-then-verify-containment, reject symlink escapes, reject non-regular files, cap read size. Tests assert each rule's behavior. |

## Adding new demos

When you build the full demo workflow, drop new demos here one
directory per layer (e.g. `tetragon/`, `cilium/`, `aibom/`,
`hubness/`). Each demo should:

1. Include a short module docstring pointing to the layer and the rule
   being illustrated.
2. Ship with a pytest file next to it that exercises the rule.
3. Stay self-contained — no network, no Azure credentials, no cluster
   access. Demos that require live infra belong in the runbooks, not
   here.
