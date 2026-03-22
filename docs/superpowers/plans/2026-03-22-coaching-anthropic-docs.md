# Coaching System Improvements from Anthropic Docs — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add hallucination reduction standards, new coaching triggers, HEREDOC commit detection, and Anthropic doc references to the workflow system.

**Architecture:** Professional standards additions (text), new Layer 2/3 hook triggers (bash/python), review pipeline enhancement (markdown), config fix (JSON), README references (markdown). All changes are additive — no existing behavior modified except the commit message regex.

**Tech Stack:** Bash, Python3 (inline), Markdown

**Spec:** `docs/superpowers/specs/2026-03-22-coaching-anthropic-docs-design.md`

---

### Task 1: Add professional standards from Anthropic docs

**Files:**
- Modify: `docs/reference/professional-standards.md`

- [ ] **Step 1: Add 4 new Universal Standards**

In `docs/reference/professional-standards.md`, after the last Universal Standard ("Short-term convenience vs long-term quality." at line 27), before `## DEFINE Phase Standards` (line 29), add:

```markdown

**Never speculate about unread code.** If you reference a file, function, or API, you must have read it in this session. "I believe this function returns X" without having read it is speculation, not knowledge. Read first, then claim. If you can't read it, say "I haven't read this file — let me check before answering."

**Allow "I don't know" — then research.** When uncertain about a fact, implementation detail, or behavior, say so explicitly: "I'm not sure about X — let me research." Never fabricate a plausible answer to appear helpful. Uncertainty admitted is honest; uncertainty hidden is a hallucination.

**Verify with citations — retract if unsupported.** For every factual claim from research or documentation, cite the source (URL, file path, or document reference). After making claims, find a supporting quote for each. If you cannot find a supporting quote, retract the claim and mark the retraction visibly.

**Use direct quotes for factual grounding.** When referencing documentation, error messages, test output, or code behavior, quote word-for-word rather than paraphrasing. Paraphrasing introduces drift — "the docs say it supports X" when the docs actually say "X is experimental and unsupported" is a hallucination caused by paraphrase.
```

- [ ] **Step 2: Add DEFINE/DISCUSS standard**

After the last DISCUSS Phase Standard ("Research must have sources." at line 56), before `## IMPLEMENT Phase Standards` (line 59), add:

```markdown

**Restrict to provided context in research phases.** When analyzing documents, specs, or research findings, base conclusions on the provided content — not general training knowledge. If the document doesn't contain the answer, say "this document doesn't address X" rather than filling the gap with parametric knowledge. General knowledge is a fallback, not a default.
```

- [ ] **Step 3: Add 2 new IMPLEMENT standards**

After the last IMPLEMENT Phase Standard ("Commit messages explain why, not what." at line 71), before `## REVIEW Phase Standards`, add:

```markdown

**Don't hard-code for tests.** Implement the actual logic that solves the problem generally. If a test expects output X for input Y, write code that computes X from Y — not code that returns X when it sees Y. If the task is unreasonable or tests are incorrect, say so rather than working around them.

**Commit as state checkpoints.** Commit messages are the state record for future context windows. A descriptive message ("increase login timeout from 5s to 30s to accommodate SSO redirects") is findable and useful. A generic message ("fix") is invisible noise. Every commit is a potential handover point — write it for the person who reads `git log` next month.
```

- [ ] **Step 4: Verify all standards are in correct sections**

Read the file and confirm the new standards appear under the right headings.

- [ ] **Step 5: Commit**

```bash
git add docs/reference/professional-standards.md
git commit -m "feat: add 7 professional standards from Anthropic hallucination docs

4 Universal: never speculate unread code, allow I-don't-know, verify
with citations, direct quotes for grounding. 1 DISCUSS: restrict to
provided context. 2 IMPLEMENT: don't hard-code for tests, commit as
state checkpoints. Sources: Anthropic reduce-hallucinations, prompting
best practices, long-running agents research."
```

---

### Task 2: Add HEREDOC commit message detection to Layer 3

**Files:**
- Modify: `.claude/hooks/post-tool-navigator.sh:247-257`
- Test: `tests/run-tests.sh`

- [ ] **Step 1: Write failing test for HEREDOC commit message**

Add to the `post-tool-navigator.sh` test suite in `tests/run-tests.sh`, after the existing Layer 3 commit message test:

```bash
# Test: Layer 3 Check 2 — short HEREDOC commit message warning
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_message_shown
cp "$REPO_DIR/.claude/hooks/post-tool-navigator.sh" "$TEST_DIR/.claude/hooks/"
OUTPUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"$(cat <<'"'"'EOF'"'"'\nfix\n\nCo-Authored-By: Claude\nEOF\n)\""}}' | "$TEST_DIR/.claude/hooks/post-tool-navigator.sh" 2>&1 || true)
assert_contains "$OUTPUT" "Commit messages must explain why" "Layer 3 fires for short HEREDOC commit message"

# Test: Layer 3 Check 2 — long HEREDOC commit message no warning
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_message_shown
cp "$REPO_DIR/.claude/hooks/post-tool-navigator.sh" "$TEST_DIR/.claude/hooks/"
OUTPUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"$(cat <<'"'"'EOF'"'"'\nfeat: add comprehensive hallucination reduction standards from Anthropic docs\n\nCo-Authored-By: Claude\nEOF\n)\""}}' | "$TEST_DIR/.claude/hooks/post-tool-navigator.sh" 2>&1 || true)
assert_not_contains "$OUTPUT" "Commit messages must explain why" "Layer 3 silent for long HEREDOC commit message"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `./tests/run-tests.sh`
Expected: HEREDOC tests fail (current regex doesn't match HEREDOC)

- [ ] **Step 3: Add HEREDOC branch to commit message check**

In `post-tool-navigator.sh`, replace the commit message python3 block (lines 247-257) with:

```python
import sys, re
cmd = sys.stdin.read()
# Match -m followed by a double-quoted or single-quoted string
# Use \x22 for double-quote and \x27 for single-quote to avoid shell quoting issues
m = re.search(r'-m\s+[\x22\x27](.*?)[\x22\x27]', cmd)
if m:
    print(len(m.group(1)))
else:
    # Try HEREDOC pattern: <<'EOF' ... EOF or << 'EOF' ... EOF
    m2 = re.search(r"<<\s*[\x22\x27]?EOF[\x22\x27]?\s*\\n(.*?)\\nEOF", cmd)
    if m2:
        first_line = m2.group(1).strip().split('\\n')[0]
        print(len(first_line))
    else:
        print(999)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `./tests/run-tests.sh`
Expected: all tests pass

- [ ] **Step 5: Commit**

```bash
git add .claude/hooks/post-tool-navigator.sh tests/run-tests.sh
git commit -m "feat: detect short HEREDOC commit messages in Layer 3

The project uses HEREDOC-style commits (cat <<'EOF'...) which bypassed
the -m 'short' regex. Add a second branch that extracts the first line
from HEREDOC content and checks its length."
```

---

### Task 3: Add "no verify after code change" Layer 3 check

**Files:**
- Modify: `.claude/hooks/post-tool-navigator.sh`
- Modify: `.claude/hooks/workflow-state.sh` (add pending_verify field helpers)
- Test: `tests/run-tests.sh`

- [ ] **Step 1: Write failing tests**

Add to tests after the existing Layer 3 tests:

```bash
# Test: Layer 3 — no verify after code change
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_message_shown
cp "$REPO_DIR/.claude/hooks/post-tool-navigator.sh" "$TEST_DIR/.claude/hooks/"

# Simulate 6 Write calls to source files without any test run
for i in $(seq 1 6); do
    echo '{"tool_name":"Write","tool_input":{"file_path":"src/main.py"}}' | "$TEST_DIR/.claude/hooks/post-tool-navigator.sh" > /dev/null 2>&1 || true
done
OUTPUT=$(echo '{"tool_name":"Write","tool_input":{"file_path":"src/main.py"}}' | "$TEST_DIR/.claude/hooks/post-tool-navigator.sh" 2>&1 || true)
assert_contains "$OUTPUT" "haven.t run tests" "Layer 3 fires after source edits without verify"

# Test: verify clears the flag
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_message_shown
cp "$REPO_DIR/.claude/hooks/post-tool-navigator.sh" "$TEST_DIR/.claude/hooks/"
echo '{"tool_name":"Write","tool_input":{"file_path":"src/main.py"}}' | "$TEST_DIR/.claude/hooks/post-tool-navigator.sh" > /dev/null 2>&1 || true
echo '{"tool_name":"Write","tool_input":{"file_path":"src/main.py"}}' | "$TEST_DIR/.claude/hooks/post-tool-navigator.sh" > /dev/null 2>&1 || true
# Run a test command — should clear the flag
echo '{"tool_name":"Bash","tool_input":{"command":"npm test"}}' | "$TEST_DIR/.claude/hooks/post-tool-navigator.sh" > /dev/null 2>&1 || true
# More writes — counter should restart
for i in $(seq 1 3); do
    echo '{"tool_name":"Write","tool_input":{"file_path":"src/other.py"}}' | "$TEST_DIR/.claude/hooks/post-tool-navigator.sh" > /dev/null 2>&1 || true
done
OUTPUT=$(echo '{"tool_name":"Write","tool_input":{"file_path":"src/other.py"}}' | "$TEST_DIR/.claude/hooks/post-tool-navigator.sh" 2>&1 || true)
assert_not_contains "$OUTPUT" "haven.t run tests" "verify clears the pending_verify flag"
```

- [ ] **Step 2: Run tests to verify they fail**

- [ ] **Step 3: Add pending_verify helpers to workflow-state.sh**

Add at the end of `workflow-state.sh`, before the last line:

```bash
# ---------------------------------------------------------------------------
# Pending verify tracking
# ---------------------------------------------------------------------------

set_pending_verify() {
    local count="${1:-0}"
    if [ ! -f "$STATE_FILE" ]; then return; fi
    local ts
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    python3 -c "
import json, sys
count, ts, filepath = int(sys.argv[1]), sys.argv[2], sys.argv[3]
with open(filepath, 'r') as f:
    d = json.load(f)
coaching = d.get('coaching', {})
coaching['pending_verify'] = count
d['coaching'] = coaching
d['updated'] = ts
with open(filepath, 'w') as f:
    json.dump(d, f, indent=2)
    f.write('\n')
" "$count" "$ts" "$STATE_FILE"
}

get_pending_verify() {
    if [ ! -f "$STATE_FILE" ]; then echo "0"; return; fi
    python3 -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        d = json.load(f)
    print(d.get('coaching', {}).get('pending_verify', 0))
except Exception:
    print(0)
" "$STATE_FILE" 2>/dev/null
}
```

- [ ] **Step 4: Add the check to post-tool-navigator.sh**

In the Layer 3 section, after the existing checks (after Check 6, around line 355), add:

```bash
# Check 7: No verify after code change (source edits without test run)
if [ "$PHASE" = "implement" ] || [ "$PHASE" = "review" ]; then
    if [ "$TOOL_NAME" = "Write" ] || [ "$TOOL_NAME" = "Edit" ] || [ "$TOOL_NAME" = "MultiEdit" ]; then
        # Check if editing a source file (not test, not docs, not plan/spec)
        if [ -n "$FILE_PATH" ] && ! echo "$FILE_PATH" | grep -qE '(test|spec|docs/|plans/|specs/|\.md$)'; then
            VERIFY_COUNT=$(get_pending_verify)
            VERIFY_COUNT=$((VERIFY_COUNT + 1))
            set_pending_verify "$VERIFY_COUNT"
            if [ "$VERIFY_COUNT" -ge 5 ]; then
                VERIFY_MSG="[Workflow Coach — ${PHASE^^}] You've edited source code $VERIFY_COUNT times but haven't run tests or verification. Verify your changes before continuing."
                set_pending_verify 0  # Fire once, reset
                if [ -n "$L3_MSG" ]; then
                    L3_MSG="$L3_MSG

$VERIFY_MSG"
                else
                    L3_MSG="$VERIFY_MSG"
                fi
            fi
        fi
    elif [ "$TOOL_NAME" = "Bash" ]; then
        BASH_CMD=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('command',''))" 2>/dev/null || echo "")
        if echo "$BASH_CMD" | grep -qE '(pytest|npm test|cargo test|make test|run-tests|jest|vitest|go test)'; then
            set_pending_verify 0  # Test run clears the flag
        fi
    fi
fi
```

- [ ] **Step 5: Run tests to verify they pass**

- [ ] **Step 6: Commit**

```bash
git add .claude/hooks/post-tool-navigator.sh .claude/hooks/workflow-state.sh tests/run-tests.sh
git commit -m "feat: add 'no verify after code change' Layer 3 check

Tracks source file edits without subsequent test runs. Fires once after
5 unverified edits, then resets. Test/lint Bash commands clear the flag.
Source: Anthropic verify-before-stopping pattern."
```

---

### Task 4: Add Layer 2 triggers (DEFINE write, COMPLETE test)

**Files:**
- Modify: `.claude/hooks/post-tool-navigator.sh:138-142` (DEFINE case) and add COMPLETE Bash trigger
- Test: `tests/run-tests.sh`

- [ ] **Step 1: Write failing tests**

```bash
# Test: Layer 2 — decision record write in DEFINE triggers coaching
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "define"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_message_shown
cp "$REPO_DIR/.claude/hooks/post-tool-navigator.sh" "$TEST_DIR/.claude/hooks/"
OUTPUT=$(echo '{"tool_name":"Write","tool_input":{"file_path":"docs/plans/decisions.md"}}' | "$TEST_DIR/.claude/hooks/post-tool-navigator.sh" 2>&1 || true)
assert_contains "$OUTPUT" "Challenge vague problem statements" "Layer 2 fires on decision record write in DEFINE"

# Test: Layer 2 — test run in COMPLETE triggers coaching
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "complete"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_message_shown
cp "$REPO_DIR/.claude/hooks/post-tool-navigator.sh" "$TEST_DIR/.claude/hooks/"
OUTPUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"./tests/run-tests.sh"}}' | "$TEST_DIR/.claude/hooks/post-tool-navigator.sh" 2>&1 || true)
assert_contains "$OUTPUT" "specific about validation failures" "Layer 2 fires on test run in COMPLETE"
```

- [ ] **Step 2: Run tests to verify they fail**

- [ ] **Step 3: Add DEFINE Write trigger**

In `post-tool-navigator.sh`, the Layer 2 `define)` case block currently looks like:

```bash
        define)
            if [ "$TOOL_NAME" = "Agent" ]; then
                TRIGGER="agent_return_define"
                L2_MSG="..."
            fi
            ;;
```

Change it to add the `elif` BEFORE the closing `fi` and `;;`:

```bash
        define)
            if [ "$TOOL_NAME" = "Agent" ]; then
                TRIGGER="agent_return_define"
                L2_MSG="[Workflow Coach — DEFINE] Challenge the first framing. Separate facts from interpretations. Are these findings changing the problem statement?"
            elif [ "$TOOL_NAME" = "Write" ] || [ "$TOOL_NAME" = "Edit" ] || [ "$TOOL_NAME" = "MultiEdit" ]; then
                if echo "$FILE_PATH" | grep -qE 'decisions\.md'; then
                    TRIGGER="decision_record_define"
                    L2_MSG="[Workflow Coach — DEFINE] Challenge vague problem statements. Outcomes must be verifiable, not aspirational. 'Better UX' is aspirational; 'checkout completes in under 3 clicks' is verifiable."
                fi
            fi
            ;;
```

- [ ] **Step 4: Add COMPLETE Bash trigger**

In the Layer 2 case block for `complete)`, after the existing Write/Edit trigger, add:

```bash
            elif [ "$TOOL_NAME" = "Bash" ]; then
                BASH_CMD=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('command',''))" 2>/dev/null || echo "")
                if echo "$BASH_CMD" | grep -qE '(pytest|npm test|cargo test|make test|run-tests|jest|vitest)'; then
                    TRIGGER="test_run_complete"
                    L2_MSG="[Workflow Coach — COMPLETE] Be specific about validation failures. If a test fails, diagnose with quantified fix effort. Don't let failures be acknowledged without understanding consequences."
                fi
```

- [ ] **Step 5: Run tests to verify they pass**

- [ ] **Step 6: Commit**

```bash
git add .claude/hooks/post-tool-navigator.sh tests/run-tests.sh
git commit -m "feat: add Layer 2 triggers for DEFINE write and COMPLETE test

DEFINE: coaching on vague problem statements when writing decision record.
COMPLETE: coaching on validation specificity when running tests.
Source: professional standards gap analysis."
```

---

### Task 5: Inject plan path into review pipeline Agent 3

**Files:**
- Modify: `.claude/commands/review.md:71-72`

- [ ] **Step 1: Update Agent 3 prompt in review.md**

In `.claude/commands/review.md`, replace the Agent 3 prompt (line 72) with:

```
**Agent 3 — Architecture & Plan Compliance Reviewer** (subagent_type: "code-review")

Before dispatching Agent 3, find the plan file path: check `docs/superpowers/plans/` and `docs/plans/` for the most recent `.md` file. If found, include it in the prompt.

Prompt: "Review these changed files for architectural issues and plan compliance. Changed files: [LIST]. Plan file: [PLAN_PATH or 'no plan file found']. If a plan file is provided, read it and verify each task was implemented correctly. Check for: does implementation match the plan/spec, are existing patterns followed, are component boundaries respected, new undocumented dependencies, regressions. For each finding report: Severity (CRITICAL/WARNING/SUGGESTION), File and line range, Description, Recommended fix. If no issues: 'No architectural issues found.' Keep output concise — findings only, limit to 2000 tokens."
```

- [ ] **Step 2: Verify the change reads correctly**

Read the file and confirm Agent 3's prompt now includes plan path injection.

- [ ] **Step 3: Commit**

```bash
git add .claude/commands/review.md
git commit -m "feat: inject plan file path into review Agent 3 prompt

Architecture agent now receives the actual plan path instead of having
to guess. Enables precise plan-vs-implementation compliance checking."
```

---

### Task 6: Add WebFetch/WebSearch permissions and README references

**Files:**
- Modify: `.claude/settings.json`
- Modify: `README.md`

- [ ] **Step 1: Add permissions to settings.json**

In `.claude/settings.json`, add a `permissions` block before the `hooks` block:

```json
  "permissions": {
    "allow": [
      "WebFetch",
      "WebSearch"
    ]
  },
```

Ensure the existing `hooks` block is preserved — merge, don't replace.

- [ ] **Step 2: Add "Informed By" section to README**

In `README.md`, before `## Contributing` (line 68), add:

```markdown
## Informed By

- [Reduce Hallucinations](https://docs.anthropic.com/en/docs/test-and-evaluate/strengthen-guardrails/reduce-hallucinations) — grounding, citations, uncertainty
- [Claude Code Best Practices](https://code.claude.com/docs/en/best-practices) — agentic coding patterns
- [Building Effective Agents](https://www.anthropic.com/research/building-effective-agents) — tool design, evaluation loops
- [Effective Harnesses for Long-Running Agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents) — session state, progress checkpoints

```

- [ ] **Step 3: Commit**

```bash
git add .claude/settings.json README.md
git commit -m "feat: allow WebFetch/WebSearch for subagents, add Anthropic doc references

Permissions prevent subagent permission prompt blocking. README now
links to the Anthropic documentation that informs the workflow design."
```

---

### Task 7: Run full test suite and verify

- [ ] **Step 1: Run the full test suite**

Run: `./tests/run-tests.sh`
Expected: all tests PASS

- [ ] **Step 2: Verify professional standards read correctly**

Read `docs/reference/professional-standards.md` and confirm all 7 new standards are present and in the correct sections.

- [ ] **Step 3: Final commit if any fixups needed**
