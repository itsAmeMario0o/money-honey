# 📝 Spec: Money Honey Chatbot v1

## 1. Title and Metadata

| Field | Value |
|---|---|
| **Feature** | Money Honey chatbot v1 (application layer) |
| **Author** | Mario Ruiz + Claude Code |
| **Status** | ⚠️ Retroactive — code existed before spec. Treat as v1 baseline going forward. |
| **Reviewers** | Mario Ruiz |
| **Skill used** | `engineering-advanced-skills/spec-driven-workflow` |
| **Related files** | `app/main.py`, `app/rag.py`, `app/personality.py`, `frontend/src/**` |

> ⚠️ **Note on anti-pattern:** `spec-driven-workflow` flags "spec as post-hoc documentation" as anti-pattern #4. This document captures the v1 baseline so future iterations (v1.1+) can follow the workflow correctly. All changes after this spec is approved MUST follow phases 1–6 of the skill.

---

## 2. Context

Money Honey is a financial-education chatbot. The chatbot is the demo vehicle; the real deliverable is the 7-layer security architecture around it (see [`CLAUDE.md`](../../CLAUDE.md)).

**Users:** anyone curious about personal finance. No auth, no accounts, no PII collection in v1. The chatbot is a public demo.

**Evidence / motivation:**
- CLAUDE.md lines 7–16 establish the project's purpose: a RAG chatbot as the vehicle for a defense-in-depth demo.
- CLAUDE.md lines 19–43 establish the chatbot's personality ("Money Honey") and tone.
- Cost target from CLAUDE.md lines 346–360: ~$3–5/month on Claude API with $20 prepaid.

**Success looks like:** a user visits `money-honey.mariojruiz.com`, asks a personal-finance question, and gets a grounded answer in Money Honey's voice within a few seconds. Every request is observable in Splunk.

---

## 3. Functional Requirements (RFC 2119)

| ID | Requirement |
|---|---|
| **FR-1** | The system MUST expose `GET /api/health` that returns a 200 JSON body with `status`, `index_ready`, `llm_ready` booleans. |
| **FR-2** | The system MUST expose `POST /api/chat` that accepts `{ "message": string }` and returns `{ "reply": string, "sources_used": integer }`. |
| **FR-3** | The backend MUST load every PDF in `app/knowledge_base/pdfs/` on startup, chunk them, embed them with the local `sentence-transformers/all-MiniLM-L6-v2` model (no external API calls), and store the embeddings in an in-memory FAISS index. |
| **FR-4** | For every chat request, the backend MUST retrieve the top-4 most similar chunks from FAISS and include them as context in the LLM prompt. |
| **FR-5** | The backend MUST send requests to the Claude API using the model `claude-haiku-4-5-20251001`. |
| **FR-6** | The LLM system prompt MUST be the Money Honey personality defined in `app/personality.py`. |
| **FR-7** | The backend MUST read `ANTHROPIC_API_KEY` and `ALLOWED_ORIGINS` from environment variables. It MUST NOT read secrets from code, config files, or command-line flags. |
| **FR-8** | The frontend MUST render a chat UI with an input field, a send button, and a scrolling history of user / Money Honey messages. |
| **FR-9** | The frontend MUST POST user messages to `/api/chat` and render the returned `reply` field as Money Honey's response. |
| **FR-10** | The frontend MUST surface API errors to the user without leaking stack traces or server internals. |
| **FR-11** | The backend MUST reject chat messages longer than 2000 characters with HTTP 422. |
| **FR-12** | The backend SHOULD return HTTP 503 with a clear message when the LLM or the knowledge-base index is not ready. |

---

## 4. Non-Functional Requirements

| ID | Requirement | Measurable threshold |
|---|---|---|
| **NFR-1** (performance) | `/api/chat` p95 end-to-end latency SHOULD be under 5 seconds for a 3-PDF corpus. | p95 < 5000 ms |
| **NFR-2** (cost) | Total Claude API spend SHOULD stay under $5/month at demo traffic (< 500 messages/month). Embeddings are local and free. | < $5/month |
| **NFR-3** (security) | No secrets MUST appear in code, logs, container images, or git history. | 0 findings in `gitleaks` + image scan |
| **NFR-4** (security) | Frontend–backend traffic MUST be HTTPS in production (Caddy handles TLS). | 100% HTTPS |
| **NFR-5** (container) | Both container images MUST run as a non-root user. | `USER` != `root` |
| **NFR-6** (availability) | The app SHOULD start successfully even when PDFs or API keys are missing, returning 503 on `/api/chat` instead of crashing. | 0 crashes on cold start |
| **NFR-7** (observability) | Every chat request SHOULD be observable in Splunk within 60 seconds (deferred to k8s step — not blocking v1 local dev). | < 60 s log lag |
| **NFR-8** (a11y) | The chat UI SHOULD meet WCAG 2.2 Level AA. | axe-core 0 critical issues |

---

## 5. Acceptance Criteria (Given / When / Then)

| ID | Criterion | Refs |
|---|---|---|
| **AC-1** | **Given** the backend is running with valid API keys and at least one PDF, **When** a client calls `GET /api/health`, **Then** the response is 200 with `{ "status": "ok", "index_ready": true, "llm_ready": true }`. | FR-1 |
| **AC-2** | **Given** the backend has no PDFs, **When** a client calls `GET /api/health`, **Then** the response is 200 with `index_ready: false`. | FR-1, FR-3 |
| **AC-3** | **Given** a ready backend, **When** a client POSTs `{ "message": "Should I invest in crypto?" }` to `/api/chat`, **Then** the response is 200 with a non-empty `reply` string and `sources_used: 4`. | FR-2, FR-4, FR-5 |
| **AC-4** | **Given** a ready backend, **When** the LLM returns a response, **Then** the response tone matches the personality system prompt (uses "babe"/"honey"/"sweetheart" naturally, stays in personal finance). | FR-6 |
| **AC-5** | **Given** the FAISS index contains 3 CFP PDFs, **When** a user asks about emergency funds, **Then** the retrieved context includes at least one chunk from the CFP PDFs. | FR-3, FR-4 |
| **AC-6** | **Given** the frontend is running, **When** a user types a message and clicks Send, **Then** the message appears in the history, a request is made to `/api/chat`, and the reply is rendered. | FR-8, FR-9 |
| **AC-7** | **Given** the backend returns a 503, **When** the frontend receives that error, **Then** the UI shows a friendly error message (not a stack trace). | FR-10, FR-12 |
| **AC-8** | **Given** a message of 2001 characters, **When** it is POSTed to `/api/chat`, **Then** the response is 422 with a validation-error body. | FR-11 |
| **AC-9** | **Given** `ANTHROPIC_API_KEY` is unset, **When** the backend starts, **Then** the process does not crash and `/api/health` returns `llm_ready: false`. | FR-7, NFR-6 |
| **AC-10** | **Given** the backend container runs in Kubernetes, **When** inspected with `id`, **Then** the user is not root. | NFR-5 |

---

## 6. Edge Cases

| ID | Scenario | Expected behavior |
|---|---|---|
| **EC-1** | No PDFs in `knowledge_base/pdfs/` | `build_index` returns `None`. App starts. `/api/chat` returns 503. `/api/health` returns `index_ready: false`. |
| **EC-2** | Claude API is unreachable | Request raises; backend responds with 502 (future hardening: currently propagates as 500). |
| **EC-3** | Claude API returns a rate-limit error | Same as EC-2 for v1. Retry logic is a v1.1 concern. |
| **EC-4** | Embedding model fails to load (disk full, corrupt cache) | App logs the error and exits non-zero (fail-fast; K8s restarts). |
| **EC-5** | User submits empty string | Pydantic rejects with 422 (FR-11 uses `min_length=1`). |
| **EC-6** | User submits message > 2000 chars | 422 with validation error (FR-11). |
| **EC-7** | PDF fails to parse (corrupt file) | `PyPDFLoader` raises; app fails to start. Operator replaces the PDF. Fail loud, not silent. |
| **EC-8** | FAISS similarity search returns fewer than 4 chunks (tiny corpus) | Return whatever it has; `sources_used` stays 4 in the response (known limitation — future improvement). |
| **EC-9** | CORS: request from an origin not in `ALLOWED_ORIGINS` | Browser blocks the response; server returns the request normally (CORS is browser-enforced). |
| **EC-10** | User asks an off-topic question (e.g., "write me a poem") | Money Honey redirects back to personal finance per system prompt. |

---

## 7. API Contracts

```typescript
// POST /api/chat — request body
interface ChatRequest {
  message: string;  // length 1..2000
}

// POST /api/chat — 200 response
interface ChatResponse {
  reply: string;
  sources_used: number;  // fixed at 4 in v1
}

// GET /api/health — 200 response
interface HealthResponse {
  status: "ok";
  index_ready: boolean;
  llm_ready: boolean;
}

// Error envelope (any 4xx / 5xx from FastAPI)
interface ErrorResponse {
  detail: string | ValidationErrorItem[];
}

interface ValidationErrorItem {
  loc: (string | number)[];
  msg: string;
  type: string;
}
```

**Status codes in use:**

| Code | When |
|---|---|
| 200 | Success on both endpoints |
| 422 | Validation failure (message empty or > 2000 chars) |
| 503 | LLM or index not ready |
| 500 | Unexpected server error |

---

## 8. Data Models

### In-memory

| Entity | Fields | Source |
|---|---|---|
| `Document` (LangChain) | `page_content: str`, `metadata: dict` (filename, page) | `PyPDFLoader` |
| `FAISS index` | embedding vectors (384-dim `all-MiniLM-L6-v2`) + doc store | built on startup |
| `ChatRequest` | `message: str` (pydantic `Field(min_length=1, max_length=2000)`) | client |
| `ChatResponse` | `reply: str`, `sources_used: int` | server |

### Persisted

**None in v1.** Everything is in-memory. No database. PDFs on disk only. This is deliberate — simpler surface area for the security demo.

### Secrets (not in code or git)

| Name | Location in prod | Location in dev |
|---|---|---|
| `ANTHROPIC_API_KEY` | Azure Key Vault → CSI volume | `app/.env` (gitignored) |
| `ALLOWED_ORIGINS` | ConfigMap | `app/.env` |

---

## 9. Out of Scope (v1)

| ID | Excluded feature | Why |
|---|---|---|
| **OS-1** | User authentication / accounts | Public demo; no PII. |
| **OS-2** | Conversation memory across turns | Each chat is independent. Memory is a v2 feature. |
| **OS-3** | Streaming responses (SSE / WebSocket) | Simpler surface area for security demo. |
| **OS-4** | Rate limiting at the app layer | Deferred to backend hardening PR (senior-backend skill will drive). |
| **OS-5** | Retrieval evaluation / benchmarking | Corpus is tiny (3–4 PDFs). Eval harness is v2. |
| **OS-6** | Hybrid search (BM25 + vector) | Pure vector is enough for this corpus. v2 if accuracy drops. |
| **OS-7** | Citation rendering (showing the user which PDF sourced the answer) | Metadata is preserved; UI treatment is v1.1. |
| **OS-8** | Multi-language support | English only in v1. |
| **OS-9** | Persisted FAISS index on disk | Rebuilt on every cold start in v1. |
| **OS-10** | Cost tracking / usage limits per session | v2; for now we rely on the $20 Anthropic prepaid cap. |

---

## 10. Self-Review Checklist (per spec-driven-workflow)

- [x] Every FR has at least one AC
- [x] Every AC references at least one FR or NFR
- [x] API contracts cover all endpoints
- [x] Data models cover all entities mentioned
- [x] Edge cases cover every external dependency (PDFs, Anthropic, OpenAI, user input)
- [x] Out of Scope is explicit
- [x] NFRs have measurable thresholds
- [x] RFC 2119 keywords used (MUST / SHOULD / MAY)

---

## 11. Known gaps vs. current code (from skill review)

These are tracked as follow-up work, not v1 regressions:

- **Backend hardening** (`senior-backend`): rate limiting, structured error format, request IDs, LLM timeout, structured logging. Planned as a separate PR.
- **Docker polish** (`docker-development`): HEALTHCHECK, `npm ci` + lockfile, BuildKit cache. Planned as a separate PR.
- **Frontend a11y + UX** (`senior-frontend`): aria-labels, auto-scroll, error boundary. Planned as a separate PR.
- **RAG metadata + citations** (`rag-architect`): preserve page/source metadata through retrieval. Planned as v1.1.
- **Tests**: zero tests exist today. Test plan to be authored per `tdd-guide` before backend-hardening PR.
