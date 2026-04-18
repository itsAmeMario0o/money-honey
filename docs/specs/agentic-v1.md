---
layout: default
title: Agentic chatbot spec (v1)
---

# 🤖 Agentic chatbot spec (v1): memory + tools

Spec for evolving Money Honey from a one-shot RAG chatbot into a tool-using conversational agent. Covers Tier 1 (multi-turn memory) and Tier 2 (financial tools). Tier 3 (autonomous planning agent) is deferred to v2 and parked in `docs/roadmap.md`.

## 1. Context

Money Honey today is stateless. Each `/api/chat` request sends one message, retrieves 4 RAG chunks, calls Claude once, and forgets everything. You can't say "what did I just tell you about my car payment?" because there is no conversation history.

Adding memory and tools makes the chatbot genuinely useful for financial education. It also deepens the security story: every new tool is a new process for Tetragon to watch, a new egress path for Cilium to gate, and a new artifact for AIBOM to inventory.

## 2. Functional requirements

### Tier 1: conversational memory

FR-1. The `/api/chat` endpoint MUST accept an optional `history` field: a list of `{role, content}` message pairs representing prior turns in the conversation.

FR-2. The backend MUST pass the full history (system prompt + history + current message) to Claude on every turn. Claude's context window is the memory boundary.

FR-3. The frontend MUST maintain the conversation history in component state and send it with every request.

FR-4. History MUST be session-scoped. Closing the browser tab clears it. No server-side persistence in v1.

FR-5. The backend MUST enforce a maximum history length. If the history exceeds the limit, the oldest turns (excluding the system prompt) are dropped. Suggested limit: 20 turns (10 user + 10 assistant messages).

FR-6. RAG retrieval MUST use the current user message only, not the full history. This keeps retrieval focused on the immediate question and avoids context dilution.

### Tier 2: financial tools

FR-7. The backend MUST register tools with Claude via the Anthropic tool_use API. Each tool is a Python function callable by Claude during a conversation turn.

FR-8. The initial tool set MUST include:

| Tool name | Input | Output | Side effects |
|---|---|---|---|
| `compound_interest` | principal, monthly_contribution, annual_rate, years | future_value, total_contributed, total_interest | None |
| `debt_payoff` | list of {name, balance, rate, min_payment}, extra_monthly_budget | ordered payoff plan (avalanche + snowball variants), months_to_payoff, total_interest_paid | None |
| `budget_breakdown` | list of {category, amount} | categorized totals, percentage breakdown, verdict (overspending / on track / room to save) | None |
| `tax_bracket` | filing_status, taxable_income | marginal_rate, effective_rate, tax_owed, breakdown_by_bracket | None |

FR-9. All tools MUST be pure functions with no side effects, no network calls, and no file I/O. They receive inputs, compute, and return results. This is the v1 contract.

FR-10. Tool implementations MUST live under `app/tools/` as individual Python modules, one per tool. Each module exports a single function with full type hints and a docstring that doubles as the tool's description for Claude.

FR-11. The backend MUST handle Claude's tool_use response by executing the requested tool, passing the result back, and letting Claude formulate the final answer in Money Honey's voice.

FR-12. If a tool raises an exception, the backend MUST catch it and return a user-friendly error message through Claude, not a raw traceback.

FR-13. Money Honey's personality MUST be preserved in tool-augmented responses. Claude uses the tool output as data but speaks in character. "Babe, I ran the numbers..." not "The compound interest calculation shows..."

## 3. Non-functional requirements

NFR-1. Adding history MUST NOT increase p95 latency by more than 500ms over the current baseline (target: p95 < 5s per chatbot-v1 spec).

NFR-2. Tool execution MUST complete in under 100ms. All tools are CPU-bound arithmetic; no I/O.

NFR-3. The history payload size MUST NOT exceed 100 KB per request. The backend MUST reject oversized payloads with 413.

NFR-4. Memory usage per tool invocation MUST stay under 10 MB. No tool loads large datasets.

## 4. Acceptance criteria

### Tier 1

AC-1. Given a user asks "I have $40k in student loans at 6.5%", then asks "what did I just tell you about my loans?", Money Honey repeats the loan details from the prior turn.

AC-2. Given a conversation with 25 turns, the backend drops the 5 oldest turns and sends 20 to Claude. No error, no crash.

AC-3. Given the user closes and reopens the browser tab, the conversation history is empty.

### Tier 2

AC-4. Given the user asks "if I invest $500 a month at 7% for 30 years, what do I get?", Money Honey calls `compound_interest` and answers with the result in character.

AC-5. Given the user provides 3 debts and asks "what's the fastest way to pay these off?", Money Honey calls `debt_payoff` and presents both avalanche and snowball strategies.

AC-6. Given the user asks "break down my monthly spending" and provides a list of categories + amounts, Money Honey calls `budget_breakdown` and gives a verdict.

AC-7. Given a tool raises a ValueError (bad input), Money Honey responds gracefully in character ("Honey, those numbers don't add up. Try again."), not with a traceback.

AC-8. Given a conversation that uses tools, the full tool call chain (tool name, inputs, outputs) is visible in Splunk via Tetragon process-exec audit logs.

## 5. Edge cases

EC-1. User sends history with mismatched roles (two user messages in a row). Backend MUST accept it; Claude handles interleaved roles gracefully.

EC-2. User sends a message that triggers multiple tool calls in one turn. Backend MUST handle sequential tool_use responses (Claude calls tool A, gets result, calls tool B, gets result, then answers).

EC-3. User asks a financial question that could use a tool but the tool isn't needed (simple enough to answer from RAG). Claude SHOULD prefer RAG when the tool adds no value. This is Claude's judgment; no hard rule.

EC-4. History contains a prompt-injection attempt in a prior turn. The system prompt and tool schemas are the defense; Tetragon logs the full chain for post-incident review.

## 6. API contract

### Updated `/api/chat` request

```json
{
  "message": "if I invest $500/mo at 7% for 30 years, what do I get?",
  "history": [
    {"role": "user", "content": "I have $40k in student loans at 6.5%"},
    {"role": "assistant", "content": "Okay babe, $40k at 6.5%..."}
  ]
}
```

`history` is optional. Omitting it or sending `[]` preserves backward compatibility with the existing one-shot behavior.

### Updated `/api/chat` response

```json
{
  "reply": "Honey, I ran the numbers. If you invest $500 every month at 7% for 30 years, you end up with $566,764. You only put in $180,000 of your own money. The rest is compound interest doing its thing.",
  "sources_used": 4,
  "tools_used": ["compound_interest"]
}
```

`tools_used` is a list of tool names Claude called during this turn. Empty list if no tools were used.

## 7. Data model

### Tool schema (registered with Claude)

```python
{
    "name": "compound_interest",
    "description": "Calculate the future value of recurring monthly investments with compound interest.",
    "input_schema": {
        "type": "object",
        "properties": {
            "principal": {"type": "number", "description": "Starting balance in dollars"},
            "monthly_contribution": {"type": "number", "description": "Amount added each month in dollars"},
            "annual_rate": {"type": "number", "description": "Annual interest rate as a decimal (0.07 = 7%)"},
            "years": {"type": "integer", "description": "Number of years to invest"}
        },
        "required": ["monthly_contribution", "annual_rate", "years"]
    }
}
```

### Conversation history (frontend state, not persisted)

```typescript
interface ChatMessage {
  role: "user" | "assistant";
  content: string;
}

// Component state
const [history, setHistory] = useState<ChatMessage[]>([]);
```

## 8. Security implications

| Concern | Layer that addresses it |
|---|---|
| Tool abuse (tricked into leaking data) | FR-9: all tools are pure functions, no I/O, no side effects. Nothing to leak. |
| Prompt injection across turns | Tetragon logs the full conversation chain. Post-incident review in Splunk. System prompt is the primary defense. |
| Tool input validation | Each tool validates its own inputs (type hints + Pydantic models). Bad input raises ValueError, caught by FR-12. |
| New AI components in the supply chain | AIBOM inventories the tool schemas as AI artifacts on every PR. |
| Code quality of tool implementations | CodeGuard rules apply during generation. `senior-backend` + `tdd-guide` skills per CLAUDE.md. |
| Tool execution visibility | Tetragon process-exec-audit sees every Python function call. OTel metrics track tool invocation counts. |

## 9. Out of scope (v1)

- Persistent memory across sessions (Tier 3 / v2).
- Tools with side effects (sending emails, making payments, calling external APIs).
- Multi-agent architecture (planner + specialist agents).
- User authentication or profiles.
- Streaming responses (SSE / WebSocket). Response is still a single JSON payload.
- Tool result caching. Each invocation recomputes.

## 10. Implementation order

1. `app/tools/` module structure + 4 tool implementations + pytest for each
2. Update `app/main.py` to accept `history`, enforce limits, register tools with Claude
3. Update `frontend/src/` to maintain history state and send it with each request
4. Update `app/tests/test_health.py` with tool-augmented happy-path and error tests
5. Update AIBOM scan config if tool schemas need explicit tracking
6. Update `docs/chatbot/rag-pipeline.md` to document the tool-use flow
7. Update `ARCHITECTURE.md` Layer 2 section to note tool-execution visibility
