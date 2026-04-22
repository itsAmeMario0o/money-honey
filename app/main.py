"""FastAPI entrypoint for Money Honey.

Exposes two endpoints:
- GET  /api/health  — liveness check for Kubernetes.
- POST /api/chat    — accepts a user message and returns Money Honey's reply.
  Supports multi-turn conversation history per agentic-v1 spec Tier 1.
"""

from __future__ import annotations

import os
from typing import Literal

from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from langchain_anthropic import ChatAnthropic
from langchain_core.messages import AIMessage, HumanMessage, SystemMessage
from pydantic import BaseModel, Field, SecretStr

from personality import SYSTEM_PROMPT
from rag import build_index, retrieve_context

load_dotenv()

ANTHROPIC_API_KEY = os.getenv("ANTHROPIC_API_KEY", "")
ALLOWED_ORIGINS = os.getenv("ALLOWED_ORIGINS", "http://localhost:3000").split(",")
MODEL_NAME = "claude-haiku-4-5-20251001"
MAX_HISTORY_TURNS = 20
MAX_REQUEST_BYTES = 100 * 1024


class HistoryMessage(BaseModel):
    role: Literal["user", "assistant"]
    content: str = Field(..., max_length=4000)


class ChatRequest(BaseModel):
    message: str = Field(..., min_length=1, max_length=2000)
    history: list[HistoryMessage] = Field(default_factory=list)


class ChatResponse(BaseModel):
    reply: str
    sources_used: int


app = FastAPI(title="Money Honey API", version="0.2.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS,
    allow_credentials=False,
    allow_methods=["GET", "POST"],
    allow_headers=["Content-Type"],
)

vector_index = build_index()
llm = (
    ChatAnthropic(
        model_name=MODEL_NAME,
        api_key=SecretStr(ANTHROPIC_API_KEY),
        timeout=30.0,
        stop=None,
    )
    if ANTHROPIC_API_KEY
    else None
)


def _build_message_list(
    system_prompt: str,
    history: list[HistoryMessage],
    current_message: str,
) -> list:
    """Assemble the message list sent to Claude.

    Enforces MAX_HISTORY_TURNS by dropping the oldest turns first.
    RAG retrieval uses the current message only (FR-6).
    """
    trimmed = history[-MAX_HISTORY_TURNS:]

    messages: list = [SystemMessage(content=system_prompt)]
    for turn in trimmed:
        if turn.role == "user":
            messages.append(HumanMessage(content=turn.content))
        else:
            messages.append(AIMessage(content=turn.content))
    messages.append(HumanMessage(content=current_message))
    return messages


@app.get("/api/health")
def health() -> dict:
    return {
        "status": "ok",
        "index_ready": vector_index is not None,
        "llm_ready": llm is not None,
    }


@app.post("/api/chat", response_model=ChatResponse)
def chat(request: ChatRequest) -> ChatResponse:
    if llm is None:
        raise HTTPException(status_code=503, detail="LLM is not configured.")
    if vector_index is None:
        raise HTTPException(status_code=503, detail="Knowledge base is empty.")

    context = retrieve_context(vector_index, request.message)
    messages = _build_message_list(
        system_prompt=SYSTEM_PROMPT.format(context=context),
        history=request.history,
        current_message=request.message,
    )
    answer = llm.invoke(messages)
    reply_text = answer.content if isinstance(answer.content, str) else str(answer.content)
    return ChatResponse(reply=reply_text, sources_used=4)
