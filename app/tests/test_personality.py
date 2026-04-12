"""Tests for the Money Honey personality prompt."""

from __future__ import annotations

from personality import SYSTEM_PROMPT


def test_system_prompt_has_context_placeholder() -> None:
    """The prompt must accept a `{context}` parameter — the RAG chunks go here."""
    assert "{context}" in SYSTEM_PROMPT


def test_system_prompt_formats_without_error() -> None:
    """Substituting a context string must not raise or leave placeholders."""
    filled = SYSTEM_PROMPT.format(context="example retrieval chunk")
    assert "{context}" not in filled
    assert "example retrieval chunk" in filled


def test_system_prompt_mentions_personal_finance_domain() -> None:
    """Sanity check that the personality stays on-topic."""
    lowered = SYSTEM_PROMPT.lower()
    assert "personal finance" in lowered
