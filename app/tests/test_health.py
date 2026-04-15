"""Tests for the /api/health and /api/chat endpoints.

We import `main` lazily and patch out the module-level LLM and vector
index initialization so the app starts cleanly in tests (no network,
no embedding-model download).
"""

from __future__ import annotations

import importlib
import os
import sys
from collections.abc import Generator
from typing import Any
from unittest.mock import MagicMock, patch

import pytest
from fastapi.testclient import TestClient


def _fresh_main(with_llm: bool = False, with_index: bool = False) -> Any:
    """Import `main` with external dependencies patched to the requested state."""
    sys.modules.pop("main", None)
    os.environ["ANTHROPIC_API_KEY"] = "sk-ant-test-key" if with_llm else ""
    os.environ.setdefault("ALLOWED_ORIGINS", "http://localhost:3000")

    index_stub = MagicMock() if with_index else None
    with patch("rag.build_index", return_value=index_stub):
        return importlib.import_module("main")


@pytest.fixture
def client() -> TestClient:
    """App with no LLM and no index. Default state for failure-path tests."""
    main = _fresh_main(with_llm=False, with_index=False)
    return TestClient(main.app)


@pytest.fixture
def ready_client() -> Generator[TestClient, None, None]:
    """App with both LLM and index available. For happy-path tests."""
    main = _fresh_main(with_llm=True, with_index=True)

    # Replace the real ChatAnthropic with a stub that returns a canned reply.
    fake_reply = MagicMock()
    fake_reply.content = "Babe, save your money first."
    main.llm = MagicMock()
    main.llm.invoke.return_value = fake_reply

    # retrieve_context is called with the stub index; return a benign string.
    with patch("main.retrieve_context", return_value="chunk-1\n\nchunk-2"):
        yield TestClient(main.app)


# ---------------------------------------------------------------------------
# /api/health
# ---------------------------------------------------------------------------


def test_health_returns_200(client: TestClient) -> None:
    response = client.get("/api/health")
    assert response.status_code == 200


def test_health_returns_expected_shape(client: TestClient) -> None:
    body = client.get("/api/health").json()
    assert body["status"] == "ok"
    assert "index_ready" in body
    assert "llm_ready" in body


def test_health_types_are_strict_booleans(client: TestClient) -> None:
    """index_ready / llm_ready must be booleans, not truthy strings."""
    body = client.get("/api/health").json()
    assert isinstance(body["index_ready"], bool)
    assert isinstance(body["llm_ready"], bool)


def test_health_reports_not_ready_when_unconfigured(client: TestClient) -> None:
    body = client.get("/api/health").json()
    assert body["index_ready"] is False
    assert body["llm_ready"] is False


def test_health_reports_ready_when_configured(ready_client: TestClient) -> None:
    body = ready_client.get("/api/health").json()
    assert body["index_ready"] is True
    assert body["llm_ready"] is True


# ---------------------------------------------------------------------------
# /api/chat — failure paths
# ---------------------------------------------------------------------------


def test_chat_returns_503_when_llm_missing(client: TestClient) -> None:
    """With no API key, /api/chat should fail loudly with 503."""
    response = client.post("/api/chat", json={"message": "test"})
    assert response.status_code == 503


def test_chat_returns_503_when_index_missing() -> None:
    """LLM configured but no PDFs loaded -> 503, not a crash."""
    main = _fresh_main(with_llm=True, with_index=False)
    main.llm = MagicMock()  # LLM present
    response = TestClient(main.app).post("/api/chat", json={"message": "hi"})
    assert response.status_code == 503


def test_chat_rejects_empty_message(client: TestClient) -> None:
    """Pydantic min_length=1 should 422 before reaching the handler."""
    response = client.post("/api/chat", json={"message": ""})
    assert response.status_code == 422


def test_chat_rejects_message_over_limit(client: TestClient) -> None:
    """Pydantic max_length=2000 is the hard cap per ChatRequest."""
    long_message = "x" * 2001
    response = client.post("/api/chat", json={"message": long_message})
    assert response.status_code == 422


def test_chat_rejects_missing_message_field(client: TestClient) -> None:
    response = client.post("/api/chat", json={})
    assert response.status_code == 422


def test_chat_rejects_wrong_type(client: TestClient) -> None:
    """message must be a string; sending a list/dict is rejected."""
    response = client.post("/api/chat", json={"message": ["not", "a", "string"]})
    assert response.status_code == 422


def test_chat_rejects_non_json_body(client: TestClient) -> None:
    """Content-type plain/text shouldn't be silently accepted."""
    response = client.post(
        "/api/chat",
        content=b"message=hello",
        headers={"content-type": "application/x-www-form-urlencoded"},
    )
    assert response.status_code == 422


# ---------------------------------------------------------------------------
# /api/chat — happy path (mocked LLM)
# ---------------------------------------------------------------------------


def test_chat_returns_200_when_configured(ready_client: TestClient) -> None:
    response = ready_client.post("/api/chat", json={"message": "Should I save?"})
    assert response.status_code == 200


def test_chat_response_shape(ready_client: TestClient) -> None:
    body = ready_client.post("/api/chat", json={"message": "hi"}).json()
    assert "reply" in body
    assert "sources_used" in body
    assert isinstance(body["reply"], str)
    assert isinstance(body["sources_used"], int)


def test_chat_sources_used_is_four(ready_client: TestClient) -> None:
    """chatbot-v1 spec: retrieval pulls top-k=4 chunks per turn."""
    body = ready_client.post("/api/chat", json={"message": "hi"}).json()
    assert body["sources_used"] == 4


def test_chat_accepts_boundary_length_messages(ready_client: TestClient) -> None:
    """Messages of length 1 and 2000 are both valid."""
    r1 = ready_client.post("/api/chat", json={"message": "a"})
    r2 = ready_client.post("/api/chat", json={"message": "x" * 2000})
    assert r1.status_code == 200
    assert r2.status_code == 200


# ---------------------------------------------------------------------------
# CORS middleware
# ---------------------------------------------------------------------------


def test_cors_preflight_allows_configured_origin(client: TestClient) -> None:
    """Preflight from the allowlisted origin gets an Allow-Origin echo."""
    response = client.options(
        "/api/chat",
        headers={
            "origin": "http://localhost:3000",
            "access-control-request-method": "POST",
            "access-control-request-headers": "content-type",
        },
    )
    assert response.status_code == 200
    assert response.headers.get("access-control-allow-origin") == "http://localhost:3000"


def test_cors_preflight_rejects_unknown_origin(client: TestClient) -> None:
    """An origin not in ALLOWED_ORIGINS must NOT receive an allow-origin header."""
    response = client.options(
        "/api/chat",
        headers={
            "origin": "https://evil.example.com",
            "access-control-request-method": "POST",
            "access-control-request-headers": "content-type",
        },
    )
    # FastAPI's CORSMiddleware returns 400 on disallowed preflight.
    assert response.headers.get("access-control-allow-origin") != "https://evil.example.com"
