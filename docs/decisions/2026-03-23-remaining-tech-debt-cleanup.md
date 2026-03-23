# Decision Record: Remaining Tech Debt Cleanup

**Date:** 2026-03-23
**Phase:** DISCUSS → IMPLEMENT
**Origin:** Observation #3540 — remaining items from python3→jq migration

## Problem

6 tech debt items remained from the python3→jq migration session. All identified, documented, and deferred during that session.

| # | Priority | Issue | Location |
|---|----------|-------|----------|
| 1 | MEDIUM | Concurrent write corruption — fixed `.tmp` suffix | `workflow-state.sh:24` |
| 2 | LOW | 56 python3 references in test fixtures (33 infrastructure + 23 test inputs) | `tests/run-tests.sh` |
| 3 | LOW | Duplicate plugin.json — version-only sync check | `check-version-sync.sh` |
| 4 | LOW | `_set_section_field` jq filter injection | `workflow-state.sh:430-438` |
| 5 | LOW | Triple fallback in `get_phase` | `workflow-state.sh:55-63` |
| 6 | LOW | No size limit on stored values | All setters in `workflow-state.sh` |

## Decision

- **Chosen approach:** Single-pass cleanup, all 6 items in one commit
- **Rationale:** All fixes are small, non-breaking, independent, and well-understood
- **Trade-offs accepted:**
  - Item 2: test fixtures now depend on jq (same tool as system-under-test), reducing test isolation
  - Item 6: oversized writes are rejected (not truncated) — callers get errors, which is correct behavior
- **Risks identified:** Item 2 has highest volume (56 calls); item 4 changes internal jq filter syntax
- **Tech debt acknowledged:** None — this session clears tech debt

## Implementation Summary

### Step 1: PID-scoped temp files
- Changed `${STATE_FILE}.tmp` → `${STATE_FILE}.tmp.$$` in both `_update_state` and `set_phase`
- Prevents concurrent hook invocations from clobbering each other's temp files

### Step 2: `_set_section_field` + `_reset_section` injection fix
- `_set_section_field`: replaced `.${section}.${field}` interpolation with `setpath([$s, $f]; ...)` using `--arg`
- `_reset_section`: replaced string-built filter with `reduce` over `--argjson fields` array
- Same function signatures, no caller changes needed

### Step 3: Remove triple fallback
- Removed unreachable `${phase:-off}` from `get_phase`, `${level:-2}` from `get_autonomy_level`, `${val:-false}` from `get_message_shown`
- jq's `// "default"` operator already guarantees non-empty output

### Step 4: Size limit in `_update_state`
- Added 10KB guard on output size after jq writes to temp file
- Rejects oversized writes with error to stderr, cleans up temp file
- Also added cleanup of temp file on jq failure

### Step 5: Extended `check-version-sync.sh`
- Now compares `name`, `description`, `license`, `repository` fields between the two `plugin.json` files
- `marketplace.json` stays version-only (different structure)

### Step 6: python3→jq in test fixtures
- Migrated all 33 python3 infrastructure calls to jq equivalents
- 23 remaining python3 references are test inputs for bash-write-guard (must stay — they test that python3 writes get blocked)
