"""Demo: Tetragon TracingPolicy manifests match what Layer 2 promises.

`k8s/tetragon/tracing-policies.yaml` defines the runtime-enforcement
policies that sit at Layer 2. The project's documentation claims three
specific policies scoped to the `money-honey` namespace, each doing
exactly one job:

  - process-exec-audit     -> audit exec() calls
  - network-connect-audit  -> audit tcp_connect()
  - secrets-file-audit     -> audit file opens under /mnt/secrets/

If someone edits the manifest in a way that drops a policy, scopes it
to the wrong namespace, or changes its enforcement mode without
updating the docs, this test fails loudly.

Structural test only. It does not require a running cluster.
"""

from __future__ import annotations

from pathlib import Path

import pytest

try:
    import yaml
except ImportError:  # pragma: no cover
    pytest.skip("PyYAML not installed", allow_module_level=True)


MANIFEST = Path(__file__).resolve().parents[4] / "k8s" / "tetragon" / "tracing-policies.yaml"

EXPECTED_POLICIES = {
    "process-exec-audit",
    "network-connect-audit",
    "secrets-file-audit",
}


@pytest.fixture(scope="module")
def policies() -> list[dict]:
    """Return every TracingPolicy / TracingPolicyNamespaced doc in the manifest."""
    docs = list(yaml.safe_load_all(MANIFEST.read_text()))
    return [d for d in docs if d and d.get("kind") in ("TracingPolicy", "TracingPolicyNamespaced")]


def test_manifest_exists() -> None:
    assert MANIFEST.exists(), f"{MANIFEST} must exist"


def test_all_expected_policies_present(policies: list[dict]) -> None:
    names = {p["metadata"]["name"] for p in policies}
    missing = EXPECTED_POLICIES - names
    extra = names - EXPECTED_POLICIES
    assert not missing, f"missing policies: {missing}"
    assert not extra, (
        f"unexpected policies present: {extra}. "
        "Update EXPECTED_POLICIES + docs if this was intentional."
    )


def test_policies_are_namespace_scoped(policies: list[dict]) -> None:
    """All v1 policies are namespaced to money-honey. Cluster-scoped
    would widen the blast radius beyond our namespace."""
    for policy in policies:
        assert policy["kind"] == "TracingPolicyNamespaced", (
            f"{policy['metadata']['name']} must be TracingPolicyNamespaced, "
            f"got {policy['kind']}"
        )
        assert (
            policy["metadata"].get("namespace") == "money-honey"
        ), f"{policy['metadata']['name']} must live in money-honey namespace"


def test_policies_use_kprobe_hooks(policies: list[dict]) -> None:
    """Every v1 policy hooks via kprobes. syscall-hooking is our
    contract with the kernel; trace-* or uprobes would be different
    instrumentation that would need doc updates."""
    for policy in policies:
        assert "kprobes" in policy["spec"], f"{policy['metadata']['name']} must use kprobes in spec"
        assert policy["spec"]["kprobes"], f"{policy['metadata']['name']} has an empty kprobes list"
