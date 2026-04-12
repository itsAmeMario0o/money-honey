"""FastAPI entrypoint for Money Honey.

Exposes two endpoints:
- GET  /api/health  — liveness check for Kubernetes.
- POST /api/chat    — accepts a user message and returns Money Honey's reply.
"""

from __future__ import annotations

import os

from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from langchain_anthropic import ChatAnthropic
from langchain_core.messages import HumanMessage, SystemMessage
from pydantic import BaseModel, Field, SecretStr

from personality import SYSTEM_PROMPT
from rag import build_index, retrieve_context

load_dotenv()

ANTHROPIC_API_KEY = os.getenv("ANTHROPIC_API_KEY", "")
ALLOWED_ORIGINS = os.getenv("ALLOWED_ORIGINS", "http://localhost:3000").split(",")
MODEL_NAME = "claude-haiku-4-5-20251001"


class ChatRequest(BaseModel):
    """Payload sent by the frontend on every chat turn."""

    message: str = Field(..., min_length=1, max_length=2000)


class ChatResponse(BaseModel):
    """Payload returned to the frontend."""

    reply: str
    sources_used: int


app = FastAPI(title="Money Honey API", version="0.1.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS,
    allow_credentials=False,
    allow_methods=["GET", "POST"],
    allow_headers=["Content-Type"],
)

vector_index = build_index()
llm = (
    ChatAnthropic(model_name=MODEL_NAME, api_key=SecretStr(ANTHROPIC_API_KEY))
    if ANTHROPIC_API_KEY
    else None
)


@app.get("/api/health")
def health() -> dict:
    """Return a simple readiness signal. Used by Kubernetes probes."""
    return {
        "status": "ok",
        "index_ready": vector_index is not None,
        "llm_ready": llm is not None,
    }


@app.post("/api/chat", response_model=ChatResponse)
def chat(request: ChatRequest) -> ChatResponse:
    """Handle one chat turn. Pull context from FAISS and call Claude."""
    if llm is None:
        raise HTTPException(status_code=503, detail="LLM is not configured.")
    if vector_index is None:
        raise HTTPException(status_code=503, detail="Knowledge base is empty.")

    context = retrieve_context(vector_index, request.message)
    messages: list = [
        SystemMessage(content=SYSTEM_PROMPT.format(context=context)),
        HumanMessage(content=request.message),
    ]
    answer = llm.invoke(messages)
    # answer.content may be str or list[str|dict]; coerce to a single string.
    reply_text = answer.content if isinstance(answer.content, str) else str(answer.content)
    return ChatResponse(reply=reply_text, sources_used=4)
