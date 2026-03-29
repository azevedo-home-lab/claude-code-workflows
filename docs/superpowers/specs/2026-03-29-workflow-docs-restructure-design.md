# Workflow Documentation Restructure

## Problem

The workflow documentation system has four overlapping folders (`docs/superpowers/specs/`, `docs/superpowers/plans/`, `docs/plans/`, `docs/decisions/`), inconsistent naming (some files have `-design` suffix, some `-decision`, some neither), and backwards terminology (what the system calls "specs" are actually high-level design docs, and what it calls "plans" are actually detailed task lists). Decision records exist as a separate concept but are barely used (3 out of ~30 features). The IMPLEMENT phase produces no documentation at all — only code.

## Goals and Non-Goals

**Goals:**
- Clear folder structure: one phase, one folder, one file type
- Correct terminology: Plan = what/why (comes first), Spec = detailed how (comes second)
- Every feature gets at least a light spec, even when jumping to IMPLEMENT
- Architecture decisions recorded as part of the plan, not as orphaned files
- Restricted file updates delivered as a single runnable script (not piecewise edits)

**Non-Goals:**
- Changing the workflow phases themselves (DEFINE/DISCUSS/IMPLEMENT/REVIEW/COMPLETE)
- Adding new documentation types (no implementation reports or logs)
- Changing how observations or handovers work

## Research

**Industry standards reviewed:**

- **ADRs (Architecture Decision Records):** Michael Nygard's 2011 proposal — short, immutable markdown docs stored in repo. Structure: Title, Status, Context, Decision, Consequences. MADR variant adds "Considered Alternatives." ThoughtWorks recommends keeping them under 2 pages and treating them as immutable (supersede, never edit).

- **RFCs in software projects:** Rust RFC process is the gold standard — Summary, Motivation, Detailed Design, Drawbacks, Alternatives, Unresolved Questions. Google's internal "design docs" follow a similar pattern: Context, Goals/Non-Goals, Proposed Solution, Alternatives, Security/Operational considerations.

- **Plan vs Spec vs Design Doc (standard ordering):**
  - Plan = scope, milestones, what/why (project management artifact, comes first)
  - Design Doc / RFC = technical approach, architecture, tradeoffs (comes second)
  - Spec = precise behavioral contract, requirements, acceptance criteria (most detailed, comes last)

- **Implementation records:** No widely-adopted standard exists for documenting what was actually built vs planned. Industry consensus: git history, PR descriptions, issue trackers, and code comments are the accepted practice.

- **Lightweight vs heavyweight:** Google's heuristic — write a design doc if the project takes more than one engineer-month. ThoughtWorks — ADRs are always lightweight; if your ADR is more than 2 pages, it's probably a design doc. Reversibility test (Fowler) — if you can easily undo it, don't over-document it.

## Approaches Considered

### Approach A: Two-folder, two-phase model
- `docs/plans/` (DISCUSS output) + `docs/specs/` (IMPLEMENT output)
- Clear phase ownership, ADR folded into plan's Decision section
- Pros: Simple, clear ownership, fewer artifacts
- Cons: Migration work across 10+ restricted files, 62 files need renaming with crossover

### Approach B: Single-folder model
- `docs/features/` — one file per feature, growing through phases
- Pros: Simplest structure, everything in one place
- Cons: Files get long, harder to distinguish phase outputs, write guards need per-section logic

### Approach C: Three-folder model with explicit ADRs
- `docs/plans/` + `docs/specs/` + `docs/decisions/`
- Pros: Most standards-compliant (Nygard ADR pattern)
- Cons: Reintroduces the standalone decision record that was already failing in practice

## Decision

- **Chosen approach:** A — Two-folder, two-phase model
- **Rationale:** Maps cleanly to the natural flow (plan before spec), each phase owns its folder, and embedding ADR content in the plan eliminates the overhead that caused decision records to be skipped
- **Trade-offs accepted:** Migration requires updating 10+ restricted files; existing naming crossover (current "specs" become plans, current "plans" become specs) could cause momentary confusion during transition
- **Risks:** Brainstorming skill (external, in superpowers plugin) references `docs/superpowers/specs/` — must be updated or overridden

---

## Design

### 1. Folder Structure

```
docs/
├── plans/          ← DISCUSS phase output
│   └── YYYY-MM-DD-<topic>.md
├── specs/          ← IMPLEMENT phase output
│   └── YYYY-MM-DD-<topic>.md
```

Eliminated:
- `docs/superpowers/specs/` — migrated to `docs/plans/`
- `docs/superpowers/plans/` — migrated to `docs/specs/`
- `docs/superpowers/` — deleted after migration
- `docs/decisions/` — content folded into relevant plans, then deleted
- `docs/plans/*-decisions.md` — content folded into relevant plans

### 2. Plan Document Template (DISCUSS Output)

Written by DISCUSS phase. DEFINE seeds the file with Problem + Goals/Non-Goals; DISCUSS enriches it with Research, Approaches, and Decision.

Path: `docs/plans/YYYY-MM-DD-<topic>.md`

```markdown
# <Topic>

## Problem
What's wrong, what needs to change, and why.

## Goals and Non-Goals
- **Goals:** What success looks like (verifiable outcomes)
- **Non-Goals:** What we're explicitly not doing

## Research
Findings from diverge phase — technical approaches investigated,
case studies, prior art, relevant patterns. Sources cited where applicable.

## Approaches Considered

### Approach A: <name>
- Description
- Pros / Cons

### Approach B: <name>
- Description
- Pros / Cons

## Decision
- **Chosen approach:** <which>
- **Rationale:** Why this over alternatives
- **Trade-offs accepted:** What downsides we're taking on
```

### 3. Spec Document Template (IMPLEMENT Output)

Written by IMPLEMENT phase before writing code. When a plan exists, references it. When no plan exists (user jumped to IMPLEMENT), adds a Context & Intent section instead.

Path: `docs/specs/YYYY-MM-DD-<topic>.md`

The spec template has two variants based on whether a plan exists. The phase command instructions (in `plugin/commands/implement.md`) determine which variant to use: if `get_plan_path` returns a non-empty value, use the plan reference header; otherwise, include the Context & Intent section.

```markdown
# <Topic> — Specification

**Plan:** `docs/plans/YYYY-MM-DD-<topic>.md`

## Functional Requirements
What the system must do — behaviors, inputs, outputs, state changes.

## Non-Functional Requirements
Performance, security, compatibility, maintainability constraints.

## Implementation Tasks

### Task 1: <name>
- Files affected
- What to do

## Acceptance Criteria
- [ ] Functional requirements verified (tests pass)
- [ ] Documentation updated
- [ ] Observability (logging, status, error messages)
- [ ] Security considerations addressed
- [ ] Architecture compliance (follows existing patterns)

## Deviations from Plan
(This section is NOT included by IMPLEMENT. REVIEW adds it only if deviations are found.)

## Technical Notes
Non-obvious implementation details, edge cases, constraints
discovered during implementation. (Optional — only if needed.)
```

When no plan exists (user jumped to IMPLEMENT), the `**Plan:**` line is replaced with:

```markdown
## Context & Intent
One paragraph: what we're building and why.
```

### 4. Phase Ownership

| Phase | Writes to | What |
|-------|-----------|------|
| DEFINE | `docs/plans/` | Problem brief (Problem + Goals/Non-Goals) |
| DISCUSS | `docs/plans/` | Enriches problem brief into full plan (Research, Approaches, Decision) |
| IMPLEMENT | `docs/specs/` + code | Spec document + implementation |
| REVIEW | `docs/specs/` | Updates existing spec if deviations found (no new files) |
| COMPLETE | Project docs, GitHub, observations | README and project files updated, issues closed/opened, observations written, handover |

### 5. Write Guard Changes

DEFINE/DISCUSS restricted whitelist:
- Old: `.claude/state/` + `docs/superpowers/specs/` + `docs/superpowers/plans/` + `docs/plans/`
- New: `.claude/state/` + `docs/plans/`

COMPLETE docs whitelist unchanged: `docs/` + root `*.md`

### 6. Workflow State Changes

- `set_decision_record` / `get_decision_record` → renamed to `set_plan_path` / `get_plan_path`
- New: `set_spec_path` / `get_spec_path` for IMPLEMENT phase
- Both preserved across phase transitions
- Soft gate for IMPLEMENT: checks if plan file exists AND has a Decision section (a partial plan from DEFINE without DISCUSS is flagged as incomplete, but still doesn't block)

### 7. Coaching Trigger Changes

- `decision_record_define` → removed
- `decision_record_edit` → removed
- `plan_write` → updated to check `docs/plans/` only
- New: `spec_write` trigger for IMPLEMENT phase

### 8. Migration Strategy

**Doc file migration (unrestricted — agent can execute):**

1. `git mv` current `docs/superpowers/specs/*-design.md` → `docs/plans/` (drop `-design` suffix)
2. `git mv` current `docs/superpowers/plans/*.md` → `docs/specs/`
3. Orphan files in `docs/superpowers/specs/` (no `-design` or `-decision` suffix):
   - `2026-03-22-autonomy-levels.md` → merge into `docs/plans/2026-03-22-autonomy-levels.md` (collision with step 1's `-design` file; append as supplementary content)
   - `2026-03-22-claude-mem-integration.md` → `docs/plans/`
   - `2026-03-25-intent-file-redesign.md` → `docs/plans/`
   - `2026-03-25-phase-token-security-model.md` → `docs/plans/`
   - `2026-03-25-phase-transition-security.md` → `docs/plans/`
   - `2026-03-29-dual-hook-execution-bug.md` → `docs/plans/`
   - `2026-03-29-workflow-docs-restructure-design.md` → `docs/plans/2026-03-29-workflow-docs-restructure.md` (this spec, self-migrating)
4. Decision file folding:
   - Files with a matching design doc: append Decision content as a section into the corresponding plan file, then delete the decision file.
     - `2026-03-23-open-issues-cleanup-decision.md` → fold into `docs/plans/2026-03-23-open-issues-cleanup.md`
     - `2026-03-23-tech-debt-cleanup-decision.md` → fold into `docs/plans/2026-03-23-tech-debt-cleanup.md`
     - `2026-03-27-v1.12.0-decisions.md` → fold into `docs/plans/2026-03-27-v1.12.0-robustness-extraction.md`
     - `2026-03-26-guard-hardening-step-enforcement-decisions.md` → fold into `docs/plans/2026-03-26-guard-hardening-step-enforcement.md`
     - `2026-03-26-statusline-debug-decisions.md` → fold into `docs/plans/2026-03-26-statusline-debug.md`
     - `2026-03-27-security-fixes-architecture-cleanup-decisions.md` → fold into `docs/plans/2026-03-27-security-fixes-architecture-cleanup.md`
     - `2026-03-23-remaining-tech-debt-cleanup.md` (from `docs/decisions/`) → fold into `docs/plans/2026-03-23-remaining-tech-debt.md`
   - Files without a matching design doc: rename to plan and keep as standalone (the decision record IS the plan).
     - `2026-03-26-autonomy-aliases-decisions.md` → `docs/plans/2026-03-26-autonomy-aliases.md`
     - `2026-03-26-tech-debt-github-sync-decisions.md` → `docs/plans/2026-03-26-tech-debt-github-sync.md`
     - `2026-03-28-wfm-auth-path-separation-decisions.md` → `docs/plans/2026-03-28-wfm-auth-path-separation.md`
     - `2026-03-15-workflow-enforcement-hooks.md` → `docs/plans/2026-03-15-workflow-enforcement-hooks.md` (already in docs/plans/, just stays)
5. Delete `docs/superpowers/` after all moves
6. Delete empty `docs/decisions/`

**Naming collision check:** Some topics have files in both `docs/superpowers/specs/` (→ plans) and `docs/plans/` (decisions → plans). The fold step (4) handles this by merging content, not overwriting.

**Restricted file updates (single script for user to run):**
A single migration script updates all references across protected files:
- `plugin/scripts/workflow-state.sh` — whitelist regex, rename decision_record functions to plan_path, add spec_path functions, update soft gate
- `plugin/scripts/workflow-gate.sh` — whitelist comment
- `plugin/scripts/bash-write-guard.sh` — whitelist comment
- `plugin/scripts/post-tool-navigator.sh` — coaching triggers, file pattern checks
- `plugin/commands/define.md` — plan creation path (was decision record)
- `plugin/commands/discuss.md` — plan path check, remove decision record references
- `plugin/commands/review.md` — plan/spec lookup paths
- `plugin/commands/complete.md` — plan path lookup
- `plugin/commands/implement.md` — spec creation instructions, `get_plan_path` / `set_spec_path` calls
- `plugin/scripts/setup.sh` — workflow.json init (decision_record → plan_path, add spec_path)

**External dependency:** The brainstorming skill (in superpowers plugin) hardcodes `docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md`. This must be updated in the skill source. The migration script should include a sed replacement for the skill file at its cached location (`~/.claude/plugins/cache/superpowers-marketplace/superpowers/*/skills/brainstorming/brainstorming.md`).
