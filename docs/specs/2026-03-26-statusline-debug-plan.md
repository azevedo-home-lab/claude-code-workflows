# Status Line Improvements & Debug Command — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add CC version to status line, fix context bar colors, and add `/wf:debug` command for hook visibility.

**Architecture:** Three independent changes bundled in one plan. Status line changes are purely in `statusline.sh`. Debug command adds a state field to `workflow-state.sh`, a command handler in `workflow-cmd.sh`, a command file `wf:debug.md`, and stderr output in three hook scripts. State preservation ensures debug flag persists across phase transitions and clears on OFF.

**Tech Stack:** Bash, jq, Claude Code hooks protocol

**Spec:** `docs/superpowers/specs/2026-03-26-statusline-debug-design.md`
**Decision record:** `docs/plans/2026-03-26-statusline-debug-decisions.md`

---

### Task 1: CC Version in Status Line

**Files:**
- Modify: `plugin/statusline/statusline.sh:14-24` (jq parse call)
- Modify: `plugin/statusline/statusline.sh:78-84` (output assembly)
- Test: `tests/run-tests.sh` (statusline test section, ~line 1488)

- [ ] **Step 1: Write the failing test**

Add to the statusline test section in `tests/run-tests.sh`, after the existing model name test (~line 1505):

```bash
# Test: statusline shows CC version
OUTPUT=$(run_statusline '{"version":"2.1.83","model":{"display_name":"Opus 4.6"},"context_window":{"used_percentage":25,"context_window_size":200000,"current_usage":{"input_tokens":50000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}},"cwd":"/tmp/test"}')
assert_contains "$OUTPUT" "CC 2.1.83" "statusline shows CC version"

# Test: statusline handles missing version field gracefully
OUTPUT=$(run_statusline '{"model":{"display_name":"Opus 4.6"},"context_window":{"used_percentage":25,"context_window_size":200000,"current_usage":{"input_tokens":50000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}},"cwd":"/tmp/test"}')
assert_contains "$OUTPUT" "CC ?" "statusline shows CC ? when version missing"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/run-tests.sh 2>&1 | grep -E '(PASS|FAIL).*CC (2\.1\.83|\?)'`
Expected: 2 FAIL lines

- [ ] **Step 3: Add version to jq parse call**

In `plugin/statusline/statusline.sh`, modify the jq parse call (line 14-24) to add `.version` as the first field:

```bash
IFS=$'\t' read -r CC_VERSION MODEL USED_PCT USED_TOKENS TOTAL_TOKENS CWD WORKTREE_NAME WORKTREE_BRANCH < <(
  echo "$DATA" | jq -r '[
    (.version // "?"),
    (.model.display_name // "?"),
    ((.context_window.used_percentage // 0) | floor | tostring),
    (((.context_window.current_usage.input_tokens // 0) + (.context_window.current_usage.cache_creation_input_tokens // 0) + (.context_window.current_usage.cache_read_input_tokens // 0)) | tostring),
    ((.context_window.context_window_size // 0) | tostring),
    (.cwd // ""),
    (.worktree.name // ""),
    (.worktree.branch // "")
  ] | @tsv'
)
```

- [ ] **Step 4: Add CC version to output assembly**

In `plugin/statusline/statusline.sh`, modify the output assembly (line 79-84) to show CC version first:

```bash
# Assemble output
OUTPUT=""

# CC Version
OUTPUT+="${BOLD}CC ${CC_VERSION}${RESET}"

# Separator
OUTPUT+="  ${DIM}│${RESET}  "

# Model
OUTPUT+="${BOLD}${MODEL}${RESET}"
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `bash tests/run-tests.sh 2>&1 | grep -E '(PASS|FAIL).*CC (2\.1\.83|\?)'`
Expected: 2 PASS lines

- [ ] **Step 6: Commit**

```bash
git add plugin/statusline/statusline.sh tests/run-tests.sh
git commit -m "feat: show CC version as first status line element

Reads version field from CC session JSON. Falls back to '?' if missing."
```

---

### Task 2: Context Bar Color Thresholds

**Files:**
- Modify: `plugin/statusline/statusline.sh:37-44` (color selection block)
- Test: `tests/run-tests.sh` (statusline color tests, ~line 1514)

- [ ] **Step 1: Update existing color tests**

Find and update the three existing color threshold tests in `tests/run-tests.sh`:

Replace the blue <50% test (~line 1514):
```bash
assert_contains "$OUTPUT" '\[32m' "statusline uses green for <30% usage"
```
Note: the test input uses `used_percentage:25` so it's already <30%.

Replace the yellow 50-80% test (~line 1517-1518). Change JSON to use 45% (between 30-60%) and test for blue:
```bash
OUTPUT=$(run_statusline '{"model":{"display_name":"Opus"},"context_window":{"used_percentage":45,"context_window_size":200000,"current_usage":{"input_tokens":90000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}},"cwd":"/tmp/test"}')
assert_contains "$OUTPUT" '\[34m' "statusline uses blue for 30-60% usage"
```

Replace the red >80% test (~line 1521-1522). Change JSON to use 65% (>=60%) and update description:
```bash
OUTPUT=$(run_statusline '{"model":{"display_name":"Opus"},"context_window":{"used_percentage":65,"context_window_size":200000,"current_usage":{"input_tokens":130000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}},"cwd":"/tmp/test"}')
assert_contains "$OUTPUT" '\[31m' "statusline uses red for >=60% usage"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/run-tests.sh 2>&1 | grep -E '(PASS|FAIL).*(green|blue|red).*usage'`
Expected: 3 FAIL lines (old colors/thresholds don't match)

- [ ] **Step 3: Update color thresholds in statusline.sh**

Replace lines 37-44 in `plugin/statusline/statusline.sh`:

```bash
# Context bar color: green <30%, blue 30-60%, red >=60%
if [ "$USED_PCT" -lt 30 ]; then
  BAR_COLOR="$GREEN"
elif [ "$USED_PCT" -lt 60 ]; then
  BAR_COLOR="$BLUE"
else
  BAR_COLOR="$RED"
fi
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/run-tests.sh 2>&1 | grep -E '(PASS|FAIL).*(green|blue|red).*usage'`
Expected: 3 PASS lines

- [ ] **Step 5: Commit**

```bash
git add plugin/statusline/statusline.sh tests/run-tests.sh
git commit -m "fix: change context bar colors to green/blue/red with lower thresholds

Yellow was unreadable on white terminal backgrounds. New scheme:
green <30%, blue 30-60%, red >=60%."
```

---

### Task 3: Debug State Helpers

**Files:**
- Modify: `plugin/scripts/workflow-state.sh` (add get_debug, set_debug, preserve in transitions)
- Modify: `plugin/scripts/workflow-cmd.sh` (add to allowlist)
- Test: `tests/run-tests.sh` (workflow-state test section)

- [ ] **Step 1: Write failing tests for get_debug/set_debug**

Add to the workflow-state.sh test section in `tests/run-tests.sh`, after the existing coaching tests:

```bash
# --- Debug flag tests ---
echo ""
echo "--- Debug flag ---"
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"

# Test: get_debug returns "false" by default
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_debug)
assert_eq "false" "$RESULT" "get_debug defaults to false"

# Test: set_debug enables debug mode
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_debug "true"
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_debug)
assert_eq "true" "$RESULT" "set_debug enables debug mode"

# Test: set_debug disables debug mode
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_debug "false"
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_debug)
assert_eq "false" "$RESULT" "set_debug disables debug mode"

# Test: debug flag preserved across phase transitions
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_debug "true"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "review"
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_debug)
assert_eq "true" "$RESULT" "debug flag preserved across phase transitions"

# Test: debug flag cleared when phase goes to OFF
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "off"
RESULT=$(source "$TEST_DIR/.claude/hooks/workflow-state.sh" && get_debug)
assert_eq "false" "$RESULT" "debug flag cleared on OFF"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/run-tests.sh 2>&1 | grep -E '(PASS|FAIL).*debug'`
Expected: 5 FAIL lines (get_debug/set_debug don't exist yet)

- [ ] **Step 3: Add get_debug and set_debug to workflow-state.sh**

Add after the `get_pending_verify` function block (after line 672):

```bash
# ---------------------------------------------------------------------------
# Debug mode
# ---------------------------------------------------------------------------

get_debug() {
    if [ ! -f "$STATE_FILE" ]; then
        echo "false"
        return
    fi
    local val
    val=$(jq -r 'if .debug == true then "true" else "false" end' "$STATE_FILE" 2>/dev/null) || val="false"
    [ -z "$val" ] && val="false"
    echo "$val"
}

set_debug() {
    if [ ! -f "$STATE_FILE" ]; then
        echo "WARNING: No workflow state file. Start a workflow phase first." >&2
        return 1
    fi
    local val="$1"
    case "$val" in
        true|false) ;;
        *) echo "ERROR: Invalid debug value: $val (valid: true, false)" >&2; return 1 ;;
    esac
    _update_state '.debug = ($v == "true")' --arg v "$val"
}
```

- [ ] **Step 4: Preserve debug across phase transitions**

In `workflow-state.sh`, modify `_read_preserved_state()` (~line 307) to add:

```bash
preserved_debug=$(get_debug)
```

Modify `set_phase()` — add `preserved_debug` to the local declarations (~line 372):

```bash
local preserved_debug=""
```

In the OFF-phase clearing block (~line 383), add:

```bash
preserved_debug="false"
```

In the jq template in `set_phase()` (~line 414-436), add `--arg debug "$preserved_debug"` to the jq arguments and add to the JSON template:

```
+ (if $debug == "true" then {debug: true} else {} end)
```

- [ ] **Step 5: Add get_debug and set_debug to workflow-cmd.sh allowlist**

In `plugin/scripts/workflow-cmd.sh`, add `get_debug|set_debug` to the case statement (line 26-42). Add after the `set_pending_verify|get_pending_verify` line:

```bash
    get_debug|set_debug|\
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `bash tests/run-tests.sh 2>&1 | grep -E '(PASS|FAIL).*debug'`
Expected: 5 PASS lines

- [ ] **Step 7: Commit**

```bash
git add plugin/scripts/workflow-state.sh plugin/scripts/workflow-cmd.sh tests/run-tests.sh
git commit -m "feat: add debug state helpers with phase-transition preservation

get_debug/set_debug manage a boolean flag in workflow.json.
Preserved across transitions, cleared on OFF."
```

---

### Task 4: Debug Command File

**Files:**
- Create: `plugin/commands/wf:debug.md`
- Test: `tests/run-tests.sh` (command file existence tests)

- [ ] **Step 1: Write failing test for command file existence**

Add to the command/alias test section in `tests/run-tests.sh`:

```bash
# Test: wf:debug command file exists
assert_file_exists "$REPO_DIR/plugin/commands/wf:debug.md" "wf:debug.md command file exists"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/run-tests.sh 2>&1 | grep -E '(PASS|FAIL).*wf:debug'`
Expected: 1 FAIL line

- [ ] **Step 3: Create the command file**

Create `plugin/commands/wf:debug.md`:

```markdown
---
description: Toggle debug mode — show/hide hook messages to user
allowed-tools: Bash
---

Toggle WFM debug mode. When enabled, all hook coaching messages and gate decisions are shown to the user (not just to Claude).

## Usage

- `/wf:debug on` — enable debug output
- `/wf:debug off` — disable debug output
- `/wf:debug` — show current debug state

## Execution

1. Parse the argument from `$ARGUMENTS`:

\`\`\`bash
.claude/hooks/workflow-cmd.sh get_phase
\`\`\`

2. If no argument, report current state:

\`\`\`bash
.claude/hooks/workflow-cmd.sh get_debug
\`\`\`

Report: "Debug mode is **on/off**."

3. If argument is `on`:

\`\`\`bash
.claude/hooks/workflow-cmd.sh set_debug "true"
\`\`\`

Report: "Debug mode **enabled**. Hook messages will now be visible to you."

4. If argument is `off`:

\`\`\`bash
.claude/hooks/workflow-cmd.sh set_debug "false"
\`\`\`

Report: "Debug mode **disabled**. Hook messages are now Claude-only."

5. If argument is anything else, report: "Invalid argument. Use `on`, `off`, or no argument to check status."
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/run-tests.sh 2>&1 | grep -E '(PASS|FAIL).*wf:debug'`
Expected: 1 PASS line

- [ ] **Step 5: Commit**

```bash
git add plugin/commands/wf:debug.md tests/run-tests.sh
git commit -m "feat: add /wf:debug command for toggling hook message visibility"
```

---

### Task 5: Debug Output in PostToolUse Hook

**Files:**
- Modify: `plugin/scripts/post-tool-navigator.sh:51-62` (after phase check, read debug flag)
- Modify: `plugin/scripts/post-tool-navigator.sh:436-438` (output section)
- Test: `tests/run-tests.sh` (post-tool-navigator test section)

- [ ] **Step 1: Write failing tests for debug stderr output**

Add to the post-tool-navigator test section in `tests/run-tests.sh`:

```bash
# --- Debug mode tests ---
echo ""
echo "--- Debug mode (post-tool-navigator) ---"
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_debug "true"

# Test: debug mode outputs Layer 1 message to stderr
STDERR_OUTPUT=$(echo '{"tool_name":"Write","tool_input":{"file_path":"/tmp/test.js"}}' | "$TEST_DIR/.claude/hooks/post-tool-navigator.sh" 2>&1 1>/dev/null || true)
assert_contains "$STDERR_OUTPUT" "[WFM DEBUG]" "debug mode outputs to stderr with prefix"
assert_contains "$STDERR_OUTPUT" "IMPLEMENT" "debug mode stderr includes phase name"

# Test: no debug output when debug is off
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_debug "false"
STDERR_OUTPUT=$(echo '{"tool_name":"Write","tool_input":{"file_path":"/tmp/test.js"}}' | "$TEST_DIR/.claude/hooks/post-tool-navigator.sh" 2>&1 1>/dev/null || true)
assert_not_contains "$STDERR_OUTPUT" "[WFM DEBUG]" "no debug output when debug is off"

# Test: debug mode shows no-fire message for irrelevant tools
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "discuss"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_debug "true"
# Use Read tool (irrelevant to coaching in discuss phase, exits early)
STDERR_OUTPUT=$(echo '{"tool_name":"Read","tool_input":{"file_path":"/tmp/test.js"}}' | "$TEST_DIR/.claude/hooks/post-tool-navigator.sh" 2>&1 1>/dev/null || true)
assert_contains "$STDERR_OUTPUT" "[WFM DEBUG]" "debug mode outputs for irrelevant tools too"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/run-tests.sh 2>&1 | grep -E '(PASS|FAIL).*debug mode'`
Expected: 4 FAIL lines

- [ ] **Step 3: Add debug flag reading to post-tool-navigator.sh**

After the phase/OFF check (~line 59, after `exit 0` for OFF phase), add:

```bash
# Read debug flag once for all layers
DEBUG_MODE=$(get_debug)
```

- [ ] **Step 4: Add debug stderr output to the output section**

Replace the output section at the end of the file (~lines 436-438):

```bash
if [ -n "$MESSAGES" ]; then
    # Debug: echo all coaching messages to stderr for user visibility
    if [ "$DEBUG_MODE" = "true" ]; then
        echo "[WFM DEBUG] PostToolUse ($TOOL_NAME):" >&2
        echo "$MESSAGES" | sed 's/^/  /' >&2
    fi
    jq -n --arg msg "$MESSAGES" '{"hookSpecificOutput": {"hookEventName": "PostToolUse", "systemMessage": $msg}}'
else
    if [ "$DEBUG_MODE" = "true" ]; then
        echo "[WFM DEBUG] PostToolUse: $TOOL_NAME — no coaching triggered" >&2
    fi
fi
```

- [ ] **Step 5: Add debug output for early-exit tools**

In the early-exit case block (~line 129-135), add debug output before the existing output:

```bash
    *) # Tool is irrelevant to coaching — output any Layer 1 message and exit
        if [ "$DEBUG_MODE" = "true" ]; then
            if [ -n "$MESSAGES" ]; then
                echo "[WFM DEBUG] PostToolUse ($TOOL_NAME) — Layer 1 only:" >&2
                echo "$MESSAGES" | sed 's/^/  /' >&2
            else
                echo "[WFM DEBUG] PostToolUse: $TOOL_NAME — no coaching (tool not tracked)" >&2
            fi
        fi
        if [ -n "$MESSAGES" ]; then
            jq -n --arg msg "$MESSAGES" '{"hookSpecificOutput": {"hookEventName": "PostToolUse", "systemMessage": $msg}}'
        fi
        exit 0
        ;;
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `bash tests/run-tests.sh 2>&1 | grep -E '(PASS|FAIL).*debug mode'`
Expected: 4 PASS lines

- [ ] **Step 7: Commit**

```bash
git add plugin/scripts/post-tool-navigator.sh tests/run-tests.sh
git commit -m "feat: add debug stderr output to PostToolUse coaching hook

When debug=true, all coaching messages are echoed to stderr with
[WFM DEBUG] prefix, making them visible to the user."
```

---

### Task 6: Debug Output in PreToolUse Hooks

**Files:**
- Modify: `plugin/scripts/workflow-gate.sh` (add debug allow/deny logging)
- Modify: `plugin/scripts/bash-write-guard.sh` (add debug allow/deny logging)
- Test: `tests/run-tests.sh` (workflow-gate and bash-write-guard test sections)

- [ ] **Step 1: Write failing tests for debug output in PreToolUse hooks**

Add to the workflow-gate test section:

```bash
# --- Debug mode tests (workflow-gate) ---
echo ""
echo "--- Debug mode (workflow-gate) ---"
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_debug "true"

# Test: workflow-gate debug shows allow in implement phase
STDERR_OUTPUT=$(echo '{"tool_name":"Write","tool_input":{"file_path":"/tmp/test.js"}}' | "$TEST_DIR/.claude/hooks/workflow-gate.sh" 2>&1 1>/dev/null || true)
assert_contains "$STDERR_OUTPUT" "[WFM DEBUG]" "workflow-gate debug shows allow decision"

# Test: no debug output when debug is off
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_debug "false"
STDERR_OUTPUT=$(echo '{"tool_name":"Write","tool_input":{"file_path":"/tmp/test.js"}}' | "$TEST_DIR/.claude/hooks/workflow-gate.sh" 2>&1 1>/dev/null || true)
assert_not_contains "$STDERR_OUTPUT" "[WFM DEBUG]" "workflow-gate no debug when off"
```

Add to the bash-write-guard test section:

```bash
# --- Debug mode tests (bash-write-guard) ---
echo ""
echo "--- Debug mode (bash-write-guard) ---"
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement"
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_debug "true"

# Test: bash-write-guard debug shows allow in implement phase
STDERR_OUTPUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"echo hello"}}' | "$TEST_DIR/.claude/hooks/bash-write-guard.sh" 2>&1 1>/dev/null || true)
assert_contains "$STDERR_OUTPUT" "[WFM DEBUG]" "bash-write-guard debug shows allow decision"

# Test: no debug output when debug is off
source "$TEST_DIR/.claude/hooks/workflow-state.sh" && set_debug "false"
STDERR_OUTPUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"echo hello"}}' | "$TEST_DIR/.claude/hooks/bash-write-guard.sh" 2>&1 1>/dev/null || true)
assert_not_contains "$STDERR_OUTPUT" "[WFM DEBUG]" "bash-write-guard no debug when off"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/run-tests.sh 2>&1 | grep -E '(PASS|FAIL).*(workflow-gate|bash-write-guard) debug'`
Expected: 4 FAIL lines

- [ ] **Step 3: Add debug output to workflow-gate.sh**

After sourcing workflow-state.sh and the state file check (~line 21), add:

```bash
DEBUG_MODE="false"
if [ -f "$STATE_FILE" ]; then
    DEBUG_MODE=$(get_debug)
fi
```

Before each `exit 0` that represents an allow decision, add:

```bash
if [ "$DEBUG_MODE" = "true" ]; then echo "[WFM DEBUG] PreToolUse ALLOW: Write/Edit — phase=$PHASE, reason=<reason>" >&2; fi
```

For the OFF phase exit (~line 29): reason=`phase is OFF`
For implement/review exit (~line 34): reason=`implement/review allows all writes`
For whitelisted path exit (~line 65): reason=`path whitelisted ($NORMALIZED_PATH)`

Before the deny emit, add:

```bash
if [ "$DEBUG_MODE" = "true" ]; then echo "[WFM DEBUG] PreToolUse DENY: Write/Edit on $NORMALIZED_PATH — $REASON" >&2; fi
```

- [ ] **Step 4: Add debug output to bash-write-guard.sh**

Same pattern. After sourcing workflow-state.sh and the state file check, add:

```bash
DEBUG_MODE="false"
if [ -f "$STATE_FILE" ]; then
    DEBUG_MODE=$(get_debug)
fi
```

Add debug echo before each `exit 0` (allow) and before each `emit_deny` (deny). Key allow points:
- OFF phase (~line 45): `phase is OFF`
- Workflow state commands (~line 66): `workflow state command`
- Git commit (~line 83): `git commit allowed`
- Implement/review phase (~line 124): `implement/review allows all bash`
- Whitelisted path (~line 150): `write target whitelisted`
- Read-only command (~line 165): `no write pattern detected`

- [ ] **Step 5: Run tests to verify they pass**

Run: `bash tests/run-tests.sh 2>&1 | grep -E '(PASS|FAIL).*(workflow-gate|bash-write-guard) debug'`
Expected: 4 PASS lines

- [ ] **Step 6: Commit**

```bash
git add plugin/scripts/workflow-gate.sh plugin/scripts/bash-write-guard.sh tests/run-tests.sh
git commit -m "feat: add debug stderr output to PreToolUse gate hooks

When debug=true, workflow-gate.sh and bash-write-guard.sh log
allow/deny decisions to stderr with [WFM DEBUG] prefix."
```

---

### Task 7: Debug Indicator in Status Line

**Files:**
- Modify: `plugin/statusline/statusline.sh:135-160` (phase display section)
- Test: `tests/run-tests.sh` (statusline test section)

- [ ] **Step 1: Write failing tests**

Add to statusline test section:

```bash
# --- Debug indicator in statusline ---
echo ""
echo "--- Debug indicator ---"

# Test: statusline shows DEBUG indicator when debug=true
SL_DEBUG_DIR=$(mktemp -d)
trap 'rm -rf "$SL_DEBUG_DIR"' EXIT
mkdir -p "$SL_DEBUG_DIR/.claude/state"
echo '{"phase":"implement","debug":true,"autonomy_level":"ask"}' > "$SL_DEBUG_DIR/.claude/state/workflow.json"
mkdir -p "$HOME/.claude/plugins/cache/azevedo-home-lab/workflow-manager"
OUTPUT=$(run_statusline "{\"version\":\"2.1.83\",\"model\":{\"display_name\":\"Opus\"},\"context_window\":{\"used_percentage\":10,\"context_window_size\":200000,\"current_usage\":{\"input_tokens\":20000,\"cache_creation_input_tokens\":0,\"cache_read_input_tokens\":0}},\"cwd\":\"$SL_DEBUG_DIR\"}")
assert_contains "$OUTPUT" "DEBUG" "statusline shows DEBUG when debug flag is true"

# Test: statusline hides DEBUG indicator when debug=false
SL_NODEBUG_DIR=$(mktemp -d)
trap 'rm -rf "$SL_NODEBUG_DIR"' EXIT
mkdir -p "$SL_NODEBUG_DIR/.claude/state"
echo '{"phase":"implement","debug":false,"autonomy_level":"ask"}' > "$SL_NODEBUG_DIR/.claude/state/workflow.json"
OUTPUT=$(run_statusline "{\"version\":\"2.1.83\",\"model\":{\"display_name\":\"Opus\"},\"context_window\":{\"used_percentage\":10,\"context_window_size\":200000,\"current_usage\":{\"input_tokens\":20000,\"cache_creation_input_tokens\":0,\"cache_read_input_tokens\":0}},\"cwd\":\"$SL_NODEBUG_DIR\"}")
CLEAN_OUTPUT=$(echo "$OUTPUT" | sed 's/\x1b\[[0-9;]*m//g')
assert_not_contains "$CLEAN_OUTPUT" "DEBUG" "statusline hides DEBUG when debug flag is false"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/run-tests.sh 2>&1 | grep -E '(PASS|FAIL).*DEBUG'`
Expected: 2 FAIL lines

- [ ] **Step 3: Add DEBUG indicator to statusline.sh**

In the phase display section of `statusline.sh`, after reading `WM_PHASE` and `WM_AUTONOMY` (~line 136-137), add:

```bash
    WM_DEBUG=$(grep -o '"debug"[[:space:]]*:[[:space:]]*true' "$WM_STATE_FILE" || true)
```

After each phase badge line (e.g., after `OUTPUT+=" ${GREEN}${AUTONOMY_SYM}[IMPLEMENT]${RESET}"`), add the debug indicator. The cleanest approach: add it once after the phase if/elif block ends (~line 159):

```bash
    # Debug indicator
    if [ -n "$WM_DEBUG" ]; then
      OUTPUT+=" ${BOLD}${YELLOW}[DEBUG]${RESET}"
    fi
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/run-tests.sh 2>&1 | grep -E '(PASS|FAIL).*DEBUG'`
Expected: 2 PASS lines

- [ ] **Step 5: Commit**

```bash
git add plugin/statusline/statusline.sh tests/run-tests.sh
git commit -m "feat: show [DEBUG] indicator in status line when debug mode is on"
```

---

### Task 8: Full Test Run and Final Commit

- [ ] **Step 1: Run the complete test suite**

Run: `bash tests/run-tests.sh`
Expected: All tests pass (current 713 + ~18 new = ~731 total), 0 failures

- [ ] **Step 2: Fix any failing tests**

If any pre-existing tests fail due to the color/version changes (e.g., tests that previously checked for blue at 25% now need to check for green), fix them.

- [ ] **Step 3: Update version if needed**

Check with the user if version bump to 1.8.0 is wanted for this release.

- [ ] **Step 4: Commit spec and decision record**

These were written during DISCUSS but couldn't be committed due to phase gate:

```bash
git add docs/superpowers/specs/2026-03-26-statusline-debug-design.md docs/plans/2026-03-26-statusline-debug-decisions.md
git commit -m "docs: add spec and decision record for status line and debug command"
```
