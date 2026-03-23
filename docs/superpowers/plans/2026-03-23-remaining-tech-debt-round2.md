# Remaining Tech Debt Round 2 — Safe Write & Phase Enum Guard

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Centralize all state file writes through a `_safe_write` helper with size guard and zero-byte rejection, and add phase enum validation to `get_phase`.

**Architecture:** Extract a `_safe_write` helper that handles PID-scoped temp file, zero-byte rejection, 10KB size guard, and atomic mv. Refactor `_update_state` and 4 direct-write paths to pipe through it. Add phase enum guard in `get_phase`.

**Tech Stack:** Bash, jq

**Spec:** `docs/superpowers/specs/2026-03-23-remaining-tech-debt-design.md`

---

### Task 1: Commit spec and update decision record

These files were written during DISCUSS but couldn't be committed due to phase gate.

**Files:**
- Existing: `docs/superpowers/specs/2026-03-23-remaining-tech-debt-design.md`
- Modify: `docs/decisions/2026-03-23-remaining-tech-debt-cleanup.md`

- [ ] **Step 1: Update decision record with Round 2 section**

Append to end of `docs/decisions/2026-03-23-remaining-tech-debt-cleanup.md`:

```markdown
---

## Round 2: Remaining Tech Debt (from devil's advocate review of Round 1)

**Date:** 2026-03-23 (second pass)
**Origin:** Handover #3615 — 5 items from devil's advocate review, 1 accepted as-is

### Approaches Considered (DISCUSS phase — diverge)

#### Approach A: Extract `_safe_write` helper (chosen)
- Extract write-temp-size-check-mv into shared helper; all 5 write paths pipe through it
- Pros: eliminates class of bug, single source of truth for size guard
- Cons: one more level of indirection

#### Approach B: Inline fixes at each call site
- Add size check inline at each of 4 direct-write locations
- Pros: zero abstraction, smaller diff
- Cons: 4 copies of same logic, next contributor must remember the pattern

### Decision (DISCUSS phase — converge)

- **Chosen approach:** Approach A — `_safe_write` helper + phase enum guard
- **Rationale:** Eliminates the class of bug rather than patching instances
- **Trade-offs accepted:**
  - One more level of indirection (pipe into helper)
  - Item 5 (env leak via filter param) accepted as documented risk — all callers are internal
  - Item 2 (concurrent last-writer-wins) accepted as documented behavior — no file locking
- **Risks identified:** Pipe changes error propagation — mitigated by zero-byte rejection in `_safe_write`
- **Constraints applied:** `workflow-state.sh` does not set `pipefail`, so zero-byte check is load-bearing
- **Tech debt acknowledged:** None — this round clears all remaining items
- **Spec:** `docs/superpowers/specs/2026-03-23-remaining-tech-debt-design.md`
```

- [ ] **Step 2: Commit docs**

```bash
git add docs/superpowers/specs/2026-03-23-remaining-tech-debt-design.md docs/decisions/2026-03-23-remaining-tech-debt-cleanup.md
git commit -m "docs: add spec and decision record for remaining tech debt round 2"
```

---

### Task 2: Write failing tests for `_safe_write` and phase enum guard

**Files:**
- Modify: `tests/run-tests.sh` — add tests after the existing `_update_state Safety Guards` section (after line 1979)

- [ ] **Step 1: Write 5 new tests**

Insert after line 1979 (after `zero-byte state: get_message_shown returns false`) and before line 1981 (`# ============================================================` / `# TEST SUITE: Completion Snapshot`):

```bash
# Test: _safe_write rejects oversized input
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh"
set_phase "off"
OVERSIZE_SW_ERR=$(printf '%0.sx' $(seq 1 12000) | _safe_write 2>&1) && OVERSIZE_SW_EXIT=0 || OVERSIZE_SW_EXIT=$?
assert_eq "1" "$OVERSIZE_SW_EXIT" "_safe_write: rejects oversized input"
assert_contains "$OVERSIZE_SW_ERR" "10KB" "_safe_write: error message mentions 10KB"
TMP_FILES=$(find "$STATE_DIR" -name '*.tmp.*' 2>/dev/null | wc -l | tr -d ' ')
assert_eq "0" "$TMP_FILES" "_safe_write: no temp files left after oversized rejection"

# Test: _safe_write rejects zero-byte input
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh"
set_phase "off"
ORIGINAL=$(cat "$STATE_FILE")
printf '' | _safe_write 2>/dev/null && ZERO_SW_EXIT=0 || ZERO_SW_EXIT=$?
assert_eq "1" "$ZERO_SW_EXIT" "_safe_write: rejects zero-byte input"
TMP_FILES=$(find "$STATE_DIR" -name '*.tmp.*' 2>/dev/null | wc -l | tr -d ' ')
assert_eq "0" "$TMP_FILES" "_safe_write: no temp files left after zero-byte rejection"
AFTER=$(cat "$STATE_FILE")
assert_eq "$ORIGINAL" "$AFTER" "_safe_write: state file unchanged after zero-byte rejection"

# Test: initial-creation via _safe_write produces valid JSON
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh"
rm -f "$STATE_FILE"
set_last_observation_id 9999
VALID=$(jq -e '.last_observation_id' "$STATE_FILE" 2>/dev/null) && VALID_EXIT=0 || VALID_EXIT=$?
assert_eq "0" "$VALID_EXIT" "initial creation: produces valid JSON via _safe_write"
assert_eq "9999" "$VALID" "initial creation: contains expected observation ID"

# Test: get_phase returns "off" for unknown phase string (enum guard)
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh"
set_phase "off"
jq '.phase = "bogus"' "$STATE_FILE" > "$STATE_FILE.tmp.test" && mv "$STATE_FILE.tmp.test" "$STATE_FILE"
RESULT=$(get_phase)
assert_eq "off" "$RESULT" "phase enum guard: unknown phase string returns off"

# Test: get_phase returns "off" for null phase (enum guard)
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh"
set_phase "off"
jq '.phase = null' "$STATE_FILE" > "$STATE_FILE.tmp.test" && mv "$STATE_FILE.tmp.test" "$STATE_FILE"
RESULT=$(get_phase)
assert_eq "off" "$RESULT" "phase enum guard: null phase returns off"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/run-tests.sh 2>&1 | tail -20`

Expected: The test runner will **abort** at the first `_safe_write` call because the function doesn't exist yet and the file runs under `set -euo pipefail`. This is expected — proceed to Task 3. The phase enum guard test for `"bogus"` would also FAIL if reached (no enum validation yet).

- [ ] **Step 3: Commit failing tests**

```bash
git add tests/run-tests.sh
git commit -m "test: add failing tests for _safe_write and phase enum guard"
```

---

### Task 3: Implement `_safe_write` helper

**Files:**
- Modify: `plugin/scripts/workflow-state.sh`

- [ ] **Step 1: Add `_safe_write` function after `_update_state` (after line 35)**

Insert after line 35 (`mv "$tmpfile" "$STATE_FILE"` / closing brace of `_update_state`) and before line 37 (`# Restrictive tier`):

```bash

# Atomic write helper. Reads stdin → PID-scoped temp file → size guards → mv.
# All state file writes MUST go through this function.
# Rejects zero-byte input (catches pipe-from-failed-jq) and >10KB output.
_safe_write() {
    local tmpfile="${STATE_FILE}.tmp.$$"
    cat > "$tmpfile" || { rm -f "$tmpfile"; return 1; }
    local size
    size=$(wc -c < "$tmpfile")
    if [ "$size" -eq 0 ]; then
        rm -f "$tmpfile"
        return 1
    fi
    if [ "$size" -gt 10240 ]; then
        rm -f "$tmpfile"
        echo "ERROR: State file would exceed 10KB ($size bytes). Write rejected." >&2
        return 1
    fi
    mv "$tmpfile" "$STATE_FILE"
}
```

- [ ] **Step 2: Run tests**

Run: `bash tests/run-tests.sh 2>&1 | tail -20`

Expected: `_safe_write` direct tests (oversized, zero-byte) should now pass. The "initial creation via `_safe_write`" test will also pass — it calls `set_last_observation_id` which still uses `> "$STATE_FILE"` at this stage, but produces valid JSON regardless. The code path won't actually exercise `_safe_write` until Task 5 refactors the initial-creation paths. Existing tests still pass. Phase enum guard tests still fail (Task 7).

- [ ] **Step 3: Commit**

```bash
git add plugin/scripts/workflow-state.sh
git commit -m "feat: add _safe_write atomic write helper with zero-byte and size guards"
```

---

### Task 4: Refactor `_update_state` to use `_safe_write`

**Files:**
- Modify: `plugin/scripts/workflow-state.sh`

- [ ] **Step 1: Add security comment and replace `_update_state` body**

Replace the current `_update_state` function (lines 15-35) with:

```bash
# Generic state write helper. Pipes jq output through _safe_write for atomic,
# size-guarded writes.
# SECURITY NOTE: The $filter parameter is interpolated into jq. This is safe
# because all callers are within this file with hardcoded filter strings.
# Do not expose _update_state to untrusted input.
# Usage: _update_state <jq_filter> [--arg name val]... [--argjson name val]...
_update_state() {
    if [ ! -f "$STATE_FILE" ]; then return 1; fi
    local filter="$1"; shift
    local ts
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    jq --arg ts "$ts" "$@" \
        "$filter | .updated = \$ts" \
        "$STATE_FILE" | _safe_write
}
```

- [ ] **Step 2: Run full test suite**

Run: `bash tests/run-tests.sh 2>&1 | tail -20`

Expected: All tests pass. The existing `_update_state` size guard and jq failure tests should still pass because `_safe_write` handles both cases.

- [ ] **Step 3: Commit**

```bash
git add plugin/scripts/workflow-state.sh
git commit -m "refactor: _update_state pipes through _safe_write instead of inline temp/size/mv"
```

---

### Task 5: Refactor 3 initial-creation paths to use `_safe_write`

**Files:**
- Modify: `plugin/scripts/workflow-state.sh` — functions `set_last_observation_id`, `set_tracked_observations`, `add_tracked_observation`

- [ ] **Step 1: Refactor `set_last_observation_id` initial-creation branch**

In `set_last_observation_id`, replace the initial-creation branch (currently lines 121-125):

```bash
    if [ ! -f "$STATE_FILE" ]; then
        # Create minimal state file for observation tracking
        jq -n --argjson id "$obs_id" --arg ts "$ts" \
            '{"phase": "off", "last_observation_id": $id, "updated": $ts}' > "$STATE_FILE"
        return
    fi
```

With:

```bash
    if [ ! -f "$STATE_FILE" ]; then
        # Create minimal state file for observation tracking
        jq -n --argjson id "$obs_id" --arg ts "$ts" \
            '{"phase": "off", "last_observation_id": $id, "updated": $ts}' | _safe_write
        return $?
    fi
```

- [ ] **Step 2: Refactor `set_tracked_observations` initial-creation branch**

In `set_tracked_observations`, replace the initial-creation branch (currently lines 149-152):

```bash
    if [ ! -f "$STATE_FILE" ]; then
        jq -n --arg ids "$ids_csv" --arg ts "$ts" \
            '{"phase": "off", "tracked_observations": (if $ids == "" then [] else ($ids | split(",") | map(select(. != "") | tonumber)) end), "updated": $ts}' > "$STATE_FILE"
        return
    fi
```

With:

```bash
    if [ ! -f "$STATE_FILE" ]; then
        jq -n --arg ids "$ids_csv" --arg ts "$ts" \
            '{"phase": "off", "tracked_observations": (if $ids == "" then [] else ($ids | split(",") | map(select(. != "") | tonumber)) end), "updated": $ts}' | _safe_write
        return $?
    fi
```

- [ ] **Step 3: Refactor `add_tracked_observation` initial-creation branch**

In `add_tracked_observation`, replace the initial-creation branch (currently lines 163-166):

```bash
    if [ ! -f "$STATE_FILE" ]; then
        jq -n --argjson id "$obs_id" --arg ts "$ts" \
            '{"phase": "off", "tracked_observations": [$id], "updated": $ts}' > "$STATE_FILE"
        return
    fi
```

With:

```bash
    if [ ! -f "$STATE_FILE" ]; then
        jq -n --argjson id "$obs_id" --arg ts "$ts" \
            '{"phase": "off", "tracked_observations": [$id], "updated": $ts}' | _safe_write
        return $?
    fi
```

- [ ] **Step 4: Run full test suite**

Run: `bash tests/run-tests.sh 2>&1 | tail -20`

Expected: All tests pass, including "initial creation: produces valid JSON via _safe_write".

- [ ] **Step 5: Commit**

```bash
git add plugin/scripts/workflow-state.sh
git commit -m "refactor: initial-creation paths pipe through _safe_write for size guard and atomicity"
```

---

### Task 6: Refactor `set_phase` to use `_safe_write`

**Files:**
- Modify: `plugin/scripts/workflow-state.sh` — function `set_phase`

- [ ] **Step 1: Replace the final jq write in `set_phase`**

In `set_phase`, replace the last write block (currently line 297-315, the large `jq -n` that builds the full state):

Change the last two lines of that jq command from:

```bash
        > "${STATE_FILE}.tmp.$$" && mv "${STATE_FILE}.tmp.$$" "$STATE_FILE"
```

To:

```bash
        | _safe_write
```

The full jq pipeline ending should look like:

```bash
    jq -n --arg phase "$new_phase" --arg ts "$ts" \
        --arg skill "$preserved_skill" --arg decision "$preserved_decision" \
        --argjson autonomy "${preserved_autonomy:-null}" \
        --arg obs_id "$preserved_obs_id" \
        --argjson tracked "$tracked_json" \
        --argjson snapshot "$snapshot_json" \
        '{
            phase: $phase,
            message_shown: false,
            active_skill: $skill,
            decision_record: $decision,
            coaching: {tool_calls_since_agent: 0, layer2_fired: []},
            updated: $ts
        }
        + (if $autonomy != null then {autonomy_level: $autonomy} else {} end)
        + (if $obs_id != "" and $obs_id != "null" then {last_observation_id: ($obs_id | tonumber)} else {} end)
        + (if ($tracked | length) > 0 then {tracked_observations: $tracked} else {} end)
        + (if $snapshot != null then {completion_snapshot: $snapshot} else {} end)' \
        | _safe_write
```

- [ ] **Step 2: Run full test suite**

Run: `bash tests/run-tests.sh 2>&1 | tail -20`

Expected: All tests pass. The set_phase tests (there are many) validate this works.

- [ ] **Step 3: Commit**

```bash
git add plugin/scripts/workflow-state.sh
git commit -m "refactor: set_phase pipes through _safe_write for size guard and consistency"
```

---

### Task 7: Add phase enum guard to `get_phase`

**Files:**
- Modify: `plugin/scripts/workflow-state.sh` — function `get_phase`

- [ ] **Step 1: Add enum validation to `get_phase`**

In `get_phase`, insert a `case` block after the empty-string guard (`[ -z "$phase" ] && phase="off"`) and before `echo "$phase"`. The function should become:

```bash
get_phase() {
    if [ ! -f "$STATE_FILE" ]; then
        echo "off"
        return
    fi
    local phase
    phase=$(jq -r '.phase // "off"' "$STATE_FILE" 2>/dev/null) || phase="off"
    [ -z "$phase" ] && phase="off"
    case "$phase" in
        off|define|discuss|implement|review|complete) ;;
        *) phase="off" ;;
    esac
    echo "$phase"
}
```

- [ ] **Step 2: Run full test suite**

Run: `bash tests/run-tests.sh 2>&1 | tail -20`

Expected: All tests pass, including the two new phase enum guard tests ("bogus" → off, null → off).

- [ ] **Step 3: Commit**

```bash
git add plugin/scripts/workflow-state.sh
git commit -m "fix: get_phase validates against known phase enum, unknown values default to off"
```

---

### Task 8: Run full test suite and verify

- [ ] **Step 1: Run full test suite**

Run: `bash tests/run-tests.sh 2>&1`

Expected: All existing + 10 new assertions pass. Zero failures. (Baseline is approximately 372 assertions; exact count may vary.)

- [ ] **Step 2: Verify workflow-state.sh has no remaining direct writes to STATE_FILE**

Run: `grep -n '> "$STATE_FILE"\|> "${STATE_FILE}"' plugin/scripts/workflow-state.sh` (use Grep tool)

Expected: Zero matches — all writes go through `_safe_write`.

- [ ] **Step 3: Final commit if any adjustments were needed**

Only if previous tasks required fixes. Otherwise skip.
