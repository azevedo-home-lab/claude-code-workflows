# Documentation Improvements — Design Spec

## Problem

The project documentation has inconsistencies from rapid iteration and gaps that make it hard to explain what this project is and why it exists. Specifically:

1. **Stale references** — autonomy levels use old `1|2|3` syntax instead of `off|ask|auto`; deprecated superpowers skill names (`brainstorm`, `write-plan`, `execute-plan`) appear in multiple docs; review agent count is wrong (says 3, actually 5); file organization diagram is incomplete.
2. **No origin story** — the README jumps straight into "four tools" without explaining what problem they solve. The journey from cc-sessions (cross-session memory to fight context rot) to a full workflow enforcement system is undocumented.
3. **No simple walkthrough** — the getting-started guide lists 13 commands in sequence, which overwhelms new users. No concrete "here's what a real session looks like" example exists.
4. **No colleague-friendly explainer** — there's no document suitable for sharing with people who haven't used Claude Code, or who need to evaluate the approach without installing it.
5. **Duplication** — `professional-standards.md` exists in both `docs/reference/` and `plugin/docs/reference/` with identical content.

### Target audiences

- **A) Claude Code users** — already use CC, want to adopt this workflow
- **B) Potential adopters** — may not use CC yet, need to understand both the tool and the workflow
- **C) Technical leaders/managers** — need to evaluate the approach, won't install it themselves

## Approach

Two workstreams: fix inconsistencies surgically across all affected files, then add three pieces of missing content.

### Workstream 1: Fix inconsistencies

#### 1.1 Autonomy level syntax and terminology

**Files affected:**
- `README.md` (lines 33-37) — change `/autonomy 1|2|3` to `/autonomy off|ask|auto`, replace "Level 1/2/3" with descriptive names
- `docs/reference/architecture.md` (lines 167-182) — same changes to the autonomy table and `/autonomy 1|2|3` reference

**Before:**
```
Set via `/autonomy 1|2|3`.
| `▶` | 1 | Supervised | Read-only... |
| `▶▶` | 2 | Semi-Auto | Writes follow... |
| `▶▶▶` | 3 | Unattended | Auto-transitions... |
```

**After:**
```
Set via `/autonomy off|ask|auto` (default: ask).
| `▶` | off | Supervised | All writes blocked regardless of phase. Claude can only read files and research. |
| `▶▶` | ask | Semi-Auto | Writes follow phase rules (blocked in define/discuss/complete, allowed in implement/review). Stops at phase transitions for user approval. |
| `▶▶▶` | auto | Unattended | Full autonomy within phase rules. Auto-transitions between phases, auto-commits. Stops only when user input is needed or before git push. |
```

#### 1.2 Deprecated superpowers skill names

**Files affected:**
- `docs/quick-reference/commands.md` — update Superpowers Skills table and Quick Sequence
- `docs/guides/integration-guide.md` — update Manual Commands table and Recommended Workflow diagram
- `docs/reference/architecture.md` (lines 194-198) — update Component Responsibilities section

**Mapping:**
| Old (deprecated) | Current |
|---|---|
| `/superpowers:brainstorm` | `/superpowers:brainstorming` |
| `/superpowers:write-plan` | `/superpowers:writing-plans` |
| `/superpowers:execute-plan` | `/superpowers:executing-plans` |

#### 1.3 Review agent count

**Files affected:**
- `docs/reference/architecture.md` — mermaid diagram (lines 94-99) shows only 3 review agents; update to show 5 (add governance + hygiene)
- Same file, text workflow section (line 235) — update "3 parallel review agents" to "5 parallel review agents"

**Current mermaid (wrong):**
```
subgraph R3 ["3 Parallel Review Agents"]
    R3A["Code Quality"]
    R3B["Security"]
    R3C["Architecture"]
end
```

**Updated mermaid:**
```
subgraph R3 ["5 Parallel Review Agents"]
    R3A["Code Quality\nDRY, SOLID, YAGNI"]
    R3B["Security\ninjection, credentials"]
    R3C["Architecture\nplan compliance"]
    R3D["Governance\nproduction readiness"]
    R3E["Codebase Hygiene\ndead code, orphans"]
end
```

#### 1.4 File organization diagram

**File:** `docs/reference/architecture.md` (lines 258-279)

Add missing command files to the diagram:
```
│   ├── commands/
│   │   ├── define.md
│   │   ├── discuss.md
│   │   ├── implement.md
│   │   ├── review.md
│   │   ├── complete.md
│   │   ├── off.md               # added
│   │   ├── autonomy.md          # added
│   │   └── proposals.md         # added
```

#### 1.5 Professional standards duplication

**Action:** Replace `docs/reference/professional-standards.md` content with a pointer to the plugin source of truth:

```markdown
# Professional Standards

> This document lives in `plugin/docs/reference/professional-standards.md`.
> See that file for the full content. This pointer exists so doc links don't break.
```

**Rationale:** The plugin copy is what the command files actually read. Maintaining two identical copies invites drift. A pointer preserves existing links while establishing a single source of truth.

### Workstream 2: Add missing content

#### 2.1 Origin story — new "Why" section in README.md

Insert before the "Four tools" line. Target: ~15-20 lines.

**Content outline:**

```markdown
## Why

Claude Code is powerful but undisciplined. Left to its defaults, it:
- Jumps straight to writing code before understanding the problem
- Loses context over long sessions — early decisions get forgotten, hallucinations increase
- Doesn't naturally follow think → plan → build → review → ship
- Produces no auditable record of what was decided and why

This project started as **cc-sessions** — a cross-session memory layer to fight context rot.
We quickly found that memory alone wasn't enough. Claude also needed:
- **Guardrails** to prevent coding before planning (hard edit gates)
- **Structure** to guide each phase of development (coaching + skills)
- **Accountability** through decision records and review pipelines

The result is a workflow enforcement system that makes Claude Code behave like a
disciplined senior engineer: think first, plan second, code third, review before shipping.
```

#### 2.2 Simple walkthrough — replace getting-started "Your First Workflow" section

Replace the current 13-command sequence with a concrete, minimal example. Target: ~30-40 lines.

**Content outline:**

First, a brief summary of what each phase does:

```markdown
### The phases

| Phase | Edits | Purpose |
|-------|-------|---------|
| **OFF** | Allowed | No enforcement — standard Claude Code behavior |
| **DEFINE** | Blocked | Frame the problem: who is affected, what's the pain, what does success look like? Research agents challenge assumptions and structure measurable outcomes. Produces the Problem section of the decision record. |
| **DISCUSS** | Blocked | Brainstorm and design the solution: research approaches, evaluate trade-offs, pick one. Write a step-by-step implementation plan. Produces the Approaches + Decision sections of the decision record. |
| **IMPLEMENT** | Allowed | Execute the plan with TDD. Tests first, code second, commit at checkpoints. |
| **REVIEW** | Allowed | Five parallel review agents (quality, security, architecture, governance, hygiene) analyze changes. Fix findings or acknowledge them. |
| **COMPLETE** | Blocked | Validate outcomes against the plan. Update docs, commit, push. Create a handover record for future sessions. Audit tech debt. Return to OFF. |
```

Then the walkthrough uses a concrete example that includes `/define`:

```markdown
### Example: adding search to a products API

**1. Define the problem** (optional — skip for straightforward tasks)
> /define

Claude asks: who needs search? what do they search for today? what's broken about the current approach? Research agents investigate the domain. Output: a problem statement with measurable success criteria.

**2. Discuss and plan**
> /discuss

Code edits are **blocked**. Claude:
- Asks clarifying questions (e.g., which fields? query syntax? pagination?)
- Researches approaches (e.g., Postgres full-text, Elasticsearch, SQLite FTS5)
- Presents options with trade-offs and a recommendation
- Writes a step-by-step implementation plan

You review the plan. When you're happy with it:

**3. Implement**
> /implement

Edits are **unlocked**. Claude follows the plan:
- Writes tests first (TDD enforced)
- Implements each step, commits at checkpoints
- Pauses for your review at milestones

**4. Review**
> /review

Five review agents analyze the changes in parallel:
code quality, security, architecture, governance, and codebase hygiene.
Findings are presented with severity and recommended fixes.

**5. Complete**
> /complete

Claude validates outcomes against the plan, updates docs if needed,
commits, pushes, creates a handover record for future sessions, and returns to OFF.

**That's the core loop: define → discuss → implement → review → complete.**
`/define` is optional — for simple tasks, start at `/discuss`. Soft gates warn when skipping steps but never block.
```

#### 2.3 Colleague-friendly overview — new `docs/guides/overview.md`

A standalone document suitable for sharing. Target: ~80-100 lines.

**Structure:**

```markdown
# Claude Code Workflows — Overview

## What is this?

A workflow enforcement layer for Claude Code (Anthropic's AI coding assistant)
that structures AI-assisted development into disciplined phases:
define → discuss → implement → review → complete.

## What problem does it solve?

[3-4 paragraphs on: undisciplined AI coding, context rot, no audit trail,
hallucination risk in long sessions]

## How does it work?

[Brief description of the two-layer enforcement model:
hooks block edits until you plan, skills guide quality at each phase]

### The phases
[Same phase summary table as getting-started: OFF, DEFINE, DISCUSS, IMPLEMENT, REVIEW, COMPLETE
with edits status and one-line purpose for each]

### Autonomy levels
[Table with off/ask/auto — full descriptions of what each level allows and blocks,
matching the corrected descriptions from section 1.1]

## What does it produce?

- Decision records (problem → approaches → rationale → outcome)
- Reviewed, tested code with commit-level traceability
- Cross-session handover observations (via claude-mem)
- Tech debt audit at completion

## Getting started
How to install, 2-minute getting started pointer.

## Sources
[Same sources list as README.md — Claude Code, claude-mem, Context Engineering,
Reduce Hallucinations, Claude Code Best Practices, Building Effective Agents,
Effective Harnesses for Long-Running Agents]
```

Note: The "Why" / "What problem does it solve?" section already addresses
technical leaders — it explains risk reduction, audit trails, and the case
for structured AI-assisted development. A separate "For technical leaders"
section would duplicate that content.

## Files modified (summary)

| File | Action |
|---|---|
| `README.md` | Add "Why" section, fix autonomy syntax |
| `docs/reference/architecture.md` | Fix autonomy, skill names, review agent count, file org diagram |
| `docs/quick-reference/commands.md` | Fix deprecated skill names |
| `docs/guides/integration-guide.md` | Fix deprecated skill names |
| `docs/guides/getting-started.md` | Replace 13-command walkthrough with simple example |
| `docs/reference/professional-standards.md` | Replace with pointer to plugin source |
| `docs/guides/overview.md` | **New** — colleague-friendly explainer |

**Total: 6 existing files modified + 1 new file created.**

## Out of scope

- Restructuring the documentation hierarchy
- Touching specs/plans docs (work-in-flight records)
- Modifying plugin command files or agent definitions
- Adding new diagrams beyond updating the existing mermaid

## Risks

- **Low:** The "Why" section in README could become stale as the project evolves. Mitigation: keep it about the problem (which is stable), not the solution (which changes).
- **Low:** The overview.md adds a new file. Mitigation: it fills a gap no existing doc covers, and is referenced from README.

## Trade-offs accepted

- Some duplication between architecture.md workflow description and getting-started walkthrough persists. Fixing this would require a doc restructure that's out of scope.
- The overview.md covers some ground that README also covers. This is intentional — the overview is for sharing externally, the README is for people already in the repo.
