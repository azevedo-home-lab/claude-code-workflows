# Public Release Preparation — Design Spec

**Date:** 2026-03-19
**Status:** Superseded by `2026-03-20-workflow-rework-design.md`
**Scope:** DEFINE phase + outcome validation, GPL v3 licensing, community files, statusline updates

---

## Problem Statement

When Claude Code executes an implementation plan, it can pass tests trivially or deliver code that satisfies plan items without actually solving the original problem. The current workflow (DISCUSS → IMPLEMENT → REVIEW) validates *deliverables* (did we build what the plan said) but not *outcomes* (did we solve the problem we set out to solve).

Additionally, the repository is moving from private to public and needs licensing, community infrastructure, and documentation updates.

## Outcomes

| # | Outcome | Type | Verification |
|---|---------|------|--------------|
| 1 | `/define` command guides users through problem + outcome definition | Functional | Run `/define`, complete the flow, verify `define.json` is created |
| 2 | `/complete` validates outcomes from `define.json` with behavioral evidence | Functional | Create `define.json` with outcomes, run `/complete`, verify each outcome is checked |
| 3 | `/complete` passes normally when no `define.json` exists | Functional | Run `/complete` without `define.json`, verify no outcome validation occurs |
| 4 | DEFINE phase blocks code edits (same as DISCUSS) | Functional | Set phase to `define`, attempt Write/Edit, verify hook blocks it |
| 5 | Statusline shows DEFINE phase in blue | Functional | Set phase to `define`, verify statusline output contains blue DEFINE |
| 6 | `/override define` works | Functional | Run `/override define`, verify phase changes |
| 7 | Repository has GPL v3 license | Structural | LICENSE file exists at repo root |
| 8 | All source files have GPL v3 header | Structural | Shell scripts and templates contain license notice |
| 9 | Community files exist (SECURITY.md, CONTRIBUTING.md, CODE_OF_CONDUCT.md) | Structural | Files exist at repo root |
| 10 | GitHub issue and PR templates exist | Structural | Files exist in `.github/` |
| 11 | README reflects new phase and license | Functional | README mentions DEFINE phase and shows license badge |
| 12 | All existing tests pass after changes | Functional | `tests/run-tests.sh` passes |
| 13 | New tests cover DEFINE phase behavior | Functional | Test cases for DEFINE edit blocking, phase transitions, outcome validation |

## Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| All existing tests pass | 100% | `tests/run-tests.sh` exit code 0 |
| New DEFINE tests pass | 100% | New test cases in `tests/run-tests.sh` exit code 0 |
| No private information in repo | 0 findings | Security audit (already completed — clean) |

---

## A. DEFINE Phase + Outcome Validation

### A1. `/define` Command

**File:** `.claude/commands/define.md`

A guided workflow command (same pattern as `/discuss`, `/review`, `/complete`) that:

1. Sets the workflow phase to `define`
2. Walks the user through 4 sections, one at a time:

**Section 1 — Problem Discovery** (borrowed from design-thinking Empathize)
- Who is affected by this problem?
- What pain or friction are they experiencing?
- What's the current state / workaround?
- Why does this matter now?

**Section 2 — Problem Statement** (borrowed from design-thinking Define)
- Synthesize into a crisp problem statement or "How Might We" framing
- User validates: "Is this the right problem?"

**Section 3 — Outcome Definition** (borrowed from ContextKit success metrics)
- What does success look like? Observable, measurable criteria
- Each outcome must be **verifiable** — expressible as a test that can pass or fail
- Each outcome must specify **how to verify it** (what to do) and **what evidence looks like** (what to observe)
- Classify each outcome by type. The `/define` command should present diverse examples across project types so users understand what good outcomes look like regardless of their domain:

  **Functional outcomes** — the system does what it should
  - Applies to any project: APIs, CLIs, libraries, workflows, scripts, documentation systems
  - Verification means exercising the behavior end-to-end, not just proving code exists
  - Evidence is the observable result: output, response, state change, file produced

  **Non-functional outcomes** — the system meets quality attributes:

  | Category | What it covers | How to verify |
  |----------|---------------|---------------|
  | Performance | Speed, throughput, resource usage | Measure under realistic conditions with concrete thresholds |
  | Security | Access control, input validation, data protection | Attempt the attack vector, demonstrate it's blocked |
  | Reliability | Recovery, degradation, fault tolerance | Simulate the failure, observe the system's response |
  | Usability / UX | Accessibility, discoverability, error clarity | Exercise the user path, observe the experience |
  | Maintainability | Readability, testability, modularity | Review structure, verify test coverage, check documentation |
  | Compatibility | Platforms, environments, versions | Run on each target, verify behavior is consistent |

  The command should adapt its examples to the project context. A CLI tool needs different outcome examples than a web API, a library, or an infrastructure script. The examples should feel natural to what the user is building, not force-fit from a different domain.

- Define **success metrics** — quantifiable measures of whether the outcomes collectively solve the problem
  - Each metric needs: what to measure, what the target is, and how to measure it
  - Some metrics are immediately verifiable (test pass rate, latency under load)
  - Some metrics are long-term and can only be monitored post-release (user adoption, error rate in production) — these should be flagged as such
  - Not every project needs formal metrics — for simple tasks, the outcomes themselves may be sufficient. The command should not force metrics when they'd be artificial

**Section 4 — Boundaries** (borrowed from ContextKit scope)
- What's explicitly in scope?
- What's explicitly out of scope (anti-goals)?
- Any constraints or dependencies?

**Output:** Saves to `docs/plans/define.json` (persisted and version-controlled, survives across sessions, branches, and collaborators).

The file must capture:
- The problem statement and who is affected
- All defined outcomes with their type, verification method, and acceptance criteria
- Success metrics with targets and how to measure them
- Linkage between outcomes and the metrics they support
- Scope boundaries (in-scope, out-of-scope, constraints)
- Creation date

The exact schema and field names are an implementation detail — the plan should determine the structure that best fits. What matters is that `/complete` can programmatically read and iterate over outcomes and metrics to validate them.

**Phase transition:** User runs `/discuss` to move to DISCUSS phase. The brainstorming skill picks up the DEFINE output as starting context.

### A2. Phase Integration

**Phase order:** DEFINE → DISCUSS → IMPLEMENT → REVIEW → OFF

**DEFINE is optional.** Users can enter DISCUSS directly. The `/define` command is the recommended starting point but not enforced as a hard gate.

**Files to update for DEFINE phase recognition:**

| File | Change | Mechanism |
|------|--------|-----------|
| `workflow-gate.sh` | Add `"define"` to edit-blocking phase check | Current code uses `if [ "$PHASE" != "discuss" ]; then exit 0; fi` (single-phase negative check). Convert to multi-phase check: `if [ "$PHASE" != "discuss" ] && [ "$PHASE" != "define" ]; then exit 0; fi` or equivalent case statement. Also make the deny message phase-aware: "Use /discuss to proceed" when in DEFINE, "Use /approve to proceed" when in DISCUSS. |
| `bash-write-guard.sh` | Add `"define"` to write-blocking phase check | Same pattern as `workflow-gate.sh` — convert single-phase check at line 26 to multi-phase check. |
| `post-tool-navigator.sh` | Add DEFINE-specific guidance message | Add `elif` branch for `"define"` phase with guidance text. |
| `workflow-state.sh` | Accept `"define"` as valid phase value | Add `define` to the `case` statement in `set_phase()` that validates phases: `off|discuss|implement|review)` → `off|define|discuss|implement|review)`. |
| `override.md` | Add `define` to valid phases list | Add to the documented valid phases. |

**Edit-blocking behavior:** Identical to DISCUSS — Write, Edit, MultiEdit, NotebookEdit are blocked. Reads, state file writes, and spec/plan file writes are whitelisted. No changes needed to the `DISCUSS_WRITE_WHITELIST` regex — DEFINE uses the same whitelist as DISCUSS.

### A3. Outcome Validation in `/complete`

Modify `/complete` Step 3 (Plan Validation) to add outcome validation alongside existing deliverable validation. This runs after the local commit (Step 2) but before push — if an outcome fails, the agent can fix and re-commit before pushing.

The example outcome tables in Section A1 are instructional content for the `/define` command prompt (guidance for Claude during the DEFINE flow). They are not implementation requirements for the validation logic.

1. Check if `docs/plans/define.json` exists
2. If yes:
   - For each outcome, require **behavioral evidence** (demonstrate, don't just grep)
   - For each success metric, check coverage:
     - Immediately verifiable → validate with evidence
     - Long-term metric → flag as "TO MONITOR: cannot verify pre-release"
   - Flag unlinked metrics: "WARNING: metric X has no outcomes that verify it"
   - Produce outcome checklist with three possible states per item:
     ```
     Outcome Validation:
       [x] <outcome description> — evidence: <what was observed>
       [ ] <outcome description> — FAILED: <what went wrong>

     Success Metrics:
       [x] <metric> <target> — linked to: <outcome(s)> (passed)
       [!] <metric> <target> — TO MONITOR: cannot verify pre-release
       [!] <metric> <target> — WARNING: no outcomes verify this metric
     ```
   - Outcomes are checked with behavioral evidence (demonstrate, don't just grep)
   - Success metrics are cross-referenced: each metric should have at least one outcome linked to it; unlinked metrics are flagged
   - Long-term metrics that can't be verified pre-release are marked "TO MONITOR" (not failures)
   - If any outcome fails: report what failed and ask "Fix now and re-commit, or proceed anyway?" (same pattern as existing plan validation failures)
   - If fix → make fixes, create new commit, re-validate failed outcomes
   - If proceed → note the gaps in the handover observation
3. If no `define.json`: skip outcome validation (DEFINE was optional)

### A4. Statusline Update

**File:** `statusline/statusline.sh`

Add DEFINE phase to the phase display block with distinct color:

| Phase | Color | ANSI |
|-------|-------|------|
| **DEFINE** | **BLUE** | `\033[34m` |
| DISCUSS | YELLOW | `\033[33m` |
| IMPLEMENT | GREEN | `\033[32m` |
| REVIEW | CYAN | `\033[36m` |
| OFF | DIM | `\033[2m` |

---

## B. GPL v3 License

### B1. LICENSE File

Add full GPL v3 license text at repository root.

### B2. License Headers

Add GPL v3 notice to all source files (shell scripts, templates). Standard short form:

```
# Copyright (C) 2026 azevedo-home-lab
# SPDX-License-Identifier: GPL-3.0-only
#
# This file is part of Claude Code Workflows.
# See LICENSE for details.
```

**Files requiring headers:**
- All `.sh` files (install.sh, uninstall.sh, hooks, statusline, tools)
- Template files (claude.md.template, SECURITY.md.template)

---

## C. Community Files

### C1. SECURITY.md

Root-level security policy (not the template). Contents:
- How to report vulnerabilities (email or GitHub security advisory)
- Supported versions
- Scope (what counts as a security issue for a workflow tool)

### C2. CONTRIBUTING.md

- How to set up the development environment
- How to run tests (`tests/run-tests.sh`)
- PR process and expectations
- Code style (shell scripts, markdown)
- Link to CODE_OF_CONDUCT.md

### C3. CODE_OF_CONDUCT.md

Contributor Covenant v2.1 (industry standard).

### C4. GitHub Templates

**`.github/ISSUE_TEMPLATE/bug_report.md`:**
- Steps to reproduce
- Expected vs actual behavior
- Environment (OS, Claude Code version, shell)

**`.github/ISSUE_TEMPLATE/feature_request.md`:**
- Problem description
- Proposed solution
- Alternatives considered

**`.github/PULL_REQUEST_TEMPLATE.md`:**
- Summary of changes
- Related issue
- Test plan
- Checklist (tests pass, docs updated, license headers added)

---

## D. Documentation Updates

### D1. README.md

- Add DEFINE phase to workflow description and phase diagram
- Add GPL v3 license badge
- Add Contributing section linking to CONTRIBUTING.md
- Update phase count from 4 to 5

### D2. Architecture Docs

- Update `docs/reference/architecture.md` phase diagram to include DEFINE
- Update phase descriptions

### D3. Commands Reference

- Add `/define` to `docs/quick-reference/commands.md`
- Update phase transition table

---

## E. Test Updates

Add test cases to `tests/run-tests.sh`:

### DEFINE Phase Tests
- `test_define_phase_blocks_edit` — Write/Edit blocked in DEFINE
- `test_define_phase_blocks_bash_write` — Bash writes blocked in DEFINE
- `test_define_phase_allows_reads` — Read operations pass
- `test_define_phase_allows_state_writes` — `.claude/state/` whitelisted
- `test_define_phase_allows_spec_writes` — `docs/superpowers/specs/` whitelisted

### Phase Transition Tests
- `test_override_to_define` — `/override define` sets phase correctly
- `test_define_to_discuss` — Phase transitions from DEFINE to DISCUSS

### Statusline Tests
- `test_statusline_shows_define_phase` — Statusline displays `[DEFINE]` in blue

### Outcome Validation Tests
- `test_complete_with_define_json` — `/complete` reads and validates outcomes
- `test_complete_without_define_json` — `/complete` skips outcome validation gracefully

---

## Out of Scope

- Changing Superpowers itself (we wrap around it)
- Hard-gating DEFINE (it stays optional/recommended)
- External dependencies (ContextKit, melodic-software — we borrow patterns, not code)
- Plugin marketplace publishing

---

## File Change Summary

| File | Action | Description |
|------|--------|-------------|
| `.claude/commands/define.md` | **Create** | DEFINE phase guided workflow |
| `.claude/hooks/workflow-gate.sh` | Modify | Add `define` to blocked phases |
| `.claude/hooks/bash-write-guard.sh` | Modify | Add `define` to blocked phases |
| `.claude/hooks/post-tool-navigator.sh` | Modify | Add DEFINE guidance message |
| `.claude/hooks/workflow-state.sh` | Modify | Accept `define` as valid phase |
| `.claude/commands/override.md` | Modify | Add `define` to valid phases |
| `.claude/commands/complete.md` | Modify | Add outcome validation pass |
| `statusline/statusline.sh` | Modify | Add DEFINE phase display (blue) |
| `install.sh` | Modify | Copy define.md during install |
| `uninstall.sh` | Modify | Add define.md to cleanup list |
| `tests/run-tests.sh` | Modify | Add DEFINE and outcome validation tests |
| `LICENSE` | **Create** | GPL v3 full text |
| `SECURITY.md` | **Create** | Security policy |
| `CONTRIBUTING.md` | **Create** | Contribution guidelines |
| `CODE_OF_CONDUCT.md` | **Create** | Contributor Covenant v2.1 |
| `.github/ISSUE_TEMPLATE/bug_report.md` | **Create** | Bug report template |
| `.github/ISSUE_TEMPLATE/feature_request.md` | **Create** | Feature request template |
| `.github/PULL_REQUEST_TEMPLATE.md` | **Create** | PR template |
| `README.md` | Modify | Add DEFINE phase, license badge, contributing |
| `docs/reference/architecture.md` | Modify | Update phase diagram |
| `docs/quick-reference/commands.md` | Modify | Add `/define` |
| All `.sh` files | Modify | Add GPL v3 license headers |
| `claude.md.template` | Modify | Add GPL v3 license header |
| `docs/reference/SECURITY.md.template` | Modify | Add GPL v3 license header |
