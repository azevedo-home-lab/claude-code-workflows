# Design: Remaining Tech Debt Cleanup — Safe Write & Phase Enum Guard

**Date:** 2026-03-23
**Scope:** `plugin/scripts/workflow-state.sh`
**Origin:** Handover #3615 — items 1, 3, 4, 5 from devil's advocate review

## Problem

After the previous tech debt cleanup session (commit 37152d4), 5 items remained. One (file locking / last-writer-wins) was accepted as documented behavior. The remaining 4 are:

1. **MEDIUM:** `set_phase` and 3 initial-creation paths bypass the 10KB size guard — they write directly to `$STATE_FILE` without the size check that `_update_state` enforces.
2. **LOW:** Non-atomic initial file creation in `set_last_observation_id`, `set_tracked_observations`, `add_tracked_observation` — they use `> "$STATE_FILE"` (direct overwrite) instead of write-to-temp-then-mv.
3. **LOW:** Non-enum phase value from external corruption bypasses enforcement — `get_phase` returns whatever jq reads, and the enforcement `case` in hooks defaults to `exit 0` for unknown values.
4. **LOW:** `_update_state` filter parameter could leak env if exposed to untrusted input — accepted as documented risk (filter is only called internally).

Items 1 and 2 share a root cause: multiple code paths write to `$STATE_FILE` without going through a common safe-write mechanism.

## Chosen Approach: Extract `_safe_write` helper

### Rationale

Extracting the write-temp-size-check-mv pattern into a shared `_safe_write` helper eliminates the class of bug (any new write path that forgets the size guard) rather than patching individual instances. The alternative (inline fixes at each of 4 call sites) duplicates 8 lines of logic 4 times.

### Trade-offs accepted

- One more level of indirection (pipe into `_safe_write` vs inline write)
- Item 4 (env leak) accepted as documented risk — filter parameter is internal-only

### Risks

- Pipe into `_safe_write` changes error propagation — if `jq` fails, the pipe still runs `_safe_write` with empty input. Without `pipefail` (which `workflow-state.sh` does not set), the pipe exit code is `_safe_write`'s, not `jq`'s. Mitigated by `_safe_write` rejecting zero-byte input (see design section 1).

## Design

### 1. New `_safe_write` helper

Located after `_update_state` definition (~line 36). Reads stdin, writes to PID-scoped temp file, enforces 10KB size limit, atomically moves to `$STATE_FILE`.

```bash
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

The zero-byte check is critical: when `jq` fails in a pipe (`jq ... | _safe_write`), `_safe_write` receives empty stdin. Without this check, a failed jq would atomically overwrite the state file with an empty file.

### 2. Refactor `_update_state` to use `_safe_write`

Replace inline temp-file/size-check/mv with pipe into `_safe_write`:

```bash
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

### 3. Refactor 4 direct-write paths to pipe into `_safe_write`

Each direct-write path changes from `> "$STATE_FILE"` (or temp-then-mv) to `| _safe_write`. Error propagation must be preserved — callers that `return` after the write must propagate `_safe_write`'s exit code:

- **`set_last_observation_id`** (initial-creation branch): `jq -n ... > "$STATE_FILE"` becomes `jq -n ... | _safe_write; return $?`
- **`set_tracked_observations`** (initial-creation branch): same pattern
- **`add_tracked_observation`** (initial-creation branch): same pattern
- **`set_phase`** (full state rebuild): `> "${STATE_FILE}.tmp.$$" && mv "${STATE_FILE}.tmp.$$" "$STATE_FILE"` becomes `| _safe_write`

### 4. Phase enum guard in `get_phase`

After reading the phase from jq, validate against known values. Unknown values map to `"off"` (safe default — disables enforcement rather than passing through a case statement that defaults to exit 0).

```bash
case "$phase" in
    off|define|discuss|implement|review|complete) ;;
    *) phase="off" ;;
esac
```

### 5. Document accepted risk (item 4)

Add a comment above the `_update_state` function definition:

```bash
# SECURITY NOTE: The $filter parameter is interpolated into jq. This is safe
# because all callers are within this file with hardcoded filter strings.
# Do not expose _update_state to untrusted input.
```

## Test Plan

### New tests (~5 tests)

1. **`_safe_write` rejects oversized input** — pipe >10KB into `_safe_write`, verify rejection, error message to stderr, and temp file cleanup
2. **`_safe_write` rejects zero-byte input** — pipe empty input into `_safe_write`, verify rejection and temp file cleanup (no error message — silent failure for pipe-from-failed-jq case)
3. **Initial-creation via `_safe_write` produces valid JSON** — call `set_last_observation_id` with no pre-existing state file, verify resulting file is valid JSON containing the expected observation ID
4. **`get_phase` returns "off" for unknown phase string** — write a state file with `"phase": "bogus"`, verify `get_phase` returns `"off"`
5. **`get_phase` returns "off" for null phase** — write a state file with `"phase": null`, verify `get_phase` returns `"off"`

### Existing test coverage (preserved)

- 372 tests pass at baseline
- Size guard rejection tests (from previous session)
- jq failure cleanup tests
- Zero-byte state file handling tests

## Files Modified

- `plugin/scripts/workflow-state.sh` — all changes
- `tests/run-tests.sh` — new test cases
- `docs/decisions/2026-03-23-remaining-tech-debt-cleanup.md` — update with new items resolved
