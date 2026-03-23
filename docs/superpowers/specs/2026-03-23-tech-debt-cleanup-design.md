# Tech Debt Cleanup — Design Specification

**Date:** 2026-03-23
**Status:** Approved
**Approach:** A — jq-first migration, then generic helper, then set_phase decomposition

## Problem

Six tech debt items accumulated from the plugin conversion era and the open issues cleanup session:

1. **HIGH:** Hard gate tests missing phase-unchanged assertions — gate correctness unverified
2. **MEDIUM:** `set_phase()` is ~120 lines — difficult to read, test, and maintain
3. **MEDIUM:** 12 setter functions share identical read-modify-write boilerplate (~200 duplicate lines)
4. **LOW:** python3 invoked 50+ times per workflow cycle for JSON — slow startup per call, heavy dependency
5. **LOW:** No concurrent write protection on workflow.json — risk of silent data loss
6. **LOW:** Duplicate plugin.json — structural necessity, already mitigated by sync check

Items 2, 3, and 4 are deeply intertwined: the setter functions (#3) all use python3 (#4), and `set_phase` (#2) is the largest setter.

## Design

### Phase 1: jq as Hard Dependency

`setup.sh` enforces jq at startup with a clear error and exit if missing (replacing the current soft warning). `check-version-sync.sh` also migrates from python3 to jq.

**Rationale:** Every function depends on jq after migration. A soft warning would cause silent failures. jq is ubiquitous (macOS Homebrew, apt, yum) and lighter than python3.

**Trade-off accepted:** Users without jq cannot use the plugin.

### Phase 2: python3→jq Migration

Migrate all ~62 python3 invocations across 6 files:

| File | Calls | Purpose |
|------|-------|---------|
| `workflow-state.sh` | ~36 | All getters, setters, and `emit_deny()` JSON output |
| `post-tool-navigator.sh` | ~13 | JSON parsing of hook input + JSON output formatting |
| `bash-write-guard.sh` | ~4 | Command parsing, write target extraction |
| `workflow-gate.sh` | ~1 | File path extraction from hook input |
| `setup.sh` | ~5 | State initialization, settings config, dependency checks |
| `check-version-sync.sh` | ~3 | Version extraction |

**Scope includes JSON output formatters:** Functions like `emit_deny()` that *produce* JSON (not just parse it) are also migrated. jq can produce JSON output via `jq -n`:
```bash
# Before (python3)
python3 -c "import json; print(json.dumps({'hookSpecificOutput': ...}))"

# After (jq)
jq -n --arg reason "$reason" \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $reason}}'
```

**Read pattern:**
```bash
# Before (python3)
phase=$(python3 -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        d = json.load(f)
    print(d.get('phase', 'off'))
except Exception:
    print('off')
" "$STATE_FILE" 2>/dev/null)

# After (jq)
phase=$(jq -r '.phase // "off"' "$STATE_FILE" 2>/dev/null) || phase="off"
```

**Write pattern (atomic via temp file + mv):**
```bash
# Before (python3, non-atomic)
python3 -c "
import json, sys
with open(filepath, 'r') as f: d = json.load(f)
d['active_skill'] = sys.argv[1]
d['updated'] = sys.argv[2]
with open(filepath, 'w') as f:
    json.dump(d, f, indent=2); f.write('\n')
" "$skill" "$ts" "$STATE_FILE"

# After (jq, atomic)
jq --arg v "$skill" --arg ts "$ts" \
  '.active_skill = $v | .updated = $ts' \
  "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
```

**Key decisions:**
- Atomic writes (temp + mv) address item #5 for free
- Read failures fall through to `|| default`; write failures leave original file intact
- stdin parsing (hook input) replaces python3 with piped jq: `echo "$INPUT" | jq -r '.tool_name // ""'`
- `set -e` safety: all jq calls in hook scripts (`post-tool-navigator.sh`, `bash-write-guard.sh`, `workflow-gate.sh`) must use the `|| fallback` pattern to prevent jq failures on malformed JSON from terminating the hook

**Output format note:** jq default output uses 2-space indent with trailing newline, matching the current python3 `json.dump(d, f, indent=2)` + `f.write('\n')` format. No format flags needed.

**Trade-off:** jq string interpolation is less flexible than Python for complex transforms. For `set_phase`'s large write, we use multi-argument jq filters with `--arg`/`--argjson` flags.

### Phase 3: Generic Read-Modify-Write Helper

After jq migration, extract common write boilerplate into a single helper:

```bash
# _update_state <jq_filter> [--arg name val]... [--argjson name val]...
_update_state() {
    local filter="$1"; shift
    local ts
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    jq --arg ts "$ts" "$@" \
      "$filter | .updated = \$ts" \
      "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
}
```

**Usage:**
```bash
set_active_skill() { _update_state '.active_skill = $v' --arg v "$1"; }
increment_coaching_counter() { _update_state '.coaching.tool_calls_since_agent += 1'; }
set_tracked_observations() { _update_state '.tracked_observations = $v' --argjson v "$1"; }
```

**What stays outside the helper:**
- `set_phase()` — too complex (gate checks, preservation, conditional clearing). Calls `_update_state` for the final write only.
- `set_autonomy_level()` — validation of 1|2|3 stays in function, delegates write to helper.
- `set_last_observation_id()` / `set_tracked_observations()` — create-or-update branching stays in function.

**Net result:** Most setters collapse from 18-30 lines to 1-3 lines. ~200 lines of duplicated boilerplate eliminated.

**Trade-off:** The helper uses `"$@"` pass-through for jq args. Callers must know jq's `--arg`/`--argjson` syntax. Acceptable since all callers are internal functions in the same file.

### Phase 4: `set_phase()` Decomposition

Extract three helpers from `set_phase()`:

**`_check_phase_gates(current, new)` (~30 lines):**
- All hard gate milestone checks
- Returns gate_error message on stdout, non-zero exit on block
- Pure validation — no side effects

**`_read_preserved_state()` (~20 lines):**
- Reads the 6 fields that survive phase transitions (active_skill, decision_record, autonomy_level, last_observation_id, tracked_observations, completion_snapshot)
- Scalar fields (active_skill, decision_record, autonomy_level, last_observation_id) via single jq call with `@tsv` output + `IFS=$'\t' read -r`
- `tracked_observations` (JSON array) and `completion_snapshot` (JSON object) read via separate jq calls since they cannot be safely transported through TSV (may contain tabs/newlines)

**Final write uses `_update_state` from Phase 3:**
- Replaces the 49-line inline Python block

**After decomposition, `set_phase()` becomes ~40-50 lines:**
1. Input validation (8 lines — inline)
2. `_check_phase_gates` call + early return
3. `_read_preserved_state` call
4. Clearing/autonomy-init conditionals (15 lines — inline)
5. `_update_state` call with assembled filter

**Trade-off:** Three new private functions add indirection. Each is independently testable with a single responsibility.

### Phase 5: Quick Wins (Items 1, 5, 6)

**Item 1 — Hard gate phase-unchanged assertions:**
Add 3 assertions to existing tests in `tests/run-tests.sh`:
- After line ~343 ("hard gate blocks leaving IMPLEMENT"): `assert_eq "implement" "$(get_phase)" "phase unchanged after implement gate block"`
- After line ~362 ("hard gate blocks leaving COMPLETE"): `assert_eq "complete" "$(get_phase)" "phase unchanged after complete gate block"`
- After line ~411 ("COMPLETE gate blocks complete→implement"): `assert_eq "complete" "$(get_phase)" "phase unchanged after complete→implement gate block"`

~10 lines of test code. No production code changes.

**Item 5 — Concurrent write documentation:**
Addressed by jq migration's atomic write pattern (temp + mv). One-line comment in `_update_state` noting the atomicity guarantee.

**Item 6 — Duplicate plugin.json:**
No changes. Structural necessity (plugin install location vs repo root). Mitigated by `check-version-sync.sh`. Accepted as-is.

## Files Modified

| File | Changes |
|------|---------|
| `plugin/scripts/workflow-state.sh` | jq migration, `_update_state` helper, `_check_phase_gates`, `_read_preserved_state`, setter simplification |
| `plugin/scripts/post-tool-navigator.sh` | python3→jq for hook input parsing |
| `plugin/scripts/bash-write-guard.sh` | python3→jq for command parsing |
| `plugin/scripts/workflow-gate.sh` | python3→jq for file path extraction |
| `plugin/scripts/setup.sh` | jq hard requirement, python3→jq for state init |
| `scripts/check-version-sync.sh` | python3→jq for version extraction |
| `tests/run-tests.sh` | Hard gate phase-unchanged assertions, test updates for any behavioral changes |

## Test Strategy

- Existing 322 assertions serve as regression suite through each phase
- Run full test suite after each phase before proceeding to next
- Phase 2 (jq migration) has the largest blast radius — migrate file-by-file in order of complexity: `check-version-sync.sh` → `workflow-gate.sh` → `bash-write-guard.sh` → `setup.sh` → `post-tool-navigator.sh` → `workflow-state.sh`, with a test run between each file
- Add 3 hard gate assertions (item #1) in Phase 5
- No new test files needed — all changes are behavioral equivalences except the gate assertions

## Tech Debt Acknowledged

- Item #6 (duplicate plugin.json) remains as accepted structural debt, mitigated by sync check
- `_update_state` helper assumes jq availability (no python3 fallback) — acceptable given hard dependency enforcement
