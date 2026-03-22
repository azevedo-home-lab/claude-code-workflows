# Autonomy Levels Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add three selectable autonomy levels (▶ supervised, ▶▶ semi-auto, ▶▶▶ unattended) to the Workflow Manager, enforced by hooks and displayed in the status line.

**Architecture:** New `autonomy_level` field in `workflow.json` state, read by existing PreToolUse hooks (`workflow-gate.sh`, `bash-write-guard.sh`) and PostToolUse coaching (`post-tool-navigator.sh`). Status line reads the level from the same state file. User sets level via `/autonomy` command. Hooks are the single source of truth for enforcement; CC permission modes are a best-effort convenience layer.

**Tech Stack:** Bash, Python 3 (inline in hooks), jq (statusline), Claude Code hooks API

**Spec:** `docs/superpowers/specs/2026-03-22-autonomy-levels-design.md`

---

### Task 1: State Management — `get_autonomy_level` and `set_autonomy_level`

**Files:**
- Modify: `.claude/hooks/workflow-state.sh:26-107` (add functions, modify `set_phase`)
- Test: `tests/run-tests.sh` (add to workflow-state.sh suite, after line ~240)

- [ ] **Step 1: Write failing tests for `get_autonomy_level` and `set_autonomy_level`**

Add these tests after the existing workflow-state.sh test suite (after the `get_review_field returns empty when no file` test around line 240):

```bash
# --- Autonomy level management ---

# Test: get_autonomy_level returns default 2 when no state file
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_autonomy_level)
assert_eq "2" "$RESULT" "get_autonomy_level defaults to 2 when no state file"

# Test: get_autonomy_level returns default 2 for old-format workflow.json (backward compat)
setup_test_project
# Create a workflow.json WITHOUT autonomy_level (simulates pre-feature state file)
echo '{"phase": "implement", "message_shown": true, "active_skill": "", "decision_record": "", "coaching": {"tool_calls_since_agent": 0, "layer2_fired": []}, "updated": "2026-03-22T00:00:00Z"}' > "$TEST_DIR/.claude/state/workflow.json"
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_autonomy_level)
assert_eq "2" "$RESULT" "get_autonomy_level defaults to 2 for old-format state file (backward compat)"

# Test: set_autonomy_level accepts valid values
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_autonomy_level 1
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_autonomy_level)
assert_eq "1" "$RESULT" "set_autonomy_level sets level to 1"

source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_autonomy_level 2
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_autonomy_level)
assert_eq "2" "$RESULT" "set_autonomy_level sets level to 2"

source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_autonomy_level 3
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_autonomy_level)
assert_eq "3" "$RESULT" "set_autonomy_level sets level to 3"

# Test: set_autonomy_level rejects invalid values
OUTPUT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_autonomy_level 0 2>&1)
assert_contains "$OUTPUT" "ERROR" "set_autonomy_level rejects 0"

OUTPUT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_autonomy_level 4 2>&1)
assert_contains "$OUTPUT" "ERROR" "set_autonomy_level rejects 4"

OUTPUT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_autonomy_level abc 2>&1)
assert_contains "$OUTPUT" "ERROR" "set_autonomy_level rejects non-numeric input"

# Test: autonomy_level preserved across set_phase transitions
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_autonomy_level 3
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "review"
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_autonomy_level)
assert_eq "3" "$RESULT" "autonomy_level preserved across phase transitions"

# Test: set_phase from OFF initializes autonomy_level to 2
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "off"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "define"
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_autonomy_level)
assert_eq "2" "$RESULT" "set_phase from OFF initializes autonomy_level to 2"

# Test: set_phase("off") clears autonomy_level
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_autonomy_level 3
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "off"
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_autonomy_level)
assert_eq "2" "$RESULT" "set_phase off clears autonomy_level (returns default 2)"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/run-tests.sh 2>&1 | tail -20`
Expected: FAIL — `get_autonomy_level` and `set_autonomy_level` not defined

- [ ] **Step 3: Implement `get_autonomy_level` function**

Add after `get_phase()` (after line 42) in `workflow-state.sh`:

```bash
get_autonomy_level() {
    if [ ! -f "$STATE_FILE" ]; then
        echo "2"
        return
    fi
    local level
    level=$(python3 -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        d = json.load(f)
    print(d.get('autonomy_level', 2))
except Exception:
    print(2)
" "$STATE_FILE" 2>/dev/null)
    echo "${level:-2}"
}
```

- [ ] **Step 4: Implement `set_autonomy_level` function**

Add after `get_autonomy_level()`:

```bash
set_autonomy_level() {
    local level="$1"
    case "$level" in
        1|2|3) ;;
        *) echo "ERROR: Invalid autonomy level: $level (valid: 1, 2, 3)" >&2; return 1 ;;
    esac
    if [ ! -f "$STATE_FILE" ]; then
        return
    fi
    local ts
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    python3 -c "
import json, sys
level, ts, filepath = int(sys.argv[1]), sys.argv[2], sys.argv[3]
with open(filepath, 'r') as f:
    d = json.load(f)
d['autonomy_level'] = level
d['updated'] = ts
with open(filepath, 'w') as f:
    json.dump(d, f, indent=2)
    f.write('\n')
" "$level" "$ts" "$STATE_FILE"
}
```

- [ ] **Step 5: Modify `set_phase` to preserve and initialize `autonomy_level`**

In `set_phase()`, add to the "Read existing state" block (after line 65):

```bash
    local existing_autonomy_level=""
    if [ -f "$STATE_FILE" ]; then
        # ... existing reads ...
        existing_autonomy_level=$(get_autonomy_level)
    fi
```

In the "If new phase is off" block (after line 71), add:

```bash
        existing_autonomy_level=""
```

Before the Python block, add initialization logic:

```bash
    # Initialize autonomy_level to 2 when transitioning from OFF to active phase
    if [ "$current_phase" = "off" ] && [ "$new_phase" != "off" ] && [ -z "$existing_autonomy_level" ]; then
        existing_autonomy_level="2"
    fi
```

In the Python block, pass `existing_autonomy_level` as a new argument and include it in the state dict:

```python
autonomy_level = sys.argv[7]

state = {
    'phase': new_phase,
    'message_shown': False,
    'active_skill': active_skill,
    'decision_record': decision_record,
    'coaching': {
        'tool_calls_since_agent': 0,
        'layer2_fired': []
    },
    'updated': ts
}

# Include autonomy_level if set (not empty string)
if autonomy_level:
    state['autonomy_level'] = int(autonomy_level)
```

And update the Python call to pass the new argument:

```bash
" "$new_phase" "$current_phase" "$existing_active_skill" "$existing_decision_record" "$ts" "$STATE_FILE" "$existing_autonomy_level"
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `bash tests/run-tests.sh 2>&1 | tail -20`
Expected: All new autonomy level tests PASS

- [ ] **Step 7: Commit**

```bash
git add .claude/hooks/workflow-state.sh tests/run-tests.sh
git commit -m "feat: add autonomy level state management (get/set/preserve/initialize)"
```

---

### Task 2: Hook Enforcement — `workflow-gate.sh`

**Files:**
- Modify: `.claude/hooks/workflow-gate.sh:20-30` (add autonomy level check)
- Test: `tests/run-tests.sh` (add to workflow-gate.sh suite, after line ~337)

- [ ] **Step 1: Write failing tests**

Add after the existing workflow-gate.sh tests (after the path traversal tests around line 337):

```bash
# --- Autonomy level enforcement ---

# Test: Level 1 blocks Write in IMPLEMENT phase (normally allowed)
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_autonomy_level 1
OUTPUT=$(run_gate "/project/src/main.py")
assert_contains "$OUTPUT" "deny" "Level 1 blocks Write in IMPLEMENT phase"

# Test: Level 1 denial message mentions /autonomy
OUTPUT=$(run_gate "/project/src/main.py")
assert_contains "$OUTPUT" "/autonomy" "Level 1 deny message mentions /autonomy command"

# Test: Level 1 does NOT block writes when phase is OFF
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "off"
# Note: autonomy_level cleared by set_phase("off"), so we need to write it manually for this edge case
python3 -c "
import json
with open('$TEST_DIR/.claude/state/workflow.json', 'r') as f:
    d = json.load(f)
d['autonomy_level'] = 1
with open('$TEST_DIR/.claude/state/workflow.json', 'w') as f:
    json.dump(d, f, indent=2)
"
OUTPUT=$(run_gate "/project/src/main.py")
assert_not_contains "$OUTPUT" "deny" "Level 1 does NOT block writes when phase is OFF"

# Test: Level 2 allows writes in IMPLEMENT (current behavior)
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_autonomy_level 2
OUTPUT=$(run_gate "/project/src/main.py")
assert_not_contains "$OUTPUT" "deny" "Level 2 allows writes in IMPLEMENT"

# Test: Level 3 allows writes in IMPLEMENT (current behavior)
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_autonomy_level 3
OUTPUT=$(run_gate "/project/src/main.py")
assert_not_contains "$OUTPUT" "deny" "Level 3 allows writes in IMPLEMENT"

# Test: Level 2 still blocks writes in DISCUSS (phase gate preserved)
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "discuss"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_autonomy_level 2
OUTPUT=$(run_gate "/project/src/main.py")
assert_contains "$OUTPUT" "deny" "Level 2 blocks writes in DISCUSS (phase gate)"

# Test: Level 3 still blocks writes in DISCUSS (phase gate preserved)
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "discuss"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_autonomy_level 3
OUTPUT=$(run_gate "/project/src/main.py")
assert_contains "$OUTPUT" "deny" "Level 3 blocks writes in DISCUSS (phase gate)"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/run-tests.sh 2>&1 | tail -20`
Expected: FAIL — Level 1 does not block writes in IMPLEMENT

- [ ] **Step 3: Restructure `workflow-gate.sh` for correct enforcement order**

**Critical:** The current code has `implement|review|off) exit 0 ;;` at line 28-30, which would bypass the autonomy check. We must separate OFF from implement/review and insert the autonomy check between them.

Replace lines 27-30:

```bash
# Allow everything in implement, review, and off phases
case "$PHASE" in
    implement|review|off) exit 0 ;;
esac
```

With:

```bash
# OFF phase: no enforcement
case "$PHASE" in
    off) exit 0 ;;
esac

# Autonomy Level 1: block ALL writes regardless of phase
AUTONOMY_LEVEL=$(get_autonomy_level)
if [ "$AUTONOMY_LEVEL" = "1" ]; then
    cat > /dev/null  # consume stdin
    REASON="BLOCKED: ▶ Level 1 (supervised) — read-only mode. No file writes allowed. Run /autonomy 2 to enable writes."
    REASON="$REASON" python3 -c "
import json, os
output = {
    'hookSpecificOutput': {
        'hookEventName': 'PreToolUse',
        'permissionDecision': 'deny',
        'permissionDecisionReason': os.environ['REASON']
    }
}
print(json.dumps(output))
"
    exit 0
fi

# Allow everything in implement and review phases (Level 2/3 only reach here)
case "$PHASE" in
    implement|review) exit 0 ;;
esac
```

This ensures the enforcement order matches the spec:
1. No state file → exit 0 (line 21-23, unchanged)
2. Phase is OFF → exit 0
3. Autonomy level check (Level 1 blocks all)
4. implement/review → exit 0 (only Level 2/3 reach here)
5. Phase gate check (existing whitelist logic, unchanged)

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/run-tests.sh 2>&1 | tail -20`
Expected: All autonomy level gate tests PASS

- [ ] **Step 5: Commit**

```bash
git add .claude/hooks/workflow-gate.sh tests/run-tests.sh
git commit -m "feat: enforce autonomy Level 1 write blocking in workflow-gate hook"
```

---

### Task 3: Hook Enforcement — `bash-write-guard.sh`

**Files:**
- Modify: `.claude/hooks/bash-write-guard.sh:20-31` (add autonomy level check)
- Test: `tests/run-tests.sh` (add to bash-write-guard.sh suite)

- [ ] **Step 1: Write failing tests**

Add after the existing bash-write-guard.sh tests. Use the existing `run_bash_guard` helper pattern:

```bash
# --- Autonomy level enforcement ---

# Test: Level 1 blocks Bash write in IMPLEMENT phase
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_autonomy_level 1
OUTPUT=$(run_bash_guard 'echo "data" > output.txt')
assert_contains "$OUTPUT" "deny" "Level 1 blocks Bash write in IMPLEMENT phase"

# Test: Level 1 denial message mentions /autonomy
assert_contains "$OUTPUT" "/autonomy" "Level 1 bash deny message mentions /autonomy"

# Test: Level 2 allows Bash write in IMPLEMENT
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_autonomy_level 2
OUTPUT=$(run_bash_guard 'echo "data" > output.txt')
assert_not_contains "$OUTPUT" "deny" "Level 2 allows Bash write in IMPLEMENT"

# Test: Level 3 allows Bash write in IMPLEMENT
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_autonomy_level 3
OUTPUT=$(run_bash_guard 'echo "data" > output.txt')
assert_not_contains "$OUTPUT" "deny" "Level 3 allows Bash write in IMPLEMENT"

# Test: Level 2 still blocks Bash write in DISCUSS (phase gate preserved)
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "discuss"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_autonomy_level 2
OUTPUT=$(run_bash_guard 'echo "data" > output.txt')
assert_contains "$OUTPUT" "deny" "Level 2 blocks Bash write in DISCUSS (phase gate)"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/run-tests.sh 2>&1 | tail -20`
Expected: FAIL — Level 1 does not block Bash writes in IMPLEMENT

- [ ] **Step 3: Restructure `bash-write-guard.sh` for correct enforcement order**

**Critical:** Same issue as workflow-gate — `implement|review|off) exit 0 ;;` at line 28-30 would bypass the autonomy check. Additionally, `WRITE_PATTERN` (line 75) must be moved above the autonomy check since Level 1 needs it.

**Step 3a: Move `WRITE_PATTERN` definition.** Move the `WRITE_PATTERN='...'` variable (line 75) and the safe-redirect strip logic comment (lines 77-79) to just after the `source workflow-state.sh` line (after line 19), before any phase checks. This makes it available to both the autonomy block and the existing phase-gate block.

**Step 3b: Restructure the phase/autonomy checks.** Replace lines 27-31:

```bash
# Allow everything in implement, review, and off phases
case "$PHASE" in
    implement|review|off) exit 0 ;;
esac
```

With:

```bash
# OFF phase: no enforcement
case "$PHASE" in
    off) exit 0 ;;
esac

# Autonomy Level 1: block ALL Bash write commands regardless of phase
AUTONOMY_LEVEL=$(get_autonomy_level)
if [ "$AUTONOMY_LEVEL" = "1" ]; then
    INPUT=$(cat)
    COMMAND=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('command',''))" 2>/dev/null || echo "")
    if [ -z "$COMMAND" ]; then exit 0; fi

    # Allow workflow state commands
    if echo "$COMMAND" | grep -qE '^[[:space:]]*(source[[:space:]]|\.[ /]).*workflow-state\.sh'; then
        if ! echo "$COMMAND" | grep -qE '(&&|\|\||;|\|)'; then
            exit 0
        fi
    fi

    CLEAN_CMD=$(echo "$COMMAND" | sed -E 's/[0-9]+>\/dev\/null//g; s/[0-9]*>&[0-9]+//g')
    if echo "$CLEAN_CMD" | grep -qE "$WRITE_PATTERN"; then
        REASON="BLOCKED: ▶ Level 1 (supervised) — read-only mode. No Bash write operations allowed. Run /autonomy 2 to enable writes."
        REASON="$REASON" python3 -c "
import json, os
output = {
    'hookSpecificOutput': {
        'hookEventName': 'PreToolUse',
        'permissionDecision': 'deny',
        'permissionDecisionReason': os.environ['REASON']
    }
}
print(json.dumps(output))
"
        exit 0
    fi
    # Read-only Bash commands allowed at Level 1
    exit 0
fi

# Allow everything in implement and review phases (Level 2/3 only reach here)
case "$PHASE" in
    implement|review) exit 0 ;;
esac
```

This ensures `WRITE_PATTERN` is defined before the autonomy block uses it, and the enforcement order matches the spec.

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/run-tests.sh 2>&1 | tail -20`
Expected: All autonomy level bash-write-guard tests PASS

- [ ] **Step 5: Commit**

```bash
git add .claude/hooks/bash-write-guard.sh tests/run-tests.sh
git commit -m "feat: enforce autonomy Level 1 Bash write blocking in bash-write-guard hook"
```

---

### Task 4: Coaching — Level 3 Auto-Transition Guidance in `post-tool-navigator.sh`

**Files:**
- Modify: `.claude/hooks/post-tool-navigator.sh:43-87` (modify Layer 1 messages)
- Test: `tests/run-tests.sh` (add to post-tool-navigator.sh suite)

- [ ] **Step 1: Write failing tests**

Add to the post-tool-navigator.sh test suite. The existing tests use a pattern like setting up state then running the hook with mock input:

```bash
# --- Autonomy level coaching ---

# Test: Level 3 coaching includes auto-transition guidance
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_autonomy_level 3
# Reset message_shown to trigger Layer 1
python3 -c "
import json
with open('$TEST_DIR/.claude/state/workflow.json', 'r') as f:
    d = json.load(f)
d['message_shown'] = False
with open('$TEST_DIR/.claude/state/workflow.json', 'w') as f:
    json.dump(d, f, indent=2)
"
OUTPUT=$(echo '{"tool_name":"Write","tool_input":{"file_path":"/project/src/main.py"}}' | "$TEST_DIR/.claude/hooks/post-tool-navigator.sh" 2>&1 || true)
assert_contains "$OUTPUT" "Level 3" "Level 3 coaching mentions Level 3 in phase entry"
assert_contains "$OUTPUT" "proceed" "Level 3 coaching includes auto-transition guidance"

# Test: Level 2 coaching does NOT include auto-transition guidance
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_autonomy_level 2
python3 -c "
import json
with open('$TEST_DIR/.claude/state/workflow.json', 'r') as f:
    d = json.load(f)
d['message_shown'] = False
with open('$TEST_DIR/.claude/state/workflow.json', 'w') as f:
    json.dump(d, f, indent=2)
"
OUTPUT=$(echo '{"tool_name":"Write","tool_input":{"file_path":"/project/src/main.py"}}' | "$TEST_DIR/.claude/hooks/post-tool-navigator.sh" 2>&1 || true)
assert_not_contains "$OUTPUT" "Level 3" "Level 2 coaching does not mention Level 3"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/run-tests.sh 2>&1 | tail -20`
Expected: FAIL — Level 3 coaching does not include auto-transition text

- [ ] **Step 3: Add autonomy-aware coaching to Layer 1 messages**

In `post-tool-navigator.sh`, after the Layer 1 phase-entry `case` block (after line 85, before `set_message_shown`), add:

```bash
        # Append Level 3 auto-transition guidance if applicable
        AUTONOMY_LEVEL=$(get_autonomy_level)
        if [ "$AUTONOMY_LEVEL" = "3" ] && [ -n "$MESSAGES" ]; then
            MESSAGES="$MESSAGES
▶▶▶ Level 3 active — when this phase's work is complete, proceed to the next phase without waiting for user confirmation. Exceptions: stop for user input in DISCUSS/DEFINE, stop before git push, stop if review finds blocking issues."
        fi
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/run-tests.sh 2>&1 | tail -20`
Expected: All coaching autonomy tests PASS

- [ ] **Step 5: Commit**

```bash
git add .claude/hooks/post-tool-navigator.sh tests/run-tests.sh
git commit -m "feat: add Level 3 auto-transition coaching guidance to phase entry messages"
```

---

### Task 5: Status Line — Display Autonomy Symbol

**Files:**
- Modify: `statusline/statusline.sh:99-123` (add autonomy symbol before phase)
- Test: `tests/run-tests.sh` (add to statusline.sh suite)

- [ ] **Step 1: Write failing tests**

Add after the existing statusline tests (after the COMPLETE phase test around line 877):

```bash
# --- Autonomy level symbols ---

# Test: Level 1 renders ▶ before phase
SL_AUTO1_DIR=$(mktemp -d)
mkdir -p "$SL_AUTO1_DIR/.claude/state" "$SL_AUTO1_DIR/.claude/hooks"
echo '{"phase": "implement", "autonomy_level": 1, "message_shown": false, "active_skill": ""}' > "$SL_AUTO1_DIR/.claude/state/workflow.json"
touch "$SL_AUTO1_DIR/.claude/hooks/workflow-gate.sh"
OUTPUT=$(run_statusline "{\"model\":{\"display_name\":\"Opus\"},\"context_window\":{\"used_percentage\":10,\"context_window_size\":200000,\"current_usage\":{\"input_tokens\":20000,\"cache_creation_input_tokens\":0,\"cache_read_input_tokens\":0}},\"cwd\":\"$SL_AUTO1_DIR\"}")
assert_contains "$OUTPUT" "▶ " "statusline shows ▶ for Level 1"
assert_contains "$OUTPUT" "IMPLEMENT" "statusline still shows phase at Level 1"
rm -rf "$SL_AUTO1_DIR"

# Test: Level 2 renders ▶▶ before phase
SL_AUTO2_DIR=$(mktemp -d)
mkdir -p "$SL_AUTO2_DIR/.claude/state" "$SL_AUTO2_DIR/.claude/hooks"
echo '{"phase": "discuss", "autonomy_level": 2, "message_shown": false, "active_skill": ""}' > "$SL_AUTO2_DIR/.claude/state/workflow.json"
touch "$SL_AUTO2_DIR/.claude/hooks/workflow-gate.sh"
OUTPUT=$(run_statusline "{\"model\":{\"display_name\":\"Opus\"},\"context_window\":{\"used_percentage\":10,\"context_window_size\":200000,\"current_usage\":{\"input_tokens\":20000,\"cache_creation_input_tokens\":0,\"cache_read_input_tokens\":0}},\"cwd\":\"$SL_AUTO2_DIR\"}")
assert_contains "$OUTPUT" "▶▶ " "statusline shows ▶▶ for Level 2"
rm -rf "$SL_AUTO2_DIR"

# Test: Level 3 renders ▶▶▶ before phase
SL_AUTO3_DIR=$(mktemp -d)
mkdir -p "$SL_AUTO3_DIR/.claude/state" "$SL_AUTO3_DIR/.claude/hooks"
echo '{"phase": "review", "autonomy_level": 3, "message_shown": false, "active_skill": ""}' > "$SL_AUTO3_DIR/.claude/state/workflow.json"
touch "$SL_AUTO3_DIR/.claude/hooks/workflow-gate.sh"
OUTPUT=$(run_statusline "{\"model\":{\"display_name\":\"Opus\"},\"context_window\":{\"used_percentage\":10,\"context_window_size\":200000,\"current_usage\":{\"input_tokens\":20000,\"cache_creation_input_tokens\":0,\"cache_read_input_tokens\":0}},\"cwd\":\"$SL_AUTO3_DIR\"}")
assert_contains "$OUTPUT" "▶▶▶ " "statusline shows ▶▶▶ for Level 3"
rm -rf "$SL_AUTO3_DIR"

# Test: No symbol when workflow is OFF
SL_AUTOOFF_DIR=$(mktemp -d)
mkdir -p "$SL_AUTOOFF_DIR/.claude/state" "$SL_AUTOOFF_DIR/.claude/hooks"
echo '{"phase": "off", "message_shown": false, "active_skill": ""}' > "$SL_AUTOOFF_DIR/.claude/state/workflow.json"
touch "$SL_AUTOOFF_DIR/.claude/hooks/workflow-gate.sh"
OUTPUT=$(run_statusline "{\"model\":{\"display_name\":\"Opus\"},\"context_window\":{\"used_percentage\":10,\"context_window_size\":200000,\"current_usage\":{\"input_tokens\":20000,\"cache_creation_input_tokens\":0,\"cache_read_input_tokens\":0}},\"cwd\":\"$SL_AUTOOFF_DIR\"}")
CLEAN_OUTPUT=$(echo "$OUTPUT" | sed 's/\x1b\[[0-9;]*m//g')
assert_not_contains "$CLEAN_OUTPUT" "▶" "statusline shows no autonomy symbol when OFF"
rm -rf "$SL_AUTOOFF_DIR"

# Test: No symbol when autonomy_level field absent
SL_AUTOABS_DIR=$(mktemp -d)
mkdir -p "$SL_AUTOABS_DIR/.claude/state" "$SL_AUTOABS_DIR/.claude/hooks"
echo '{"phase": "implement", "message_shown": false, "active_skill": ""}' > "$SL_AUTOABS_DIR/.claude/state/workflow.json"
touch "$SL_AUTOABS_DIR/.claude/hooks/workflow-gate.sh"
OUTPUT=$(run_statusline "{\"model\":{\"display_name\":\"Opus\"},\"context_window\":{\"used_percentage\":10,\"context_window_size\":200000,\"current_usage\":{\"input_tokens\":20000,\"cache_creation_input_tokens\":0,\"cache_read_input_tokens\":0}},\"cwd\":\"$SL_AUTOABS_DIR\"}")
CLEAN_OUTPUT=$(echo "$OUTPUT" | sed 's/\x1b\[[0-9;]*m//g')
assert_not_contains "$CLEAN_OUTPUT" "▶" "statusline shows no autonomy symbol when field absent"
rm -rf "$SL_AUTOABS_DIR"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/run-tests.sh 2>&1 | tail -20`
Expected: FAIL — no autonomy symbols in output

- [ ] **Step 3: Add autonomy symbol rendering to `statusline.sh`**

In `statusline.sh`, inside the `if [ -f "$WM_STATE_FILE" ]` block (after line 106, where `WM_PHASE` is extracted), add:

```bash
    WM_AUTONOMY=$(grep -o '"autonomy_level"[[:space:]]*:[[:space:]]*[0-9]*' "$WM_STATE_FILE" | grep -o '[0-9]*$')
```

Then modify the phase display section (lines 107-119). Before the phase `if/elif` chain, add the autonomy symbol:

```bash
    # Autonomy symbol (only when phase is not OFF and level is set)
    AUTONOMY_SYM=""
    if [ "$WM_PHASE" != "off" ] && [ -n "$WM_AUTONOMY" ]; then
      case "$WM_AUTONOMY" in
        1) AUTONOMY_SYM="▶ " ;;
        2) AUTONOMY_SYM="▶▶ " ;;
        3) AUTONOMY_SYM="▶▶▶ " ;;
      esac
    fi
```

Then prepend `$AUTONOMY_SYM` to each phase display. For example, change:

```bash
    elif [ "$WM_PHASE" = "implement" ]; then
      OUTPUT+=" ${GREEN}[IMPLEMENT]${RESET}"
```

to:

```bash
    elif [ "$WM_PHASE" = "implement" ]; then
      OUTPUT+=" ${GREEN}${AUTONOMY_SYM}[IMPLEMENT]${RESET}"
```

Apply the same `${AUTONOMY_SYM}` prefix to all phase displays (define, discuss, implement, review, complete). Do NOT add it to the OFF display.

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/run-tests.sh 2>&1 | tail -20`
Expected: All statusline autonomy tests PASS

- [ ] **Step 5: Commit**

```bash
git add statusline/statusline.sh tests/run-tests.sh
git commit -m "feat: display autonomy level symbol in status line before phase indicator"
```

---

### Task 6: Command — `/autonomy`

**Files:**
- Create: `.claude/commands/autonomy.md`

- [ ] **Step 1: Create the `/autonomy` command**

```markdown
# Autonomy Level

Set the Workflow Manager autonomy level. This controls how much independence Claude has during the workflow.

**Levels:**
- `1` (▶ Supervised): Read-only. Local research only, no file writes, no web access.
- `2` (▶▶ Semi-Auto): Writes allowed per phase rules. Stops at each phase transition for user approval.
- `3` (▶▶▶ Unattended): Full autonomy. Auto-transitions between phases, auto-commits. Stops only for user input in DISCUSS/DEFINE and before git push.

## Usage

```
/autonomy 1|2|3
```

## Execution

Run this to set the level:

```bash
WF_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}" && source "$WF_DIR/.claude/hooks/workflow-state.sh" && set_autonomy_level "$ARGUMENTS"
echo "Autonomy level set to $ARGUMENTS"
```

Then apply the corresponding behavior:

**If level is 1:** Enter plan mode by calling the `EnterPlanMode` tool. This blocks all write operations at the Claude Code level. Confirm: "▶ **Supervised** — read-only mode. I can research and explore but cannot modify files. Run `/autonomy 2` to enable writes."

**If level is 2:** If you are currently in plan mode, call `ExitPlanMode`. Confirm: "▶▶ **Semi-Auto** — writes enabled per phase rules. I'll propose phase transitions and wait for your approval."

**If level is 3:** If you are currently in plan mode, call `ExitPlanMode`. Confirm: "▶▶▶ **Unattended** — full autonomy. I'll auto-transition between phases and auto-commit. I'll stop only when I need your input or before git push. Note: ensure your `settings.local.json` includes Bash, WebFetch, WebSearch, and MCP tools in the allow list for fully unattended operation."

**Important:** Only the user can run this command. If you think a different level would be appropriate, suggest it: "This task would benefit from Level 3 — run `/autonomy 3` if you'd like to proceed unattended." Do NOT invoke this command yourself.
```

- [ ] **Step 2: Update `install.sh` and `uninstall.sh`**

Add `autonomy.md` to the list of command files copied by `install.sh` and removed by `uninstall.sh`. Find the section that copies command files (e.g., `define.md`, `discuss.md`, etc.) and add `autonomy.md` to the list.

- [ ] **Step 3: Verify the command file is valid**

Run: `cat .claude/commands/autonomy.md | head -5`
Expected: Shows the command header

- [ ] **Step 4: Commit**

```bash
git add .claude/commands/autonomy.md install.sh uninstall.sh
git commit -m "feat: add /autonomy command for setting workflow autonomy level"
```

---

### Task 7: Documentation Updates

**Files:**
- Modify: `docs/reference/hooks.md`
- Modify: `docs/reference/architecture.md`
- Modify: `docs/guides/statusline-guide.md`
- Modify: `README.md`

- [ ] **Step 1: Update `docs/reference/hooks.md`**

Add an "Autonomy Levels" section documenting:
- How autonomy level interacts with the hooks (check order: no state → OFF → autonomy → phase)
- Level 1 blocks all writes regardless of phase
- Level 2/3 fall through to existing phase-based logic
- The check is in both `workflow-gate.sh` and `bash-write-guard.sh`

- [ ] **Step 2: Update `docs/reference/architecture.md`**

Add autonomy levels as a system concept:
- Two orthogonal dimensions: phase (WHAT) and autonomy (HOW MUCH)
- Three levels with symbols
- Enforcement via hooks (truth) and CC modes (convenience)

- [ ] **Step 3: Update `docs/guides/statusline-guide.md`**

Document the autonomy symbols:
- `▶` = Level 1 Supervised
- `▶▶` = Level 2 Semi-Auto
- `▶▶▶` = Level 3 Unattended
- No symbol when workflow is OFF or field absent

- [ ] **Step 4: Update `README.md`**

Add autonomy levels to the feature overview. Brief mention with link to the statusline guide for details.

- [ ] **Step 5: Commit**

```bash
git add docs/reference/hooks.md docs/reference/architecture.md docs/guides/statusline-guide.md README.md
git commit -m "docs: add autonomy levels to hooks, architecture, statusline guide, and README"
```

---

### Task 8: Final Integration Test

- [ ] **Step 1: Run full test suite**

Run: `bash tests/run-tests.sh`
Expected: All tests pass (existing + new autonomy tests)

- [ ] **Step 2: Manual verification — status line**

Set up a workflow state with autonomy level 2 and verify the status line shows `▶▶ [PHASE]`:

```bash
WF_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}" && source "$WF_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement" && set_autonomy_level 2
cat .claude/state/workflow.json
```

Expected: JSON shows `"autonomy_level": 2` and `"phase": "implement"`

- [ ] **Step 3: Manual verification — hook enforcement**

Test Level 1 blocking in IMPLEMENT phase:

```bash
WF_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}" && source "$WF_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement" && set_autonomy_level 1
echo '{"tool_input":{"file_path":"/project/src/main.py"}}' | .claude/hooks/workflow-gate.sh
```

Expected: JSON with `"permissionDecision": "deny"` and message about Level 1

- [ ] **Step 4: Reset state and commit final**

```bash
WF_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}" && source "$WF_DIR/.claude/hooks/workflow-state.sh" && set_phase "off"
```
