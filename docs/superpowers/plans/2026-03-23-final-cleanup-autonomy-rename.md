# Final Cleanup + Autonomy Rename Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix 3 remaining tech debt items and rename autonomy levels from 1/2/3 to off/ask/auto across the entire codebase.

**Architecture:** 4 independent changes to workflow-state.sh, setup.sh, and consumer scripts. Autonomy rename is a breaking change — no migration needed.

**Tech Stack:** Bash, jq

---

### Task 1: Add pipefail to `set_phase` and initial-creation pipes

**Files:**
- Modify: `plugin/scripts/workflow-state.sh`

- [ ] **Step 1: Wrap `set_phase` jq pipe in pipefail subshell**

In `set_phase`, the final jq command (currently ending with `| _safe_write`) should be wrapped. Change:

```bash
    jq -n --arg phase "$new_phase" --arg ts "$ts" \
        ...
        | _safe_write
```

To:

```bash
    ( set -o pipefail
      jq -n --arg phase "$new_phase" --arg ts "$ts" \
          ...
          | _safe_write
    )
```

- [ ] **Step 2: Wrap 3 initial-creation pipes in pipefail subshells**

In `set_last_observation_id`, `set_tracked_observations`, `add_tracked_observation` — each initial-creation branch has `jq -n ... | _safe_write`. Wrap each in `( set -o pipefail; jq -n ... | _safe_write )` and change `return $?` to capture the subshell exit:

```bash
    if [ ! -f "$STATE_FILE" ]; then
        ( set -o pipefail; jq -n ... | _safe_write )
        return $?
    fi
```

- [ ] **Step 3: Run tests**

Run: `bash tests/run-tests.sh 2>&1 | tail -5`
Expected: All 384 tests pass.

- [ ] **Step 4: Commit**

```bash
git add plugin/scripts/workflow-state.sh
git commit -m "fix: wrap all jq|_safe_write pipes in pipefail subshells for consistency"
```

---

### Task 2: Add stale temp file cleanup to setup.sh

**Files:**
- Modify: `plugin/scripts/setup.sh`

- [ ] **Step 1: Add cleanup after state dir creation**

In `setup.sh`, after the `mkdir -p` that creates the state directory and before the state file creation, add:

```bash
# Clean up stale temp files from interrupted writes (older than 5 minutes)
find "$STATE_DIR" -name '*.tmp.*' -mmin +5 -delete 2>/dev/null || true
```

- [ ] **Step 2: Run tests**

Run: `bash tests/run-tests.sh 2>&1 | tail -5`
Expected: All tests pass.

- [ ] **Step 3: Commit**

```bash
git add plugin/scripts/setup.sh
git commit -m "fix: clean up stale temp files from interrupted writes on session start"
```

---

### Task 3: Make `set_tracked_observations` resilient to non-numeric CSV elements

**Files:**
- Modify: `plugin/scripts/workflow-state.sh`
- Modify: `tests/run-tests.sh`

- [ ] **Step 1: Write failing test**

Add after the existing tracked observations tests (find the `# TEST SUITE: _update_state Safety Guards` section and add before it):

```bash
# Test: set_tracked_observations skips non-numeric CSV elements
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh"
set_phase "implement"
set_tracked_observations "1,abc,3"
RESULT=$(get_tracked_observations)
assert_eq "1,3" "$RESULT" "set_tracked_observations skips non-numeric CSV elements"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/run-tests.sh 2>&1 | grep -A2 "non-numeric"`
Expected: FAIL (currently the entire jq expression fails on `abc`).

- [ ] **Step 3: Fix the jq filter**

In `set_tracked_observations`, change `tonumber` to `(tonumber? // empty)` in BOTH the initial-creation branch AND the `_update_state` call:

Initial-creation branch:
```bash
'{"phase": "off", "tracked_observations": (if $ids == "" then [] else ($ids | split(",") | map(select(. != "") | (tonumber? // empty))) end), "updated": $ts}'
```

`_update_state` call:
```bash
_update_state '.tracked_observations = (if $ids == "" then [] else ($ids | split(",") | map(select(. != "") | (tonumber? // empty))) end)' --arg ids "$ids_csv"
```

- [ ] **Step 4: Run tests**

Expected: All tests pass including new one.

- [ ] **Step 5: Commit**

```bash
git add plugin/scripts/workflow-state.sh tests/run-tests.sh
git commit -m "fix: set_tracked_observations skips non-numeric CSV elements instead of failing"
```

---

### Task 4: Rename autonomy levels from 1/2/3 to off/ask/auto

This is a breaking change. All references to numeric autonomy levels become string names.

**Files:**
- Modify: `plugin/scripts/workflow-state.sh` — validation, defaults, storage
- Modify: `plugin/scripts/workflow-gate.sh` — comparison `"1"` → `"off"`
- Modify: `plugin/scripts/bash-write-guard.sh` — comparison `"1"` → `"off"`
- Modify: `plugin/scripts/post-tool-navigator.sh` — comparison `"3"` → `"auto"`
- Modify: `plugin/statusline/statusline.sh` — grep pattern, case statement
- Modify: `plugin/scripts/setup.sh` — default value
- Modify: `plugin/commands/autonomy.md` — user-facing docs
- Modify: `tests/run-tests.sh` — all test assertions

- [ ] **Step 1: Update `workflow-state.sh`**

**`get_autonomy_level`:** Change default from `2` to `"ask"`:
```bash
get_autonomy_level() {
    if [ ! -f "$STATE_FILE" ]; then
        echo "ask"
        return
    fi
    local level
    level=$(jq -r '.autonomy_level // "ask"' "$STATE_FILE" 2>/dev/null) || level="ask"
    [ -z "$level" ] && level="ask"
    echo "$level"
}
```

**`set_autonomy_level`:** Change validation from `1|2|3` to `off|ask|auto`:
```bash
set_autonomy_level() {
    local level="$1"
    case "$level" in
        off|ask|auto) ;;
        *) echo "ERROR: Invalid autonomy level: $level (valid: off, ask, auto)" >&2; return 1 ;;
    esac
    ...
    _update_state '.autonomy_level = $v' --arg v "$level"
}
```

Note: change `--argjson v "$level"` to `--arg v "$level"` since values are now strings, not numbers.

**`set_phase`:** Change default init from `"2"` to `"ask"`:
```bash
    if [ "$current_phase" = "off" ] && [ "$new_phase" != "off" ] && [ -z "$preserved_autonomy" ]; then
        preserved_autonomy="ask"
    fi
```

And change `--argjson autonomy` to `--arg autonomy` (string, not number) and adjust the null check:
```bash
        --arg autonomy "${preserved_autonomy}" \
```
And in the JSON builder, change `$autonomy != null` to `$autonomy != ""`:
```bash
        + (if $autonomy != "" then {autonomy_level: $autonomy} else {} end)
```

Update the comment about initializing to `2` → `"ask"`.

- [ ] **Step 2: Update `workflow-gate.sh`**

Change `"1"` to `"off"`:
```bash
if [ "$AUTONOMY_LEVEL" = "off" ]; then
```

- [ ] **Step 3: Update `bash-write-guard.sh`**

Change `"1"` to `"off"`:
```bash
if [ "$AUTONOMY_LEVEL" = "off" ]; then
```

- [ ] **Step 4: Update `post-tool-navigator.sh`**

Change `"3"` to `"auto"`:
```bash
if [ "$AUTONOMY_LEVEL" = "auto" ] && [ -n "$MESSAGES" ]; then
```

- [ ] **Step 5: Update `statusline.sh`**

Change the grep pattern from `[0-9]*` to `"[^"]*"` and the case statement:
```bash
    WM_AUTONOMY=$(grep -o '"autonomy_level"[[:space:]]*:[[:space:]]*"[^"]*"' "$WM_STATE_FILE" | grep -o '"[^"]*"$' | tr -d '"')
    ...
    case "$WM_AUTONOMY" in
      off) AUTONOMY_SYM="▶ " ;;
      ask) AUTONOMY_SYM="▶▶ " ;;
      auto) AUTONOMY_SYM="▶▶▶ " ;;
    esac
```

- [ ] **Step 6: Update `setup.sh`**

Change `autonomy_level: 2` to `autonomy_level: "ask"` in the initial state creation:
```bash
    autonomy_level: "ask"
```

- [ ] **Step 7: Update `autonomy.md`**

Replace content with:
```markdown
Set the Workflow Manager autonomy level. This controls how much independence Claude has during the workflow.

**Levels:**
- `off` (▶ Supervised): Read-only. Local research only, no file writes, no web access.
- `ask` (▶▶ Semi-Auto): Writes allowed per phase rules. Stops at each phase transition for user approval.
- `auto` (▶▶▶ Unattended): Full autonomy. Auto-transitions between phases, auto-commits. Stops only for user input in DISCUSS/DEFINE and before git push.

## Usage

\```
/autonomy off|ask|auto
\```

## Execution

Run this to set the level:

\```bash
WF="${CLAUDE_PLUGIN_ROOT}/scripts/workflow-cmd.sh" && "$WF" set_autonomy_level "$ARGUMENTS"
echo "Autonomy level set to $ARGUMENTS"
\```

Then apply the corresponding behavior:

**If level is off:** Enter plan mode by calling the `EnterPlanMode` tool. This blocks all write operations at the Claude Code level. Confirm: "▶ **Supervised** — read-only mode. I can research and explore but cannot modify files. Run `/autonomy ask` to enable writes."

**If level is ask:** If you are currently in plan mode, call `ExitPlanMode`. Confirm: "▶▶ **Semi-Auto** — writes enabled per phase rules. I'll propose phase transitions and wait for your approval."

**If level is auto:** If you are currently in plan mode, call `ExitPlanMode`. Confirm: "▶▶▶ **Unattended** — full autonomy. I'll auto-transition between phases and auto-commit. I'll stop only when I need your input or before git push. Note: ensure your `settings.local.json` includes Bash, WebFetch, WebSearch, and MCP tools in the allow list for fully unattended operation."

**Important:** Only the user can run this command. If you think a different level would be appropriate, suggest it: "This task would benefit from auto — run `/autonomy auto` if you'd like to proceed unattended." Do NOT invoke this command yourself.
```

- [ ] **Step 8: Update all tests in `run-tests.sh`**

Apply these replacements across the entire test file:

| Old | New |
|-----|-----|
| `set_autonomy_level 1` | `set_autonomy_level off` |
| `set_autonomy_level 2` | `set_autonomy_level ask` |
| `set_autonomy_level 3` | `set_autonomy_level auto` |
| `assert_eq "1" "$RESULT"` (autonomy context) | `assert_eq "off" "$RESULT"` |
| `assert_eq "2" "$RESULT"` (autonomy context) | `assert_eq "ask" "$RESULT"` |
| `assert_eq "3" "$RESULT"` (autonomy context) | `assert_eq "auto" "$RESULT"` |
| `"autonomy_level": 1` / `autonomy_level: 1` | `"autonomy_level": "off"` |
| `"autonomy_level": 2` / `autonomy_level: 2` | `"autonomy_level": "ask"` |
| `"autonomy_level": 3` / `autonomy_level: 3` | `"autonomy_level": "auto"` |
| `.autonomy_level = 1` (jq) | `.autonomy_level = "off"` |
| `.autonomy_level = 2` (jq) | `.autonomy_level = "ask"` |
| `.autonomy_level = 3` (jq) | `.autonomy_level = "auto"` |
| `defaults to 2` (test names) | `defaults to ask` |
| `sets level to 1` | `sets level to off` |
| `sets level to 2` | `sets level to ask` |
| `sets level to 3` | `sets level to auto` |
| `rejects 0` / `rejects 4` | `rejects 0` / `rejects 4` (keep — still invalid) |
| `rejects non-numeric input` | `rejects invalid input` |
| `initializes autonomy_level to 2` | `initializes autonomy_level to ask` |
| `clears autonomy_level (returns default 2)` | `clears autonomy_level (returns default ask)` |
| `preserved across phase transitions` assert `"3"` | assert `"auto"` |
| Zero-byte state: `assert_eq "2"` for autonomy | `assert_eq "ask"` |

Also update inline jq JSON in test fixtures that create state files with `"autonomy_level":2` → `"autonomy_level":"ask"`.

- [ ] **Step 9: Run full test suite**

Run: `bash tests/run-tests.sh 2>&1 | tail -5`
Expected: All tests pass.

- [ ] **Step 10: Commit**

```bash
git add plugin/scripts/workflow-state.sh plugin/scripts/workflow-gate.sh plugin/scripts/bash-write-guard.sh plugin/scripts/post-tool-navigator.sh plugin/statusline/statusline.sh plugin/scripts/setup.sh plugin/commands/autonomy.md tests/run-tests.sh
git commit -m "feat: rename autonomy levels from 1/2/3 to off/ask/auto for clarity"
```

---

### Task 5: Run full test suite and verify

- [ ] **Step 1: Run full test suite**

Run: `bash tests/run-tests.sh 2>&1`
Expected: All tests pass. Zero failures.

- [ ] **Step 2: Verify no stale references to numeric autonomy levels in code**

Search for `"1".*autonomy\|"2".*autonomy\|"3".*autonomy\|autonomy.*[123]` in plugin/ scripts (excluding docs/specs/plans).

Expected: Zero matches in active code files.
