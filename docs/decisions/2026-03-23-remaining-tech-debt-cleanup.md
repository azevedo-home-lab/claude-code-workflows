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
- **Risks identified:** Pipe changes error propagation — mitigated by zero-byte rejection in `_safe_write` plus `pipefail` subshell in `_update_state`
- **Constraints applied:** `_update_state` wraps pipe in `( set -o pipefail; ... )` for defense-in-depth; initial-creation paths use zero-byte check as sole guard (jq -n failure is near-impossible)
- **Tech debt acknowledged:** See Remaining Tech Debt section below
- **Spec:** `docs/superpowers/specs/2026-03-23-remaining-tech-debt-design.md`

### Implementation Summary (Round 2)

1. **`_safe_write` helper** — new function at `workflow-state.sh:18-37`. Reads stdin → PID-scoped temp → zero-byte check → 10KB size guard → atomic `mv`. All 5 write paths now pipe through it.
2. **`_update_state` refactored** — pipes jq output through `_safe_write` in a `( set -o pipefail; ... )` subshell. Security comment added above function.
3. **3 initial-creation paths refactored** — `set_last_observation_id`, `set_tracked_observations`, `add_tracked_observation` pipe through `_safe_write` with `return $?` for error propagation.
4. **`set_phase` refactored** — final jq write pipes through `_safe_write` instead of inline temp+mv.
5. **Phase enum guard** — `get_phase` validates against known phase values; unknown defaults to `"off"`.
6. **Review fixes** — zero-byte diagnostic message added, `pipefail` subshell added, failure propagation test added.

### Beneficial Deviations from Plan

- `_safe_write` placed before `_update_state` (necessary — bash requires definition before use)
- Zero-byte rejection emits diagnostic stderr message (plan said silent; aids debugging)
- `_update_state` wrapped in `pipefail` subshell (plan didn't include; defense-in-depth)
- Commit granularity: 3 commits instead of 7 (batched for cleaner history)

## Outcome Verification (COMPLETE phase)

- [x] `_safe_write` helper exists with zero-byte, size, and atomic-mv guards — PASS — `workflow-state.sh:18-37`
- [x] `_update_state` pipes through `_safe_write` — PASS — `workflow-state.sh:48-54`
- [x] All 5 direct-write paths use `_safe_write` — PASS — zero `> "$STATE_FILE"` matches remain
- [x] Phase enum guard in `get_phase` — PASS — `workflow-state.sh:90-93`, unknown → "off"
- [x] Security comment on `_update_state` — PASS — `workflow-state.sh:38-40`
- [x] 5 spec tests implemented — PASS — `tests/run-tests.sh:1981-2027`
- [x] 2 extra tests from review (zero-byte message, failure propagation) — PASS — `tests/run-tests.sh:1998, 2029-2036`
- [x] All 384 tests pass — PASS
- **Unresolved items:** 2 hardening improvements identified by devil's advocate (see Remaining Tech Debt)

## Remaining Tech Debt (from Round 2 devil's advocate)

| # | Priority | Issue | Proposed Fix | Effort |
|---|----------|-------|--------------|--------|
| 1 | MEDIUM | `_safe_write` mv failure leaves temp file behind | Add `|| { rm -f "$tmpfile"; return 1; }` after `mv` | S |
| 2 | MEDIUM | Disk-full partial write bypasses guards (cat writes partial, non-zero, passes size check) | Add `jq -e . "$tmpfile" >/dev/null 2>&1` JSON validity check before `mv` | S |
| 3 | LOW | `set_phase` and initial-creation paths lack `pipefail` (unlike `_update_state`) | Wrap in `( set -o pipefail; ... )` for consistency, or document why not needed | S |
| 4 | LOW | Stale temp files after abnormal termination not cleaned up | Add `find "$STATE_DIR" -name '*.tmp.*' -mmin +5 -delete` in setup or session start | S |
| 5 | LOW | `set_tracked_observations` fails entirely if any CSV element is non-numeric | Use `try tonumber catch empty` in jq filter to skip invalid entries | S |
