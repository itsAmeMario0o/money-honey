"""Demo: every `.trivyignore.yaml` entry must expire within policy.

Shows Layer 6 (CI gates) with a concrete guardrail: no permanent
Trivy ignores. Every suppression must have an `expiredAt` date that is
(a) in the future and (b) no more than 1 year out. Prevents the slow
decay of a CVE-suppression list into a permanent amnesty.

Runs in the regular pytest suite. Failing this test = someone added an
ignore without an expiry, or set expiredAt too far out, or let an
existing entry lapse past its expiration without remediation.
"""

from __future__ import annotations

from datetime import date, timedelta
from pathlib import Path

import pytest

try:
    import yaml  # type: ignore[import-untyped]
except ImportError:  # pragma: no cover - PyYAML ships with k8s + ansible tooling
    pytest.skip("PyYAML not installed", allow_module_level=True)


IGNORE_FILE = Path(__file__).resolve().parents[4] / ".trivyignore.yaml"
MAX_EXPIRY_WINDOW = timedelta(days=365)


def _load_entries() -> list[dict]:
    """Return every vulnerability + misconfiguration entry in the file."""
    if not IGNORE_FILE.exists():
        return []
    doc = yaml.safe_load(IGNORE_FILE.read_text()) or {}
    return list(doc.get("vulnerabilities", [])) + list(doc.get("misconfigurations", []))


@pytest.fixture(scope="module")
def entries() -> list[dict]:
    return _load_entries()


def test_trivyignore_file_exists() -> None:
    assert IGNORE_FILE.exists(), f"{IGNORE_FILE} must exist"


def test_every_entry_has_an_id(entries: list[dict]) -> None:
    for entry in entries:
        assert entry.get("id"), f"entry missing id: {entry}"


def test_every_entry_has_expiredAt(entries: list[dict]) -> None:
    """No entry may be open-ended. An ignore without a deadline becomes permanent."""
    for entry in entries:
        assert (
            "expiredAt" in entry
        ), f"{entry.get('id')} is missing expiredAt — add one or remove the ignore"


def test_expiredAt_is_in_the_future(entries: list[dict]) -> None:
    """Past-due ignores must be revisited (remediate the CVE or re-extend)."""
    today = date.today()
    for entry in entries:
        expiry = entry["expiredAt"]
        if isinstance(expiry, str):
            expiry = date.fromisoformat(expiry)
        assert expiry > today, f"{entry['id']} expired on {expiry} — remediate or re-extend"


def test_expiredAt_within_policy_window(entries: list[dict]) -> None:
    """Ignores can't be set more than 1 year out."""
    today = date.today()
    for entry in entries:
        expiry = entry["expiredAt"]
        if isinstance(expiry, str):
            expiry = date.fromisoformat(expiry)
        window = expiry - today
        assert window <= MAX_EXPIRY_WINDOW, (
            f"{entry['id']} expires in {window.days} days — policy limit is "
            f"{MAX_EXPIRY_WINDOW.days}"
        )
