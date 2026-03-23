# Tech Debt Cleanup — Decision Record

**Date:** 2026-03-23
**Status:** Decided

## Problem

Six tech debt items from the plugin conversion era remain unresolved:
1. Hard gate tests missing phase-unchanged assertions
2. `set_phase()` at 140 lines — too large
3. 12 setter functions duplicate read-modify-write boilerplate (~200 lines)
4. python3 invoked 50+ times per cycle for JSON ops — slow, heavy dependency
5. No concurrent write protection on workflow.json
6. Duplicate plugin.json

Items 2, 3, 4 are deeply coupled — the setters use python3 and set_phase is the largest setter.

## Approaches Considered (DISCUSS phase — diverge)

### Approach A: jq-first migration (chosen)
Migrate all python3→jq first, then extract generic helper, then decompose set_phase.

- **Pros:** Each step simplifies the next. jq setters are 2-3 lines vs 15-20 python3. Atomic writes come free. Clear dependency chain.
- **Cons:** Large blast radius on jq step. jq becomes hard dependency.

### Approach B: Generic helper first, then jq
Extract read-modify-write helper using python3, then swap internals to jq.

- **Pros:** Smaller blast radius per step. Python3 preserved longer.
- **Cons:** Double work — build python3 helper only to rewrite it.

### Approach C: jq + generic helper simultaneously
Single pass: create jq-based helper and migrate all setters at once.

- **Pros:** Least total code written.
- **Cons:** Hardest to review. All-or-nothing — bugs break everything. Hard to bisect regressions.

## Decision (DISCUSS phase — converge)

- **Chosen approach:** A — jq-first migration
- **Rationale:** jq migration is highest-value change (performance, code reduction, atomic writes). Each subsequent step becomes simpler. Each phase is independently testable against 355-test suite.
- **Trade-offs accepted:** jq becomes hard dependency (acceptable — ubiquitous, lighter than python3). Three new private helper functions add indirection (justified by testability and SRP).
- **Risks identified:** Large blast radius on jq migration step. Mitigated by running full test suite after each phase.
- **Constraints applied:** Bash 3.2 compatibility must be maintained. Existing test suite provides regression safety net.
- **Tech debt acknowledged:** Duplicate plugin.json remains (structural, mitigated by sync check). No python3 fallback for jq.
- **Link to spec:** `docs/superpowers/specs/2026-03-23-tech-debt-cleanup-design.md`

## Item-specific decisions

- **Item 5 (concurrent writes):** Option B — atomic writes via jq's temp+mv pattern, document remaining edge cases. Not implementing flock or advisory locking.
- **Item 6 (duplicate plugin.json):** No changes — accepted as structural necessity.

## Review Findings

**Review date:** 2026-03-23
**Reviewers:** Code Quality, Security, Architecture & Plan Compliance (3 agents)
**Verification:** All findings verified against actual code; 1 false positive removed (disk-full test)

### Critical
None.

### Warnings (fixed)
- **Stale test assertion** (`tests/run-tests.sh:424`): Corrupt JSON test checked for Python "Traceback" which jq never produces. Updated to check for false gate block instead.
- **Missing mismatch test** (`check-version-sync.sh`): Only happy path tested. Added test for version mismatch detection (exit code 1 + error message).

### Suggestions (addressed)
- **`_update_state` missing guard** (`workflow-state.sh:17`): Added `[ ! -f "$STATE_FILE" ]` check as defense-in-depth.
- **Dual-mode exit comment** (`setup.sh:22`): Added explanatory comment for `return 1 2>/dev/null || exit 1` idiom.

### Suggestions (accepted as-is)
- **python3 in test fixtures** (~21 calls): Provides test independence — test setup doesn't go through system-under-test. Documented.
- **Triple fallback in get_phase**: Belt-and-suspenders — negligible cost, prevents empty phase.
- **Individual getter calls in _read_preserved_state**: More readable than single @tsv call. Negligible performance difference.
- **Three file-creation paths bypass _update_state**: Inherent to `jq -n` pattern for creating new files.

## Outcome Verification (COMPLETE phase)
- [x] Outcome 1: Hard gate phase-unchanged assertions — PASS — 3 assertions at run-tests.sh:345,366,417
- [x] Outcome 2: set_phase decomposed — PASS — _check_phase_gates + _read_preserved_state extracted
- [x] Outcome 3: Setter boilerplate eliminated — PASS — _update_state helper, 14+ call sites
- [x] Outcome 4: python3 eliminated — PASS — 0 runtime calls across 6 production files
- [x] Outcome 5: Atomic writes — PASS — temp+mv in _update_state and set_phase
- [x] Outcome 6: Duplicate plugin.json — PASS — accepted as-is, sync check migrated to jq
- Tests: 360 passing, 0 failed
- Boundary tests: 60/60 edge cases pass
- Devil's advocate: 2 known-accepted concurrency findings (documented in Item 5 decision)
- **Unresolved:** Concurrent write corruption with shared .tmp path (accepted per Item 5 decision)
- **Tech debt incurred:** ~21 python3 calls remain in test fixtures (intentional for test independence)
