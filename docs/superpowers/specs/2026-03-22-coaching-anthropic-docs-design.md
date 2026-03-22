# Design: Coaching System Improvements from Anthropic Documentation

**Date:** 2026-03-22
**Status:** Draft

## Problem

The coaching system monitors tool usage patterns but lacks several behavioral standards that Anthropic's own documentation recommends for reducing hallucinations, improving code quality, and enforcing verification discipline. The review pipeline also has gaps (no plan path passed to Agent 3, no test coaching in COMPLETE). Additionally, subagents get blocked on WebFetch/WebSearch permission prompts, and the README lacks references to the Anthropic documentation that informs the workflow design.

## Sources

All techniques below are sourced from Anthropic's published documentation:

- [Reduce Hallucinations](https://docs.anthropic.com/en/docs/test-and-evaluate/strengthen-guardrails/reduce-hallucinations) — 7 techniques for minimizing fabrication
- [Avoiding Hallucinations Course](https://github.com/anthropics/courses/blob/master/prompt_engineering_interactive_tutorial/Anthropic%201P/08_Avoiding_Hallucinations.ipynb) — interactive notebook with examples
- [Claude Code Best Practices](https://code.claude.com/docs/en/best-practices) — patterns for agentic coding
- [Prompting Best Practices](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices) — system prompt recommendations
- [Building Effective Agents](https://www.anthropic.com/research/building-effective-agents) — agent architecture patterns
- [Effective Harnesses for Long-Running Agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents) — session management and state

## Changes

### Tier 1: New Layer 3 Anti-Laziness Checks

Layer 3 checks fire on every match. These are new checks in `post-tool-navigator.sh`.

#### Check: No verify after code change

**Detection:** Write/Edit/MultiEdit to a source file (not test, not docs, not plan/spec), then no Bash containing test/lint/check/run within the next N tool calls. Track via a `pending_verify` flag in coaching state: set on source edit, clear on test Bash. Fire once when the flag has been set for 5+ non-test tool calls, then clear the flag (fires only once per unverified edit batch, not repeatedly).

**Message:** `[Workflow Coach — {PHASE}] You edited source code but haven't run tests or verification. Anthropic's guidance: always verify after changes — a plausible implementation that doesn't handle edge cases is a named failure mode.`

**Source:** Anthropic "verify before stopping" pattern.

#### Check: Investigate before claiming

**Detection:** Write/Edit to a source file where the file_path was not previously Read in the current phase. Track via a set of read file paths in coaching state. If a Write/Edit targets a path not in the set, fire.

**Complexity note:** This requires tracking read paths across tool calls in the coaching state. The state file already has a coaching object — add a `files_read` array. The early-exit block for Read would need to record the file path before exiting. This adds disk I/O to Read calls, which are frequent. **Alternative:** Only check for Write/Edit to files not in the plan's file list — simpler but less coverage. **Recommendation:** Skip this check for now. The professional standard "Never speculate about unread code" covers the intent without hook overhead. Revisit if hallucination on unread files becomes a recurring problem.

#### Check: HEREDOC commit message detection

**Detection:** Current regex `r'-m\s+[\x22\x27](.*?)[\x22\x27]'` misses HEREDOC-style commits (`git commit -m "$(cat <<'EOF'...)`). Add a second branch: extract the message from between `EOF` markers.

**Implementation:** In the commit message check (Layer 3 Check 2), after the existing regex match, add a HEREDOC extraction branch:

```python
if not m:
    # Try HEREDOC pattern: <<'EOF' ... EOF or << 'EOF' ... EOF
    m2 = re.search(r"<<\s*['\"]?EOF['\"]?\s*\n(.*?)\nEOF", cmd, re.DOTALL)
    if m2:
        # First line of HEREDOC is the commit message
        first_line = m2.group(1).strip().split('\n')[0]
        print(len(first_line))
    else:
        print(999)
```

### Tier 2: New Layer 2 Professional Standards Triggers

Layer 2 triggers fire once per trigger type per phase. These are new triggers in `post-tool-navigator.sh`.

#### Trigger: Decision record write in DEFINE phase

**Detection:** Write/Edit/MultiEdit in DEFINE phase where FILE_PATH matches `decisions.md` or a decision record path. This fires on any write to the decision record during DEFINE — the message coaches on problem definition quality since that's what DEFINE writes to the record.

**Message:** `[Workflow Coach — DEFINE] Challenge vague problem statements. Outcomes must be verifiable, not aspirational. "Better UX" is aspirational; "checkout completes in under 3 clicks" is verifiable.`

**Trigger name:** `decision_record_define`

#### Trigger: Test run in COMPLETE phase

**Detection:** Bash tool in COMPLETE phase where command matches test patterns (pytest, npm test, cargo test, make test, run-tests, jest, vitest).

**Message:** `[Workflow Coach — COMPLETE] Be specific about validation failures. If a test fails, diagnose with quantified fix effort. Don't let failures be acknowledged without understanding consequences.`

**Trigger name:** `test_run_complete`

#### Trigger: Plan path injection in review pipeline

**Detection:** Not a hook change — this is a change to `.claude/commands/review.md`. Agent 3 (Architecture & Plan Compliance) prompt should include the actual plan file path from workflow state or by scanning `docs/superpowers/plans/` and `docs/plans/`.

**Change in review.md:** Before dispatching Agent 3, read the plan path:
```
Read the most recent plan file from docs/superpowers/plans/ or docs/plans/. Pass its path to Agent 3.
```

Update Agent 3's prompt to include: `"Plan file: [PATH]. Read it and verify implementation matches each task."`

### Tier 3: Professional Standards Additions

These go into `docs/reference/professional-standards.md`. No hook changes needed — standards are loaded at phase entry via Layer 1 messages and referenced by Layer 2 triggers.

#### Universal Standards (additions)

**Never speculate about unread code.** If you reference a file, function, or API, you must have read it in this session. "I believe this function returns X" without having read it is speculation, not knowledge. Read first, then claim. If you can't read it, say "I haven't read this file — let me check before answering."

Source: Anthropic prompting best practices — `investigate_before_answering` pattern.

**Allow "I don't know" — then research.** When uncertain about a fact, implementation detail, or behavior, say so explicitly: "I'm not sure about X — let me research." Never fabricate a plausible answer to appear helpful. Uncertainty admitted is honest; uncertainty hidden is a hallucination.

Source: Anthropic technique #1, "Allow Claude to say I don't know."

**Verify with citations — retract if unsupported.** For every factual claim from research or documentation, cite the source (URL, file path, or document reference). After making claims, find a supporting quote for each. If you cannot find a supporting quote, retract the claim. Mark retractions visibly.

Source: Anthropic technique #3, "Verify with citations."

**Use direct quotes for factual grounding.** When referencing documentation, error messages, test output, or code behavior, quote word-for-word rather than paraphrasing. Paraphrasing introduces drift — "the docs say it supports X" when the docs actually say "X is experimental and unsupported" is a hallucination caused by paraphrase.

Source: Anthropic technique #2, "Use direct quotes for factual grounding."

#### DEFINE/DISCUSS Standards (addition)

**Restrict to provided context in research phases.** When analyzing documents, specs, or research findings, base conclusions on the provided content — not general training knowledge. If the document doesn't contain the answer, say "this document doesn't address X" rather than filling the gap with parametric knowledge. General knowledge is a fallback, not a default.

Source: Anthropic technique #7, "External knowledge restriction."

#### IMPLEMENT Standards (additions)

**Don't hard-code for tests.** Implement the actual logic that solves the problem generally. If a test expects output X for input Y, write code that computes X from Y — not code that returns X when it sees Y. If a test seems wrong, say so rather than working around it.

Source: Anthropic prompting best practices, anti-hard-coding pattern.

**Commit as state checkpoints.** Commit messages are the state record for future context windows. A descriptive message ("increase login timeout from 5s to 30s to accommodate SSO redirects") is findable and useful. A generic message ("fix") is invisible noise. Every commit is a potential handover point — write it for the person who reads `git log` next month.

Source: Anthropic long-running agents research, state handoff protocol.

### Tier 4: Config and Documentation

#### WebFetch/WebSearch permissions

Add to `.claude/settings.json`:
```json
"permissions": {
    "allow": [
        "WebFetch",
        "WebSearch"
    ]
}
```

This prevents subagents from blocking on permission prompts during research.

#### README references section

Add an "Informed By" section to README.md linking to the Anthropic documentation sources that inform the workflow design:

```markdown
## Informed By

- [Reduce Hallucinations](https://docs.anthropic.com/en/docs/test-and-evaluate/strengthen-guardrails/reduce-hallucinations) — grounding, citations, uncertainty
- [Claude Code Best Practices](https://code.claude.com/docs/en/best-practices) — agentic coding patterns
- [Building Effective Agents](https://www.anthropic.com/research/building-effective-agents) — tool design, evaluation loops
- [Effective Harnesses for Long-Running Agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents) — session state, progress checkpoints
```

## Trade-offs

- **"No verify after code change" check adds state tracking** — a `pending_verify` flag in the coaching state, cleared on test runs. One extra JSON read/write per source edit.
- **HEREDOC commit message regex is more complex** — two branches instead of one. Still a single python3 invocation.
- **"Investigate before claiming" deferred** — tracking read paths across all tool calls would add disk I/O to every Read. The professional standard covers the intent without hook overhead.
- **7 new professional standards increase text volume** — but they are loaded once at phase entry, not repeated. Standards that are rarely violated become invisible; standards that catch real issues pay for themselves.
- **Best-of-N and iterative refinement techniques not adopted** — require multiple API calls per operation, incompatible with hook-based coaching.
