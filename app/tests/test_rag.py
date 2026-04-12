"""Tests for the RAG pipeline's pure-Python helpers.

These tests intentionally avoid loading the embedding model or Claude —
they exercise only the document loading and chunking logic.
"""

from __future__ import annotations

from pathlib import Path

from langchain_core.documents import Document

from rag import load_pdf_documents, split_documents


def test_load_pdf_documents_empty_directory(tmp_path: Path) -> None:
    """An empty folder should return an empty list, not crash."""
    result = load_pdf_documents(tmp_path)
    assert result == []


def test_split_documents_produces_chunks() -> None:
    """Splitter must break a long document into multiple chunks."""
    long_text = "Money Honey says save your money. " * 100  # ~3.4k chars
    doc = Document(page_content=long_text, metadata={"source": "test"})
    chunks = split_documents([doc])
    assert len(chunks) > 1, "long document should produce more than one chunk"
    # Metadata should survive the split
    for chunk in chunks:
        assert chunk.metadata.get("source") == "test"


def test_split_documents_handles_empty_input() -> None:
    """Zero documents in -> zero chunks out."""
    assert split_documents([]) == []
