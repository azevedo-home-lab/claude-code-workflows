# 3 HIGH Bug Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix 3 HIGH priority bugs (BUG-1, BUG-2, BUG-3) that undermine workflow enforcement reliability.

**Architecture:** BUG-1 and BUG-2 are simple fixes to command templates and state functions. BUG-3 adds a UserPromptSubmit hook that generates one-time tokens for phase/autonomy commands, with `set_phase()` and `set_autonomy_level()` verifying tokens before allowing state changes. Existing tests need a `WF_SKIP_AUTH=1` env var to bypass token checks.

**Tech Stack:** Bash, jq, Claude Code hooks system

**Spec:** `docs/superpowers/specs/2026-03-25-high-bug-fixes-design.md`

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `plugin/commands/define.md` | Modify | Chain echo with `&&` (BUG-2) |
| `plugin/commands/discuss.md` | Modify | Chain echo with `&&` (BUG-2) |
| `plugin/commands/implement.md` | Modify | Chain echo with `&&` (BUG-2) |
| `plugin/commands/review.md` | Modify | Chain echo with `&&` (BUG-2) |
| `plugin/commands/complete.md` | Modify | Chain echo with `&&` (BUG-2) |
| `plugin/commands/autonomy.md` | Modify | Numeric mapping + echo chaining (BUG-1 + BUG-2) |
| `plugin/scripts/workflow-state.sh` | Modify | Numeric mapping in `set_autonomy_level`, token auth in `set_phase` and `set_autonomy_level`, `_phase_ordinal` helper, `_check_phase_token`/`_check_autonomy_token` helpers (BUG-1 + BUG-3) |
| `plugin/scripts/user-phase-token.sh` | Create | UserPromptSubmit hook — generates one-time tokens for phase/autonomy commands (BUG-3) |
| `plugin/hooks/hooks.json` | Modify | Add UserPromptSubmit hook registration (BUG-3) |
| `tests/run-tests.sh` | Modify | Add BUG-1, BUG-2, BUG-3 tests; add `WF_SKIP_AUTH=1` to `setup_test_project` (BUG-1 + BUG-3) |

---

### Task 1: BUG-2 — Fix echo chaining in 5 phase commands

**Files:**
- Modify: `plugin/commands/define.md:4-5`
- Modify: `plugin/commands/discuss.md:4-5`
- Modify: `plugin/commands/implement.md:14-15`
- Modify: `plugin/commands/review.md:14-15`
- Modify: `plugin/commands/complete.md:14-15`

- [ ] **Step 1: Fix `define.md` — chain echo with `&&`**

In `plugin/commands/define.md`, replace the bash block (lines 3-6):
```bash
WF="${CLAUDE_PLUGIN_ROOT}/scripts/workflow-cmd.sh" && "$WF" set_phase "define" && "$WF" set_active_skill ""
echo "Phase set to DEFINE — code edits are blocked. Define the problem and outcomes first."
```
With:
```bash
WF="${CLAUDE_PLUGIN_ROOT}/scripts/workflow-cmd.sh" && "$WF" set_phase "define" && "$WF" set_active_skill "" && echo "Phase set to DEFINE — code edits are blocked. Define the problem and outcomes first."
```

- [ ] **Step 2: Fix `discuss.md` — chain echo with `&&`**

In `plugin/commands/discuss.md`, replace the bash block (lines 3-6):
```bash
WF="${CLAUDE_PLUGIN_ROOT}/scripts/workflow-cmd.sh" && "$WF" set_phase "discuss" && "$WF" set_active_skill ""
echo "Phase set to DISCUSS — code edits are now blocked until plan is ready."
```
With:
```bash
WF="${CLAUDE_PLUGIN_ROOT}/scripts/workflow-cmd.sh" && "$WF" set_phase "discuss" && "$WF" set_active_skill "" && echo "Phase set to DISCUSS — code edits are now blocked until plan is ready."
```

- [ ] **Step 3: Fix `implement.md` — chain echo with `&&`**

In `plugin/commands/implement.md`, replace the bash block (lines 13-16):
```bash
WF="${CLAUDE_PLUGIN_ROOT}/scripts/workflow-cmd.sh" && "$WF" set_phase "implement" && "$WF" reset_implement_status && "$WF" set_active_skill ""
echo "Phase set to IMPLEMENT — code edits are now allowed."
```
With:
```bash
WF="${CLAUDE_PLUGIN_ROOT}/scripts/workflow-cmd.sh" && "$WF" set_phase "implement" && "$WF" reset_implement_status && "$WF" set_active_skill "" && echo "Phase set to IMPLEMENT — code edits are now allowed."
```

- [ ] **Step 4: Fix `review.md` — chain echo with `&&`**

In `plugin/commands/review.md`, replace the bash block (lines 13-16):
```bash
WF="${CLAUDE_PLUGIN_ROOT}/scripts/workflow-cmd.sh" && "$WF" set_phase "review" && "$WF" reset_review_status && "$WF" set_active_skill "review-pipeline"
echo "Phase set to REVIEW — running review pipeline."
```
With:
```bash
WF="${CLAUDE_PLUGIN_ROOT}/scripts/workflow-cmd.sh" && "$WF" set_phase "review" && "$WF" reset_review_status && "$WF" set_active_skill "review-pipeline" && echo "Phase set to REVIEW — running review pipeline."
```

- [ ] **Step 5: Fix `complete.md` — chain echo with `&&`**

In `plugin/commands/complete.md`, replace the bash block (lines 13-16):
```bash
WF="${CLAUDE_PLUGIN_ROOT}/scripts/workflow-cmd.sh" && "$WF" set_phase "complete" && "$WF" reset_completion_status && "$WF" set_active_skill "completion-pipeline"
echo "Phase set to COMPLETE — running completion pipeline. Code edits blocked, doc updates allowed."
```
With:
```bash
WF="${CLAUDE_PLUGIN_ROOT}/scripts/workflow-cmd.sh" && "$WF" set_phase "complete" && "$WF" reset_completion_status && "$WF" set_active_skill "completion-pipeline" && echo "Phase set to COMPLETE — running completion pipeline. Code edits blocked, doc updates allowed."
```

- [ ] **Step 6: Write BUG-2 verification test**

Append to `tests/run-tests.sh`, after the existing autonomy level tests section:

```bash
# --- BUG-2: Echo chaining verification ---

# Test: echo suppressed when set_phase fails (hard gate)
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && reset_implement_status
# set_phase should fail (hard gate: implement milestones incomplete), && echo should NOT fire
WF="$TEST_DIR/.claude/hooks/workflow-cmd.sh"
OUTPUT=$("$WF" set_phase "review" && echo "Phase set to REVIEW" 2>&1 || true)
assert_not_contains "$OUTPUT" "Phase set to REVIEW" "BUG-2: echo suppressed when set_phase fails (hard gate)"

# Test: echo fires when set_phase succeeds
setup_test_project
WF="$TEST_DIR/.claude/hooks/workflow-cmd.sh"
OUTPUT=$("$WF" set_phase "implement" && echo "Phase set to IMPLEMENT" 2>&1)
assert_contains "$OUTPUT" "Phase set to IMPLEMENT" "BUG-2: echo fires when set_phase succeeds"
```

- [ ] **Step 7: Run tests to verify no regression**

Run: `bash tests/run-tests.sh`
Expected: All existing tests pass plus 2 new BUG-2 tests pass.

- [ ] **Step 8: Commit BUG-2 fix**

```bash
git add plugin/commands/define.md plugin/commands/discuss.md plugin/commands/implement.md plugin/commands/review.md plugin/commands/complete.md
git commit -m "fix: chain echo with && in phase commands to prevent false success messages (BUG-2)"
```

---

### Task 2: BUG-1 — Add backward-compat mapping for `/autonomy` numeric values

**Files:**
- Modify: `plugin/commands/autonomy.md:18-21`
- Modify: `plugin/scripts/workflow-state.sh:113-118`
- Test: `tests/run-tests.sh` (add tests)

- [ ] **Step 1: Write failing tests for numeric autonomy values**

Append to the `workflow-state.sh` test suite section in `tests/run-tests.sh`, after the existing `set_autonomy_level` tests (around line 279):

```bash
# --- BUG-1: Backward-compat numeric autonomy values ---

# Test: set_autonomy_level maps numeric 1 to off
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_autonomy_level 1
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_autonomy_level)
assert_eq "off" "$RESULT" "set_autonomy_level maps 1 to off"

# Test: set_autonomy_level maps numeric 2 to ask
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_autonomy_level 2
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_autonomy_level)
assert_eq "ask" "$RESULT" "set_autonomy_level maps 2 to ask"

# Test: set_autonomy_level maps numeric 3 to auto
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_autonomy_level 3
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_autonomy_level)
assert_eq "auto" "$RESULT" "set_autonomy_level maps 3 to auto"

# Test: set_autonomy_level still rejects truly invalid values
OUTPUT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_autonomy_level 4 2>&1 || true)
assert_contains "$OUTPUT" "ERROR" "set_autonomy_level still rejects 4 after backward-compat"

OUTPUT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_autonomy_level abc 2>&1 || true)
assert_contains "$OUTPUT" "ERROR" "set_autonomy_level still rejects abc after backward-compat"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/run-tests.sh 2>&1 | tail -20`
Expected: The 3 numeric mapping tests FAIL (1, 2, 3 are currently rejected as invalid).

- [ ] **Step 3: Add numeric mapping to `set_autonomy_level()` in `workflow-state.sh`**

In `plugin/scripts/workflow-state.sh`, replace `set_autonomy_level()` (lines 113-124):

```bash
set_autonomy_level() {
    local level="$1"
    case "$level" in
        off|ask|auto) ;;
        *) echo "ERROR: Invalid autonomy level: $level (valid: off, ask, auto)" >&2; return 1 ;;
    esac
    if [ ! -f "$STATE_FILE" ]; then
        echo "WARNING: No workflow state file. Start a workflow phase first (e.g., /define)." >&2
        return 1
    fi
    _update_state '.autonomy_level = $v' --arg v "$level"
}
```

With:

```bash
set_autonomy_level() {
    local level="$1"
    # Backward-compat: map legacy numeric values
    case "$level" in
        1) level="off" ;;
        2) level="ask" ;;
        3) level="auto" ;;
    esac
    case "$level" in
        off|ask|auto) ;;
        *) echo "ERROR: Invalid autonomy level: $level (valid: off, ask, auto)" >&2; return 1 ;;
    esac
    if [ ! -f "$STATE_FILE" ]; then
        echo "WARNING: No workflow state file. Start a workflow phase first (e.g., /define)." >&2
        return 1
    fi
    _update_state '.autonomy_level = $v' --arg v "$level"
}
```

- [ ] **Step 4: Fix `autonomy.md` — add normalization + chain echo**

Replace the Execution bash block in `plugin/commands/autonomy.md` (lines 18-20):

```bash
WF="${CLAUDE_PLUGIN_ROOT}/scripts/workflow-cmd.sh" && "$WF" set_autonomy_level "$ARGUMENTS"
echo "Autonomy level set to $ARGUMENTS"
```

With:

```bash
# Normalize legacy numeric values
LEVEL="$ARGUMENTS"
case "$LEVEL" in
    1) LEVEL="off" ;;
    2) LEVEL="ask" ;;
    3) LEVEL="auto" ;;
esac
WF="${CLAUDE_PLUGIN_ROOT}/scripts/workflow-cmd.sh" && "$WF" set_autonomy_level "$LEVEL" && echo "Autonomy level set to $LEVEL"
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `bash tests/run-tests.sh 2>&1 | tail -20`
Expected: All tests pass, including the 3 new numeric mapping tests.

- [ ] **Step 6: Commit BUG-1 fix**

```bash
git add plugin/scripts/workflow-state.sh plugin/commands/autonomy.md tests/run-tests.sh
git commit -m "fix: add backward-compat mapping for numeric autonomy values (BUG-1)"
```

---

### Task 3: BUG-3 — Create `user-phase-token.sh` UserPromptSubmit hook

**Files:**
- Create: `plugin/scripts/user-phase-token.sh`

- [ ] **Step 1: Create the hook script**

Create `plugin/scripts/user-phase-token.sh`:

```bash
#!/bin/bash
# Copyright (C) 2026 azevedo-home-lab
# SPDX-License-Identifier: GPL-3.0-only
#
# UserPromptSubmit hook: generates one-time tokens for phase and autonomy commands.
# Tokens are consumed by set_phase() and set_autonomy_level() in workflow-state.sh.
# Claude cannot trigger this hook — it only fires on actual user input.

set -euo pipefail

# Read stdin JSON
INPUT=$(cat)

# Extract prompt
PROMPT=$(echo "$INPUT" | jq -r '.prompt // ""' 2>/dev/null) || PROMPT=""
[ -z "$PROMPT" ] && exit 0

# Token directory
TOKEN_DIR="${CLAUDE_PLUGIN_DATA:-${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}/.claude/plugin-data}/.phase-tokens"

# Detect phase commands: /define, /discuss, /implement, /review, /complete
# Also detect bare set_phase calls (user running via ! prefix)
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
elif echo "$PROMPT" | grep -qE 'set_phase\s+"?(off|define|discuss|implement|review|complete)"?'; then
    TARGET=$(echo "$PROMPT" | grep -oE 'set_phase\s+"?(off|define|discuss|implement|review|complete)"?' | head -1 | sed 's/set_phase[[:space:]]*//' | tr -d '"')
fi

# Detect autonomy commands: /autonomy <level>
AUTONOMY_TARGET=""
if echo "$PROMPT" | grep -qE '^\s*/autonomy\s+'; then
    RAW_LEVEL=$(echo "$PROMPT" | grep -oE '/autonomy\s+\S+' | head -1 | awk '{print $2}')
    # Normalize numeric values
    case "$RAW_LEVEL" in
        1|off) AUTONOMY_TARGET="autonomy:off" ;;
        2|ask) AUTONOMY_TARGET="autonomy:ask" ;;
        3|auto) AUTONOMY_TARGET="autonomy:auto" ;;
    esac
elif echo "$PROMPT" | grep -qE 'set_autonomy_level\s+"?(off|ask|auto|1|2|3)"?'; then
    RAW_LEVEL=$(echo "$PROMPT" | grep -oE 'set_autonomy_level\s+"?(off|ask|auto|1|2|3)"?' | head -1 | sed 's/set_autonomy_level[[:space:]]*//' | tr -d '"')
    case "$RAW_LEVEL" in
        1|off) AUTONOMY_TARGET="autonomy:off" ;;
        2|ask) AUTONOMY_TARGET="autonomy:ask" ;;
        3|auto) AUTONOMY_TARGET="autonomy:auto" ;;
    esac
fi

# No matching command — exit silently
[ -z "$TARGET" ] && [ -z "$AUTONOMY_TARGET" ] && exit 0

# Create token directory
mkdir -p "$TOKEN_DIR"

# Clean up expired tokens (>60 seconds old)
NOW=$(date +%s)
for old_token in "$TOKEN_DIR"/*; do
    [ -f "$old_token" ] || continue
    TOKEN_TS=$(jq -r '.ts // 0' "$old_token" 2>/dev/null) || TOKEN_TS=0
    if [ $((NOW - TOKEN_TS)) -ge 60 ]; then
        rm -f "$old_token"
    fi
done

# Generate nonce
NONCE=$(openssl rand -hex 16 2>/dev/null || head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')

# Write phase token
if [ -n "$TARGET" ]; then
    jq -n --arg target "$TARGET" --argjson ts "$NOW" --arg nonce "$NONCE" \
        '{"target": $target, "ts": $ts, "nonce": $nonce}' > "$TOKEN_DIR/$NONCE"
fi

# Write autonomy token (separate nonce)
if [ -n "$AUTONOMY_TARGET" ]; then
    ANONCE=$(openssl rand -hex 16 2>/dev/null || head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')
    jq -n --arg target "$AUTONOMY_TARGET" --argjson ts "$NOW" --arg nonce "$ANONCE" \
        '{"target": $target, "ts": $ts, "nonce": $nonce}' > "$TOKEN_DIR/$ANONCE"
fi

exit 0
```

- [ ] **Step 2: Make the script executable**

Run: `chmod +x plugin/scripts/user-phase-token.sh`

- [ ] **Step 3: Commit the hook script**

```bash
git add plugin/scripts/user-phase-token.sh
git commit -m "feat: add UserPromptSubmit hook for phase/autonomy token generation (BUG-3)"
```

---

### Task 4: BUG-3 — Add token authorization to `set_phase()` and `set_autonomy_level()`

**Files:**
- Modify: `plugin/scripts/workflow-state.sh`

- [ ] **Step 1: Write failing tests for token authorization**

Append to `tests/run-tests.sh`, in a new test section:

```bash
# ============================================================
# TEST SUITE: BUG-3 — Phase token authorization
# ============================================================
echo ""
echo "=== BUG-3: Phase token authorization ==="

# Test: set_phase blocked without token (when WF_SKIP_AUTH is unset)
setup_test_project
# First create state via authorized path
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
# Now try to change phase with auth enforced
OUTPUT=$(run_with_auth set_phase "review" 2>&1) || true
assert_contains "$OUTPUT" "BLOCKED" "set_phase blocked without token when auth enforced"
# Phase should not have changed
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_phase)
assert_eq "implement" "$RESULT" "phase unchanged after blocked set_phase"

# Test: set_phase allowed with valid token
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
# Create a valid token
TOKEN_DIR="$TEST_DIR/.claude/plugin-data/.phase-tokens"
mkdir -p "$TOKEN_DIR"
NOW=$(date +%s)
NONCE="test-token-123"
jq -n --arg target "review" --argjson ts "$NOW" --arg nonce "$NONCE" \
    '{"target": $target, "ts": $ts, "nonce": $nonce}' > "$TOKEN_DIR/$NONCE"
export CLAUDE_PLUGIN_DATA="$TEST_DIR/.claude/plugin-data"
run_with_auth set_phase "review"
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_phase)
assert_eq "review" "$RESULT" "set_phase allowed with valid token"
# Token should be consumed
assert_file_not_exists "$TOKEN_DIR/$NONCE" "token consumed after use"

# Test: second set_phase blocked after token consumed
OUTPUT=$(run_with_auth set_phase "review" 2>&1) || true
assert_contains "$OUTPUT" "BLOCKED" "second set_phase blocked after token consumed"

# Test: set_phase blocked with expired token (>60s)
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
TOKEN_DIR="$TEST_DIR/.claude/plugin-data/.phase-tokens"
mkdir -p "$TOKEN_DIR"
EXPIRED_TS=$(($(date +%s) - 120))
jq -n --arg target "review" --argjson ts "$EXPIRED_TS" --arg nonce "expired-token" \
    '{"target": $target, "ts": $ts, "nonce": $nonce}' > "$TOKEN_DIR/expired-token"
export CLAUDE_PLUGIN_DATA="$TEST_DIR/.claude/plugin-data"
OUTPUT=$(run_with_auth set_phase "review" 2>&1) || true
assert_contains "$OUTPUT" "BLOCKED" "set_phase blocked with expired token"

# Test: forward auto-transition allowed without token when autonomy=auto
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

# Test: set_autonomy_level blocked without token (when WF_SKIP_AUTH is unset)
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_autonomy_level "ask"
OUTPUT=$(run_with_auth set_autonomy_level "auto" 2>&1) || true
assert_contains "$OUTPUT" "BLOCKED" "set_autonomy_level blocked without token"

# Test: set_autonomy_level allowed with valid autonomy token
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
TOKEN_DIR="$TEST_DIR/.claude/plugin-data/.phase-tokens"
mkdir -p "$TOKEN_DIR"
NOW=$(date +%s)
jq -n --arg target "autonomy:auto" --argjson ts "$NOW" --arg nonce "auto-token" \
    '{"target": $target, "ts": $ts, "nonce": $nonce}' > "$TOKEN_DIR/auto-token"
export CLAUDE_PLUGIN_DATA="$TEST_DIR/.claude/plugin-data"
run_with_auth set_autonomy_level "auto"
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_autonomy_level)
assert_eq "auto" "$RESULT" "set_autonomy_level allowed with valid autonomy token"
assert_file_not_exists "$TOKEN_DIR/auto-token" "autonomy token consumed after use"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/run-tests.sh 2>&1 | tail -30`
Expected: New BUG-3 tests fail (no token auth exists yet).

- [ ] **Step 3: Add `WF_SKIP_AUTH=1` to `setup_test_project` and `run_with_auth` helper**

In `tests/run-tests.sh`, find the `setup_test_project()` function (around line 111) and add `export WF_SKIP_AUTH=1` after `export CLAUDE_PROJECT_DIR="$TEST_DIR"`. Also add a `run_with_auth` helper right after `setup_test_project`:

```bash
setup_test_project() {
    rm -rf "$TEST_DIR"
    TEST_DIR=$(mktemp -d)
    mkdir -p "$TEST_DIR/.claude/hooks" "$TEST_DIR/.claude/state" "$TEST_DIR/.claude/commands"
    cp "$HOOKS_DIR/workflow-state.sh" "$TEST_DIR/.claude/hooks/"
    cp "$HOOKS_DIR/workflow-cmd.sh" "$TEST_DIR/.claude/hooks/"
    cp "$HOOKS_DIR/workflow-gate.sh" "$TEST_DIR/.claude/hooks/"
    cp "$HOOKS_DIR/bash-write-guard.sh" "$TEST_DIR/.claude/hooks/"
    # Set CLAUDE_PROJECT_DIR for hooks
    export CLAUDE_PROJECT_DIR="$TEST_DIR"
    # Skip token auth for existing tests (BUG-3 tests explicitly unset this via run_with_auth)
    export WF_SKIP_AUTH=1
}

# Run a workflow-state.sh function with auth enforcement enabled (no WF_SKIP_AUTH bypass).
# Uses a subshell so the unset doesn't leak into the parent environment.
# Usage: run_with_auth set_phase "review"
#        run_with_auth set_autonomy_level "auto"
run_with_auth() {
    (unset WF_SKIP_AUTH; export CLAUDE_PLUGIN_DATA="${CLAUDE_PLUGIN_DATA:-$TEST_DIR/.claude/plugin-data}"; source "$TEST_DIR/.claude/hooks/workflow-state.sh" && "$@")
}
```

- [ ] **Step 4: Add `_phase_ordinal()` helper to `workflow-state.sh`**

In `plugin/scripts/workflow-state.sh`, add this function right before the `get_phase()` function (find `get_phase()` by name — line numbers will have shifted after Task 2 modifications):

```bash
# Phase ordinal for forward-only auto-transition enforcement
_phase_ordinal() {
    case "$1" in
        off)       echo 0 ;;
        define)    echo 1 ;;
        discuss)   echo 2 ;;
        implement) echo 3 ;;
        review)    echo 4 ;;
        complete)  echo 5 ;;
        *)         echo 0 ;;
    esac
}

# Check for a valid one-time phase token. Consumes the token on success.
# Returns 0 if authorized, 1 if blocked.
_check_phase_token() {
    local target_phase="$1"
    local token_dir="${CLAUDE_PLUGIN_DATA:-${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}/.claude/plugin-data}/.phase-tokens"
    [ -d "$token_dir" ] || return 1
    local now
    now=$(date +%s)
    for token_file in "$token_dir"/*; do
        [ -f "$token_file" ] || continue
        local target ts
        target=$(jq -r '.target // ""' "$token_file" 2>/dev/null) || continue
        ts=$(jq -r '.ts // 0' "$token_file" 2>/dev/null) || continue
        if [ "$target" = "$target_phase" ] && [ $((now - ts)) -lt 60 ]; then
            rm -f "$token_file"
            return 0
        fi
    done
    return 1
}

# Check for a valid one-time autonomy token. Consumes the token on success.
# Returns 0 if authorized, 1 if blocked.
_check_autonomy_token() {
    local level="$1"
    _check_phase_token "autonomy:$level"
}
```

- [ ] **Step 5: Add token authorization to `set_phase()`**

In `plugin/scripts/workflow-state.sh`, in the `set_phase()` function, add the authorization check after the phase validation `case` block and before `mkdir -p "$STATE_DIR"` (find these by text — line numbers will have shifted after earlier steps):

Insert between the validation case and `mkdir -p "$STATE_DIR"`:

```bash
    # Authorization: require token or forward-only auto-transition
    # WF_SKIP_AUTH is test-only — never set in production
    if [ "${WF_SKIP_AUTH:-}" != "1" ]; then
        local authorized=false

        # Check 1: Valid one-time token
        if _check_phase_token "$new_phase"; then
            authorized=true
        fi

        # Check 2: Forward-only auto-transition (no token needed)
        if [ "$authorized" = false ] && [ -f "$STATE_FILE" ]; then
            local current_autonomy
            current_autonomy=$(get_autonomy_level)
            if [ "$current_autonomy" = "auto" ]; then
                local current_ordinal new_ordinal
                current_ordinal=$(_phase_ordinal "$(get_phase)")
                new_ordinal=$(_phase_ordinal "$new_phase")
                if [ "$new_ordinal" -gt "$current_ordinal" ] && [ "$new_phase" != "off" ]; then
                    authorized=true
                fi
            fi
        fi

        if [ "$authorized" = false ]; then
            echo "BLOCKED: Phase transition to '$new_phase' requires user authorization. Only the user can change the workflow phase." >&2
            return 1
        fi
    fi
```

- [ ] **Step 6: Add token authorization to `set_autonomy_level()`**

In `plugin/scripts/workflow-state.sh`, in the `set_autonomy_level()` function, add the authorization check after the validation case block and before the state file existence check:

Insert after the validation case and before `if [ ! -f "$STATE_FILE" ]; then`:

```bash
    # Authorization: require token from UserPromptSubmit hook
    # WF_SKIP_AUTH is test-only — never set in production
    if [ "${WF_SKIP_AUTH:-}" != "1" ]; then
        if ! _check_autonomy_token "$level"; then
            echo "BLOCKED: Autonomy level change requires user authorization. Use /autonomy $level." >&2
            return 1
        fi
    fi
```

- [ ] **Step 7: Run all tests**

Run: `bash tests/run-tests.sh 2>&1 | tail -30`
Expected: ALL tests pass — existing tests use `WF_SKIP_AUTH=1` (from setup_test_project), new BUG-3 tests explicitly unset it to test authorization.

- [ ] **Step 8: Commit token authorization**

```bash
git add plugin/scripts/workflow-state.sh tests/run-tests.sh
git commit -m "feat: add token authorization to set_phase and set_autonomy_level (BUG-3)"
```

---

### Task 5: BUG-3 — Register hook in `hooks.json`

**Files:**
- Modify: `plugin/hooks/hooks.json`

- [ ] **Step 1: Add UserPromptSubmit entry to `hooks.json`**

In `plugin/hooks/hooks.json`, add the UserPromptSubmit block after the `"SessionStart"` entry and before the `"PreToolUse"` entry. The new entry:

```json
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/user-phase-token.sh",
            "timeout": 5
          }
        ]
      }
    ],
```

- [ ] **Step 2: Validate JSON syntax**

Run: `jq . plugin/hooks/hooks.json > /dev/null && echo "Valid JSON"`
Expected: "Valid JSON"

- [ ] **Step 3: Run all tests**

Run: `bash tests/run-tests.sh 2>&1 | tail -10`
Expected: All tests pass.

- [ ] **Step 4: Commit hook registration**

```bash
git add plugin/hooks/hooks.json
git commit -m "feat: register UserPromptSubmit hook for phase token generation (BUG-3)"
```

---

### Task 6: Integration test — verify BUG-3 end-to-end token flow

**Files:**
- Modify: `tests/run-tests.sh` (add integration tests)

- [ ] **Step 1: Write integration test for token generation + consumption**

Append to `tests/run-tests.sh`:

```bash
# ============================================================
# TEST SUITE: BUG-3 — Integration: token hook + state functions
# ============================================================
echo ""
echo "=== BUG-3: Integration — token hook + state ==="

# Test: user-phase-token.sh generates token for /review prompt
setup_test_project
export CLAUDE_PLUGIN_DATA="$TEST_DIR/.claude/plugin-data"
echo '{"prompt": "/review"}' | bash "$REPO_DIR/plugin/scripts/user-phase-token.sh"
TOKEN_COUNT=$(ls "$TEST_DIR/.claude/plugin-data/.phase-tokens/" 2>/dev/null | wc -l | tr -d ' ')
assert_eq "1" "$TOKEN_COUNT" "hook generates exactly 1 token for /review"
# Check token content
TOKEN_FILE=$(ls "$TEST_DIR/.claude/plugin-data/.phase-tokens/"* 2>/dev/null | head -1)
TOKEN_TARGET=$(jq -r '.target' "$TOKEN_FILE")
assert_eq "review" "$TOKEN_TARGET" "token target is 'review'"

# Test: user-phase-token.sh generates token for /autonomy auto prompt
rm -rf "$TEST_DIR/.claude/plugin-data/.phase-tokens"
echo '{"prompt": "/autonomy auto"}' | bash "$REPO_DIR/plugin/scripts/user-phase-token.sh"
TOKEN_COUNT=$(ls "$TEST_DIR/.claude/plugin-data/.phase-tokens/" 2>/dev/null | wc -l | tr -d ' ')
assert_eq "1" "$TOKEN_COUNT" "hook generates exactly 1 token for /autonomy auto"
TOKEN_FILE=$(ls "$TEST_DIR/.claude/plugin-data/.phase-tokens/"* 2>/dev/null | head -1)
TOKEN_TARGET=$(jq -r '.target' "$TOKEN_FILE")
assert_eq "autonomy:auto" "$TOKEN_TARGET" "token target is 'autonomy:auto'"

# Test: user-phase-token.sh generates no token for non-phase prompt
rm -rf "$TEST_DIR/.claude/plugin-data/.phase-tokens"
echo '{"prompt": "help me write a function"}' | bash "$REPO_DIR/plugin/scripts/user-phase-token.sh"
TOKEN_COUNT=$(ls "$TEST_DIR/.claude/plugin-data/.phase-tokens/" 2>/dev/null | wc -l | tr -d ' ')
assert_eq "0" "$TOKEN_COUNT" "hook generates no token for non-phase prompt"

# Test: user-phase-token.sh cleans up expired tokens
mkdir -p "$TEST_DIR/.claude/plugin-data/.phase-tokens"
EXPIRED_TS=$(($(date +%s) - 120))
jq -n --arg target "old" --argjson ts "$EXPIRED_TS" --arg nonce "old" \
    '{"target": $target, "ts": $ts, "nonce": $nonce}' > "$TEST_DIR/.claude/plugin-data/.phase-tokens/old-token"
echo '{"prompt": "/review"}' | bash "$REPO_DIR/plugin/scripts/user-phase-token.sh"
assert_file_not_exists "$TEST_DIR/.claude/plugin-data/.phase-tokens/old-token" "hook cleans up expired tokens"

# Test: Full flow — hook generates token, set_phase consumes it
setup_test_project
export CLAUDE_PLUGIN_DATA="$TEST_DIR/.claude/plugin-data"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
# Generate token via hook
echo '{"prompt": "/review"}' | bash "$REPO_DIR/plugin/scripts/user-phase-token.sh"
# Use token via set_phase (with auth enabled)
run_with_auth set_phase "review"
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_phase)
assert_eq "review" "$RESULT" "full flow: hook token allows set_phase"

# Test: Full flow — autonomy token
setup_test_project
export CLAUDE_PLUGIN_DATA="$TEST_DIR/.claude/plugin-data"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
echo '{"prompt": "/autonomy auto"}' | bash "$REPO_DIR/plugin/scripts/user-phase-token.sh"
run_with_auth set_autonomy_level "auto"
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_autonomy_level)
assert_eq "auto" "$RESULT" "full flow: hook token allows set_autonomy_level"

# Test: escalation attack — cannot set autonomy to auto without token, so forward-transition defense holds
setup_test_project
export CLAUDE_PLUGIN_DATA="$TEST_DIR/.claude/plugin-data"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
# Attacker tries to escalate autonomy without token
run_with_auth set_autonomy_level "auto" 2>/dev/null || true
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_autonomy_level)
assert_eq "ask" "$RESULT" "escalation attack: autonomy stays at ask without token"
# Forward transition should also be blocked (still in ask mode, no token)
OUTPUT=$(run_with_auth set_phase "review" 2>&1) || true
assert_contains "$OUTPUT" "BLOCKED" "escalation attack: forward transition blocked when autonomy escalation failed"

# Test: user-phase-token.sh handles /discuss with arguments
rm -rf "$TEST_DIR/.claude/plugin-data/.phase-tokens"
echo '{"prompt": "/discuss we need to fix these bugs"}' | bash "$REPO_DIR/plugin/scripts/user-phase-token.sh"
TOKEN_COUNT=$(ls "$TEST_DIR/.claude/plugin-data/.phase-tokens/" 2>/dev/null | wc -l | tr -d ' ')
assert_eq "1" "$TOKEN_COUNT" "hook generates token for /discuss with arguments"
TOKEN_FILE=$(ls "$TEST_DIR/.claude/plugin-data/.phase-tokens/"* 2>/dev/null | head -1)
TOKEN_TARGET=$(jq -r '.target' "$TOKEN_FILE")
assert_eq "discuss" "$TOKEN_TARGET" "token target is 'discuss' even with arguments"
```

- [ ] **Step 2: Run all tests**

Run: `bash tests/run-tests.sh 2>&1 | tail -30`
Expected: All tests pass.

- [ ] **Step 3: Commit integration tests**

```bash
git add tests/run-tests.sh
git commit -m "test: add integration tests for BUG-3 token flow"
```

---

### Task 7: Final verification

- [ ] **Step 1: Run the full test suite**

Run: `bash tests/run-tests.sh`
Expected: All tests pass, 0 failures.

- [ ] **Step 2: Verify no untracked files left behind**

Run: `git status`
Expected: Clean working tree, all changes committed.

- [ ] **Step 3: Verify spec and plan are committed**

Run: `git log --oneline -10`
Expected: See commits for BUG-2 fix, BUG-1 fix, BUG-3 hook script, BUG-3 token auth, BUG-3 hook registration, and integration tests.
