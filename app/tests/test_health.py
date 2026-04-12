"""Tests for the /api/health endpoint.

We import `main` lazily and patch out the module-level LLM and vector
index initialization so the app starts cleanly in tests (no network,
no embedding-model download).
"""

from __future__ import annotations

import importlib
import os
import sys
from unittest.mock import patch

import pytest
from fastapi.testclient import TestClient


@pytest.fixture
def client() -> TestClient:
    """Import `main` with external dependencies patched, yield a TestClient."""
    # Reset any cached `main` so patches take effect on fresh import.
    sys.modules.pop("main", None)
    os.environ.setdefault("ANTHROPIC_API_KEY", "")
    os.environ.setdefault("ALLOWED_ORIGINS", "http://localhost:3000")

    with patch("rag.build_index", return_value=None):
        main = importlib.import_module("main")
    return TestClient(main.app)


def test_health_returns_200(client: TestClient) -> None:
    response = client.get("/api/health")
    assert response.status_code == 200


def test_health_returns_expected_shape(client: TestClient) -> None:
    body = client.get("/api/health").json()
    assert body["status"] == "ok"
    assert "index_ready" in body
    assert "llm_ready" in body


def test_chat_returns_503_when_index_missing(client: TestClient) -> None:
    """With no PDFs and no API key, /api/chat should fail loudly with 503."""
    response = client.post("/api/chat", json={"message": "test"})
    assert response.status_code == 503
