# Intent File Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the BUG-3 phase token system with a simpler intent file approach, and move version bump from COMPLETE to IMPLEMENT phase.

**Architecture:** UserPromptSubmit hook writes a single-line intent file (`phase-intent.json` or `autonomy-intent.json`) using `printf`. `set_phase()` reads, validates, and deletes the intent file. bash-write-guard protects intent and state files with path-qualified string matching.

**Tech Stack:** Bash, jq (for workflow-state.sh only — not in the hook), shell builtins

**Spec:** [docs/superpowers/specs/2026-03-25-intent-file-redesign.md](../specs/2026-03-25-intent-file-redesign.md)

---

### Task 1: Create intent file hook (`user-phase-gate.sh`)

**Files:**
- Create: `plugin/scripts/user-phase-gate.sh`

- [ ] **Step 1: Write the hook script**

```bash
#!/bin/bash
# Copyright (C) 2026 azevedo-home-lab
# SPDX-License-Identifier: GPL-3.0-only
#
# UserPromptSubmit hook: writes intent files for phase and autonomy commands.
# Intent files are consumed by set_phase() and set_autonomy_level() in workflow-state.sh.
# Claude cannot trigger this hook — it only fires on actual user input.
#
# Security model: Only explicit slash commands generate intent files.
# No bare set_phase/set_autonomy_level matching — prevents false positives.
# Uses printf (shell builtin) — no jq, no openssl, no PATH dependencies.

set -euo pipefail

# Read stdin JSON — extract prompt using shell builtins + grep/sed
INPUT=$(cat)
PROMPT=$(echo "$INPUT" | grep -o '"prompt"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"prompt"[[:space:]]*:[[:space:]]*"//;s/"$//' 2>/dev/null) || PROMPT=""
[ -z "$PROMPT" ] && exit 0

# Resolve STATE_DIR (same logic as workflow-state.sh)
STATE_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}/.claude/state"

# Detect phase commands: explicit slash commands only
# Regex: ^\s*/<command>(\s|$) — anchored to line start, must start with /
TARGET=""
if echo "$PROMPT" | grep -qE '^\s*/define(\s|$)'; then
    TARGET="define"
elif echo "$PROMPT" | grep -qE '^\s*/discuss(\s|$)'; then
    TARGET="discuss"
elif echo "$PROMPT" | grep -qE '^\s*/implement(\s|$)'; then
    TARGET="implement"
elif echo "$PROMPT" | grep -qE '^\s*/review(\s|$)'; then
    TARGET="review"
elif echo "$PROMPT" | grep -qE '^\s*/complete(\s|$)'; then
    TARGET="complete"
elif echo "$PROMPT" | grep -qE '^\s*/off(\s|$)'; then
    TARGET="off"
fi

# Detect autonomy commands: /autonomy <level>
AUTONOMY_TARGET=""
if echo "$PROMPT" | grep -qE '^\s*/autonomy\s+'; then
    RAW_LEVEL=$(echo "$PROMPT" | grep -oE '/autonomy\s+\S+' | head -1 | awk '{print $2}')
    case "$RAW_LEVEL" in
        1|off) AUTONOMY_TARGET="autonomy:off" ;;
        2|ask) AUTONOMY_TARGET="autonomy:ask" ;;
        3|auto) AUTONOMY_TARGET="autonomy:auto" ;;
    esac
fi

# No matching command — exit silently
[ -z "$TARGET" ] && [ -z "$AUTONOMY_TARGET" ] && exit 0

# Write phase intent file
if [ -n "$TARGET" ]; then
    printf '{"intent":"%s"}\n' "$TARGET" > "$STATE_DIR/phase-intent.json"
    if [ ! -s "$STATE_DIR/phase-intent.json" ]; then
        echo "ERROR: Failed to write phase intent file to $STATE_DIR/phase-intent.json" >&2
        # exit 0, not exit 1 — let the prompt through, set_phase() will produce diagnostics
    fi
fi

# Write autonomy intent file (separate file — prevents overwrite when both in same prompt)
if [ -n "$AUTONOMY_TARGET" ]; then
    printf '{"intent":"%s"}\n' "$AUTONOMY_TARGET" > "$STATE_DIR/autonomy-intent.json"
    if [ ! -s "$STATE_DIR/autonomy-intent.json" ]; then
        echo "ERROR: Failed to write autonomy intent file to $STATE_DIR/autonomy-intent.json" >&2
    fi
fi

exit 0
```

- [ ] **Step 2: Make it executable**

Run: `chmod +x plugin/scripts/user-phase-gate.sh`

- [ ] **Step 3: Verify hook runs with test input**

Run: `echo '{"prompt": "/discuss some args"}' | bash plugin/scripts/user-phase-gate.sh && echo "exit: $?"`

Expected: exit 0, and a file `.claude/state/phase-intent.json` containing `{"intent":"discuss"}`

Run: `cat .claude/state/phase-intent.json`

Expected: `{"intent":"discuss"}`

- [ ] **Step 4: Clean up test artifact**

Run: `rm -f .claude/state/phase-intent.json .claude/state/autonomy-intent.json`

- [ ] **Step 5: Commit**

```bash
git add plugin/scripts/user-phase-gate.sh
git commit -m "feat: add intent file hook — replaces token-based user-phase-token.sh

printf-only (shell builtin, no jq/PATH dependency). Writes phase-intent.json
and autonomy-intent.json to .claude/state/ for consumption by set_phase().

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

### Task 2: Replace token functions with intent functions in `workflow-state.sh`

**Files:**
- Modify: `plugin/scripts/workflow-state.sh:103-130` (delete token functions)
- Modify: `plugin/scripts/workflow-state.sh:328-355` (update set_phase authorization)
- Modify: `plugin/scripts/workflow-state.sh:158-183` (update set_autonomy_level)

- [ ] **Step 1: Write failing tests for intent file authorization**

Add to `tests/run-tests.sh` — replace the BUG-3 token test suite (lines 2269-2543) with intent file tests. Delete everything from `# TEST SUITE: BUG-3 — Phase token authorization` through the `.phase-tokens guard also fires in DISCUSS phase` test (before `# RESULTS`). Replace with:

```bash
# ============================================================
# TEST SUITE: BUG-3 — Phase intent file authorization
# ============================================================
echo ""
echo "=== BUG-3: Phase intent file authorization ==="

# Helper: create a phase intent file for testing
create_phase_intent() {
    local target="$1"
    printf '{"intent":"%s"}\n' "$target" > "$TEST_DIR/.claude/state/phase-intent.json"
}

# Helper: create an autonomy intent file for testing
create_autonomy_intent() {
    local target="$1"
    printf '{"intent":"%s"}\n' "$target" > "$TEST_DIR/.claude/state/autonomy-intent.json"
}

# Test: set_phase blocked without intent file
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
OUTPUT=$(run_with_auth set_phase "review" 2>&1) || true
assert_contains "$OUTPUT" "BLOCKED" "set_phase blocked without intent file"
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_phase)
assert_eq "implement" "$RESULT" "phase unchanged after blocked set_phase"

# Test: set_phase allowed with valid intent file
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
create_phase_intent "review"
run_with_auth set_phase "review"
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_phase)
assert_eq "review" "$RESULT" "set_phase allowed with valid intent file"

# Test: intent file deleted after consumption
assert_file_not_exists "$TEST_DIR/.claude/state/phase-intent.json" "intent file deleted after consumption"

# Test: second set_phase blocked after intent consumed
OUTPUT=$(run_with_auth set_phase "review" 2>&1) || true
assert_contains "$OUTPUT" "BLOCKED" "second set_phase blocked after intent consumed"

# Test: wrong intent target rejected
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
create_phase_intent "define"
OUTPUT=$(run_with_auth set_phase "review" 2>&1) || true
assert_contains "$OUTPUT" "BLOCKED" "set_phase blocked with wrong intent target"
# Intent file should survive (not consumed on mismatch)
assert_file_exists "$TEST_DIR/.claude/state/phase-intent.json" "non-matching intent file survives"

# Test: forward auto-transition allowed without intent when autonomy=auto
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_autonomy_level "auto"
run_with_auth set_phase "review"
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_phase)
assert_eq "review" "$RESULT" "forward auto-transition allowed in auto mode"

# Test: backward transition blocked even in auto mode
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "review"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_autonomy_level "auto"
OUTPUT=$(run_with_auth set_phase "implement" 2>&1) || true
assert_contains "$OUTPUT" "BLOCKED" "backward transition blocked in auto mode"

# Test: transition to OFF blocked even in auto mode
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_autonomy_level "auto"
OUTPUT=$(run_with_auth set_phase "off" 2>&1) || true
assert_contains "$OUTPUT" "BLOCKED" "transition to OFF blocked in auto mode"

# Test: set_autonomy_level blocked without intent
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_autonomy_level "ask"
OUTPUT=$(run_with_auth set_autonomy_level "auto" 2>&1) || true
assert_contains "$OUTPUT" "BLOCKED" "set_autonomy_level blocked without intent"

# Test: set_autonomy_level allowed with valid autonomy intent
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
create_autonomy_intent "autonomy:auto"
run_with_auth set_autonomy_level "auto"
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_autonomy_level)
assert_eq "auto" "$RESULT" "set_autonomy_level allowed with valid autonomy intent"
assert_file_not_exists "$TEST_DIR/.claude/state/autonomy-intent.json" "autonomy intent consumed after use"

# Test: phase + autonomy intents coexist (independent files, independent consumption)
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
create_phase_intent "review"
create_autonomy_intent "autonomy:auto"
# Consume phase intent
run_with_auth set_phase "review"
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_phase)
assert_eq "review" "$RESULT" "phase intent consumed"
# Autonomy intent should still exist
assert_file_exists "$TEST_DIR/.claude/state/autonomy-intent.json" "autonomy intent survives when phase intent consumed"

# Test: escalation attack — forward-transition defense holds without autonomy escalation
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
# No autonomy intent — escalation blocked
run_with_auth set_autonomy_level "auto" 2>/dev/null || true
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_autonomy_level)
assert_eq "ask" "$RESULT" "escalation attack: autonomy stays at ask without intent"
OUTPUT=$(run_with_auth set_phase "review" 2>&1) || true
assert_contains "$OUTPUT" "BLOCKED" "escalation attack: forward transition blocked when autonomy escalation failed"

# ============================================================
# TEST SUITE: BUG-3 — Integration: intent hook + state functions
# ============================================================
echo ""
echo "=== BUG-3: Integration — intent hook + state ==="

# Test: hook generates valid phase intent for /review
setup_test_project
export CLAUDE_PROJECT_DIR="$TEST_DIR"
echo '{"prompt": "/review"}' | bash "$REPO_DIR/plugin/scripts/user-phase-gate.sh"
assert_file_exists "$TEST_DIR/.claude/state/phase-intent.json" "hook creates phase-intent.json for /review"
INTENT=$(jq -r '.intent' "$TEST_DIR/.claude/state/phase-intent.json")
assert_eq "review" "$INTENT" "hook writes correct intent for /review"

# Test: hook generates valid autonomy intent for /autonomy auto
rm -f "$TEST_DIR/.claude/state/phase-intent.json" "$TEST_DIR/.claude/state/autonomy-intent.json"
echo '{"prompt": "/autonomy auto"}' | bash "$REPO_DIR/plugin/scripts/user-phase-gate.sh"
assert_file_exists "$TEST_DIR/.claude/state/autonomy-intent.json" "hook creates autonomy-intent.json for /autonomy auto"
INTENT=$(jq -r '.intent' "$TEST_DIR/.claude/state/autonomy-intent.json")
assert_eq "autonomy:auto" "$INTENT" "hook writes correct intent for /autonomy auto"

# Test: hook generates no intent for non-phase prompt
rm -f "$TEST_DIR/.claude/state/phase-intent.json" "$TEST_DIR/.claude/state/autonomy-intent.json"
echo '{"prompt": "help me write a function"}' | bash "$REPO_DIR/plugin/scripts/user-phase-gate.sh"
assert_file_not_exists "$TEST_DIR/.claude/state/phase-intent.json" "hook generates no intent for non-phase prompt"

# Test: hook generates intent for /off
rm -f "$TEST_DIR/.claude/state/phase-intent.json"
echo '{"prompt": "/off"}' | bash "$REPO_DIR/plugin/scripts/user-phase-gate.sh"
INTENT=$(jq -r '.intent' "$TEST_DIR/.claude/state/phase-intent.json")
assert_eq "off" "$INTENT" "hook writes correct intent for /off"

# Test: bare set_phase in text generates NO intent (false-positive regression)
rm -f "$TEST_DIR/.claude/state/phase-intent.json"
echo '{"prompt": "now call set_phase review to transition"}' | bash "$REPO_DIR/plugin/scripts/user-phase-gate.sh"
assert_file_not_exists "$TEST_DIR/.claude/state/phase-intent.json" "bare set_phase in text generates no intent (false-positive regression)"

# Test: bare set_autonomy_level in text generates NO intent
rm -f "$TEST_DIR/.claude/state/autonomy-intent.json"
echo '{"prompt": "set_autonomy_level auto"}' | bash "$REPO_DIR/plugin/scripts/user-phase-gate.sh"
assert_file_not_exists "$TEST_DIR/.claude/state/autonomy-intent.json" "bare set_autonomy_level in text generates no intent"

# Test: malformed JSON input produces no intent and exits cleanly
rm -f "$TEST_DIR/.claude/state/phase-intent.json"
echo "not json at all" | bash "$REPO_DIR/plugin/scripts/user-phase-gate.sh"
assert_file_not_exists "$TEST_DIR/.claude/state/phase-intent.json" "malformed JSON input produces no intent"

# Test: /discuss with arguments generates correct intent
rm -f "$TEST_DIR/.claude/state/phase-intent.json"
echo '{"prompt": "/discuss we need to fix these bugs"}' | bash "$REPO_DIR/plugin/scripts/user-phase-gate.sh"
INTENT=$(jq -r '.intent' "$TEST_DIR/.claude/state/phase-intent.json")
assert_eq "discuss" "$INTENT" "hook writes correct intent for /discuss with arguments"

# Test: /complete generates only phase intent (no autonomy or off intent)
rm -f "$TEST_DIR/.claude/state/phase-intent.json" "$TEST_DIR/.claude/state/autonomy-intent.json"
echo '{"prompt": "/complete"}' | bash "$REPO_DIR/plugin/scripts/user-phase-gate.sh"
INTENT=$(jq -r '.intent' "$TEST_DIR/.claude/state/phase-intent.json")
assert_eq "complete" "$INTENT" "/complete generates phase intent with target 'complete'"
assert_file_not_exists "$TEST_DIR/.claude/state/autonomy-intent.json" "/complete does not generate autonomy intent"

# Test: Full flow — hook generates intent, set_phase consumes it
setup_test_project
export CLAUDE_PROJECT_DIR="$TEST_DIR"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
echo '{"prompt": "/review"}' | bash "$REPO_DIR/plugin/scripts/user-phase-gate.sh"
run_with_auth set_phase "review"
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_phase)
assert_eq "review" "$RESULT" "full flow: hook intent allows set_phase"
assert_file_not_exists "$TEST_DIR/.claude/state/phase-intent.json" "full flow: intent file consumed"

# Test: Full flow — autonomy intent
setup_test_project
export CLAUDE_PROJECT_DIR="$TEST_DIR"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
echo '{"prompt": "/autonomy auto"}' | bash "$REPO_DIR/plugin/scripts/user-phase-gate.sh"
run_with_auth set_autonomy_level "auto"
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_autonomy_level)
assert_eq "auto" "$RESULT" "full flow: hook intent allows set_autonomy_level"

# Test: intent file guard in bash-write-guard
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
OUTPUT=$(run_bash_guard 'echo x > .claude/state/phase-intent.json')
assert_contains "$OUTPUT" "deny" "bash-write-guard blocks phase-intent.json write (defense-in-depth)"

# Test: workflow.json guard in bash-write-guard
OUTPUT=$(run_bash_guard 'echo x > .claude/state/workflow.json')
assert_contains "$OUTPUT" "deny" "bash-write-guard blocks workflow.json write (defense-in-depth)"

# Test: intent guard also fires in DISCUSS phase
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "discuss"
OUTPUT=$(run_bash_guard 'echo x > .claude/state/phase-intent.json')
assert_contains "$OUTPUT" "deny" "bash-write-guard blocks intent write in DISCUSS (defense-in-depth)"

# Test: hook self-validates write (unwritable state dir → exits 0, no intent file)
setup_test_project
SAVE_DIR="$TEST_DIR/.claude/state"
chmod 444 "$SAVE_DIR"
OUTPUT=$(echo '{"prompt": "/review"}' | CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$REPO_DIR/plugin/scripts/user-phase-gate.sh" 2>&1) || true
EXIT_CODE=$?
chmod 755 "$SAVE_DIR"
# Hook should exit 0 (not block the prompt) and log error to stderr
assert_eq "0" "$EXIT_CODE" "hook exits 0 on write failure (does not block prompt)"
assert_file_not_exists "$TEST_DIR/.claude/state/phase-intent.json" "no intent file when write fails"

# Test: stale intent file cleanup in setup.sh
setup_test_project
printf '{"intent":"stale"}\n' > "$TEST_DIR/.claude/state/phase-intent.json"
printf '{"intent":"autonomy:stale"}\n' > "$TEST_DIR/.claude/state/autonomy-intent.json"
# Run setup.sh in isolated HOME to avoid modifying real ~/.claude/
export CLAUDE_PROJECT_DIR="$TEST_DIR"
FAKE_HOME=$(mktemp -d)
HOME="$FAKE_HOME" bash "$REPO_DIR/plugin/scripts/setup.sh"
rm -rf "$FAKE_HOME"
assert_file_not_exists "$TEST_DIR/.claude/state/phase-intent.json" "setup.sh cleans stale phase intent"
assert_file_not_exists "$TEST_DIR/.claude/state/autonomy-intent.json" "setup.sh cleans stale autonomy intent"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/run-tests.sh 2>&1 | tail -20`

Expected: Multiple failures because `_check_phase_intent` doesn't exist yet and tests reference new hook.

- [ ] **Step 3: Replace `_check_phase_token` and `_check_autonomy_token` with intent functions**

In `plugin/scripts/workflow-state.sh`, replace lines 100-130 (the `_check_phase_token` and `_check_autonomy_token` functions) with:

```bash
# Check for a valid phase intent file. Consumes the intent on success.
# Returns 0 if authorized, 1 if blocked.
_check_phase_intent() {
    local target_phase="$1"
    local intent_file="$STATE_DIR/phase-intent.json"
    [ -s "$intent_file" ] || return 1
    local intent
    intent=$(jq -r '.intent // ""' "$intent_file" 2>/dev/null) || return 1
    if [ "$intent" = "$target_phase" ]; then
        rm -f "$intent_file"
        return 0
    fi
    return 1
}

# Check for a valid autonomy intent file. Consumes the intent on success.
# Returns 0 if authorized, 1 if blocked.
_check_autonomy_intent() {
    local level="$1"
    local intent_file="$STATE_DIR/autonomy-intent.json"
    [ -s "$intent_file" ] || return 1
    local intent
    intent=$(jq -r '.intent // ""' "$intent_file" 2>/dev/null) || return 1
    if [ "$intent" = "autonomy:$level" ]; then
        rm -f "$intent_file"
        return 0
    fi
    return 1
}
```

- [ ] **Step 4: Update `set_phase()` authorization to use `_check_phase_intent`**

In `plugin/scripts/workflow-state.sh`, in the `set_phase()` function, replace:
```bash
        if _check_phase_token "$new_phase"; then
```
with:
```bash
        if _check_phase_intent "$new_phase"; then
```

- [ ] **Step 5: Update `set_autonomy_level()` authorization to use `_check_autonomy_intent`**

In `plugin/scripts/workflow-state.sh`, in the `set_autonomy_level()` function, replace:
```bash
        if ! _check_autonomy_token "$level"; then
```
with:
```bash
        if ! _check_autonomy_intent "$level"; then
```

- [ ] **Step 6: Update `run_with_auth` test helper and `setup_test_project` comment**

The `run_with_auth` helper currently exports `CLAUDE_PLUGIN_DATA`. Intent files use `STATE_DIR` (which is `CLAUDE_PROJECT_DIR/.claude/state`), so ensure `CLAUDE_PROJECT_DIR` is set. The current helper already exports `CLAUDE_PROJECT_DIR` via `setup_test_project`, so this should work. But remove the `CLAUDE_PLUGIN_DATA` export since it's no longer needed:

In `tests/run-tests.sh`, replace the `run_with_auth` function:
```bash
run_with_auth() {
    (unset WF_SKIP_AUTH; source "$TEST_DIR/.claude/hooks/workflow-state.sh" && "$@")
}
```

Also update the `setup_test_project` comment (line 121) from:
```bash
    # Skip token auth for existing tests (BUG-3 tests explicitly unset this via run_with_auth)
```
to:
```bash
    # Skip intent auth for existing tests (BUG-3 tests explicitly unset this via run_with_auth)
```

- [ ] **Step 7: Run tests**

Run: `bash tests/run-tests.sh 2>&1 | tail -30`

Expected: All tests pass.

- [ ] **Step 8: Commit**

```bash
git add plugin/scripts/workflow-state.sh tests/run-tests.sh
git commit -m "refactor: replace phase tokens with intent files in workflow-state.sh

Delete _check_phase_token/_check_autonomy_token. Add _check_phase_intent/
_check_autonomy_intent that read fixed-path files instead of iterating a
token directory. Update test suite with intent-based authorization tests.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

### Task 3: Update bash-write-guard and hooks.json

**Files:**
- Modify: `plugin/scripts/bash-write-guard.sh:117-126`
- Modify: `plugin/hooks/hooks.json:33`

- [ ] **Step 1: Replace `.phase-tokens` guard with intent+state file guard**

In `plugin/scripts/bash-write-guard.sh`, replace lines 117-126:

```bash
# ---------------------------------------------------------------------------
# Defense-in-depth: block writes to .phase-tokens directory in ALL active phases
# Fires before the implement/review early-exit to catch token forgery attempts.
# NOTE: PreToolUse blocking is unreliable — this is a speed bump, not a wall.
# ---------------------------------------------------------------------------

if echo "$COMMAND" | grep -qE '\.phase-tokens'; then
    emit_deny "BLOCKED: Direct writes to the phase token directory are not allowed. Phase tokens are generated by the workflow system."
    exit 0
fi
```

With:

```bash
# ---------------------------------------------------------------------------
# Defense-in-depth: block writes to workflow state and intent files in ALL active phases
# Uses path-qualified patterns to avoid false positives on read commands.
# Fires before the implement/review early-exit to catch forgery attempts.
# NOTE: PreToolUse blocking is unreliable — this is a speed bump, not a wall.
# ---------------------------------------------------------------------------

if echo "$COMMAND" | grep -qE '\.claude/(state/workflow\.json|state/phase-intent\.json|state/autonomy-intent\.json)'; then
    emit_deny "BLOCKED: Direct writes to workflow state files are not allowed."
    exit 0
fi
```

- [ ] **Step 2: Update hooks.json — point UserPromptSubmit at new hook**

In `plugin/hooks/hooks.json`, replace:
```json
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/user-phase-token.sh",
```
With:
```json
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/user-phase-gate.sh",
```

- [ ] **Step 3: Run tests**

Run: `bash tests/run-tests.sh 2>&1 | tail -10`

Expected: All tests pass, including the new bash-write-guard intent file tests.

- [ ] **Step 4: Commit**

```bash
git add plugin/scripts/bash-write-guard.sh plugin/hooks/hooks.json
git commit -m "refactor: update guards and hooks for intent file system

Replace .phase-tokens directory guard with path-qualified guard covering
workflow.json, phase-intent.json, and autonomy-intent.json. Point
UserPromptSubmit hook at user-phase-gate.sh.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

### Task 4: Cleanup — delete old token infrastructure, add setup.sh cleanup

**Files:**
- Delete: `plugin/scripts/user-phase-token.sh`
- Modify: `plugin/scripts/setup.sh:39`
- Delete: `.claude/plugin-data/.phase-tokens/` (runtime directory)

- [ ] **Step 1: Delete old token hook**

Run: `git rm plugin/scripts/user-phase-token.sh`

- [ ] **Step 2: Add stale intent file cleanup to setup.sh**

In `plugin/scripts/setup.sh`, after line 39 (`find "$STATE_DIR" -name '*.tmp.*' ...`), add:

```bash
# Clean up stale intent files from previous sessions
rm -f "$STATE_DIR/phase-intent.json" "$STATE_DIR/autonomy-intent.json"
```

- [ ] **Step 3: Delete runtime token directory**

Run: `rm -rf .claude/plugin-data/.phase-tokens`

- [ ] **Step 4: Run tests**

Run: `bash tests/run-tests.sh 2>&1 | tail -10`

Expected: All tests pass, including the setup.sh stale intent cleanup test.

- [ ] **Step 5: Commit**

```bash
git add plugin/scripts/setup.sh
git commit -m "chore: delete token infrastructure, add intent file cleanup

Remove user-phase-token.sh (replaced by user-phase-gate.sh).
Add stale intent file cleanup to setup.sh SessionStart hook.
Delete .phase-tokens runtime directory.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

### Task 5: Version bump fix — move from COMPLETE to IMPLEMENT (#3907)

**Files:**
- Modify: `plugin/commands/implement.md`
- Modify: `plugin/commands/complete.md:226-258`

- [ ] **Step 1: Add version bump step to implement.md**

In `plugin/commands/implement.md`, after step 4 (line 34-36, the `all_tasks_complete` milestone) and before step 5 (line 37-40, tests_passing), add:

```markdown
4b. **Version bump** (after all tasks complete, before final test run):

Dispatch a **Versioning agent** to determine the bump type:

Prompt: "Determine the semantic version bump for this release.
1. Read the decision record at [DECISION_RECORD_PATH] for phase history
2. Read `git log --oneline main...HEAD` for commit history (if no divergence, check last 10 commits)
3. Read current version from `.claude-plugin/marketplace.json`
4. Apply these rules:
   - **Major** (X.0.0): Breaking changes to public API — hook contract changes, state schema changes that break existing state files, command interface changes
   - **Minor** (x.Y.0): New features — session went through DEFINE/DISCUSS phases (new capability), new commands added, new state fields
   - **Patch** (x.y.Z): Bug fixes, refactors, tech debt cleanup, doc updates — changes are internal only
5. Return: current version, bump type (major/minor/patch), new version, one-line reasoning"

Apply the version bump to all 3 files:
```bash
python3 -c "
import json, sys
new_version = sys.argv[1]
for path in ['.claude-plugin/marketplace.json', '.claude-plugin/plugin.json', 'plugin/.claude-plugin/plugin.json']:
    with open(path) as f:
        data = json.load(f)
    if 'plugins' in data:
        data['plugins'][0]['version'] = new_version
    else:
        data['version'] = new_version
    with open(path, 'w') as f:
        json.dump(data, f, indent=2)
        f.write('\n')
" "<NEW_VERSION>"
```

Run `scripts/check-version-sync.sh` to validate all 3 files match. This is not an IMPLEMENT exit gate — COMPLETE Step 5 will verify it.
```

- [ ] **Step 2: Replace version bump with verification in complete.md**

In `plugin/commands/complete.md`, replace the version bump section (lines 226-258, from `2b. **Version bump:**` through the `check-version-sync.sh` line) with:

```markdown
2b. **Version verification:** Verify the version bump was done during IMPLEMENT.

Run `scripts/check-version-sync.sh` to validate all 3 version files match.
Then verify the version is greater than the last release tag:
```bash
CURRENT=$(jq -r '.plugins[0].version // .version' .claude-plugin/marketplace.json)
LAST_TAG=$(git tag -l 'v*' --sort=-v:refname | head -1 | sed 's/^v//')
echo "Current: $CURRENT, Last tag: ${LAST_TAG:-none}"
```

If version bump was not done (version matches or is less than last tag), flag as validation failure:
> "Version bump missing — loop back to `/implement` and run the versioning step."
```

- [ ] **Step 3: Commit**

```bash
git add plugin/commands/implement.md plugin/commands/complete.md
git commit -m "fix: move version bump from COMPLETE to IMPLEMENT phase (#3907)

COMPLETE phase write whitelist blocks .claude-plugin/ files. Version bump
now runs during IMPLEMENT (all writes allowed). COMPLETE Step 5 verifies
the bump was done and loops back if missing.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

### Task 6: Final validation and full test run

**Files:** None (validation only)

- [ ] **Step 1: Run full test suite**

Run: `bash tests/run-tests.sh`

Expected: All tests pass, 0 failures.

- [ ] **Step 2: Verify hook works end-to-end**

Simulate the full flow manually:

```bash
# Simulate UserPromptSubmit for /implement
echo '{"prompt": "/implement"}' | bash plugin/scripts/user-phase-gate.sh
cat .claude/state/phase-intent.json
# Expected: {"intent":"implement"}

# Verify set_phase can consume it
source plugin/scripts/workflow-state.sh && set_phase "implement"
echo "Phase: $(source plugin/scripts/workflow-state.sh && get_phase)"
# Expected: Phase: implement

# Verify intent file was consumed
ls -la .claude/state/phase-intent.json 2>/dev/null || echo "Intent file consumed (deleted)"
# Expected: Intent file consumed (deleted)
```

- [ ] **Step 3: Verify guard blocks forgery**

```bash
# Set up an active phase first
source plugin/scripts/workflow-state.sh && WF_SKIP_AUTH=1 set_phase "implement"

# Simulate bash-write-guard check
echo '{"tool_input":{"command":"printf x > .claude/state/phase-intent.json"}}' | bash plugin/scripts/bash-write-guard.sh 2>&1
# Expected: output contains "deny" and "workflow state files"
```

- [ ] **Step 4: Verify no references to old token system remain**

Run: `grep -r 'phase-token\|_check_phase_token\|_check_autonomy_token\|\.phase-tokens\|user-phase-token' plugin/ tests/ --include='*.sh' --include='*.json' --include='*.md' | grep -v 'specs/' | grep -v 'plans/'`

Expected: No output (no references outside of spec/plan docs).

- [ ] **Step 5: Verify git status is clean**

Run: `git status`

Expected: Clean working tree, all changes committed.
