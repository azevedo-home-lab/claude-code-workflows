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
