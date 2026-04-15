<!-- Keep it short. The diff speaks for itself; this template is for context the diff can't show. -->

## What this changes

<!-- 1–2 sentences. What problem does this solve, what user-visible behavior changes? -->

## Skill(s) applied

<!-- From CLAUDE.md §Claude Code Skills. Example: senior-backend + api-test-suite-builder. -->

## Linked spec / issue

<!-- docs/specs/<feature>-v1.md or an issue number. Delete if not applicable. -->

## Test plan

<!-- How you verified this. Keep it concrete. Paste command output if useful. -->

- [ ] `pre-commit run --all-files` passes locally
- [ ] `pytest` green (or N/A for non-Python change)
- [ ] `vitest` green (or N/A for non-frontend change)
- [ ] Relevant spec / README / ARCHITECTURE.md updated if behavior changed
- [ ] No new secrets committed; `.gitleaksignore` / `.trivyignore.yaml` entries justified + time-bounded

## Security impact

<!-- If this touches any of the 8 layers, say which and how. "None" is a valid answer. -->

---

🤖 Generated with [Claude Code](https://claude.com/claude-code)
