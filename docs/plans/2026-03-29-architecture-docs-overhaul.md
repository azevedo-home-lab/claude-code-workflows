# Architecture Documentation Overhaul — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Overhaul long-lived documentation — rewrite architecture.md as the comprehensive technical reference, consolidate redundant files, and simplify the docs folder structure.

**Architecture:** Delete 3 redundant files (overview.md, integration-guide.md, professional-standards.md pointer). Move commands.md into reference/. Rewrite architecture.md with a single horizontal-flow mermaid diagram showing phases as top boxes with vertical step/gate detail underneath. Trim hooks.md to remove concept duplication (link to architecture.md instead). Fix getting-started.md to link to architecture.md instead of duplicating tables.

**Tech Stack:** Markdown, Mermaid diagrams

---

## Problem

From GitHub issue #24: The enforcement system (phases, 3-layer coaching, gates, milestones, pipeline-abandoned detection) is undocumented. The existing docs have massive redundancy — the phase table appears 5 times across files, the autonomy table 4 times. Three files don't stand alone (overview.md duplicates README, integration-guide.md duplicates getting-started.md, professional-standards.md is a 3-line pointer). architecture.md has 3 overlapping phase-flow representations and still says "Two-Layer Enforcement."

## Decision

**Chosen approach:** Delete redundant files, consolidate into fewer authoritative docs, rewrite architecture.md as the single technical reference.

**Rationale:** Patching would preserve structural duplication. A consolidation reduces 10 long-lived docs to 7, with one authoritative location per concept.

**Trade-offs accepted:** Deleting overview.md breaks any existing bookmarks. Acceptable for a young project. architecture.md grows larger but becomes the single source of truth for system internals.

**Scope:** Documentation only. No code changes.

---

## File Structure

```
AFTER:
docs/
├── guides/
│   ├── getting-started.md             # MODIFY — remove duplicated phase/autonomy tables, link to architecture.md
│   ├── claude-mem-guide.md            # KEEP as-is
│   └── statusline-guide.md           # KEEP as-is
├── reference/
│   ├── architecture.md                # REWRITE — comprehensive technical reference
│   ├── hooks.md                       # MODIFY — trim concept duplication, link to architecture.md
│   └── commands.md                    # MOVE from quick-reference/
├── plans/                             # Out of scope
└── specs/                             # Out of scope

DELETED:
- docs/guides/overview.md
- docs/guides/integration-guide.md
- docs/reference/professional-standards.md (3-line pointer)
- docs/quick-reference/commands.md (moved to reference/)
- docs/quick-reference/ (empty directory)
```

**Source files** (read-only, for content accuracy when writing architecture.md):
- `plugin/scripts/post-tool-navigator.sh` — 3-layer coaching implementation
- `plugin/scripts/workflow-gate.sh` — write/edit blocking, whitelist tiers
- `plugin/scripts/bash-write-guard.sh` — bash write blocking
- `plugin/scripts/workflow-state.sh` — state management, milestones, hard/soft gates

---

### Task 1: Delete Redundant Files and Move commands.md

**Files:**
- Delete: `docs/guides/overview.md`
- Delete: `docs/guides/integration-guide.md`
- Delete: `docs/reference/professional-standards.md`
- Move: `docs/quick-reference/commands.md` → `docs/reference/commands.md`
- Delete: `docs/quick-reference/` (empty after move)

- [ ] **Step 1: Delete overview.md**

```bash
git rm docs/guides/overview.md
```

- [ ] **Step 2: Delete integration-guide.md**

```bash
git rm docs/guides/integration-guide.md
```

- [ ] **Step 3: Delete professional-standards.md pointer**

```bash
git rm docs/reference/professional-standards.md
```

- [ ] **Step 4: Move commands.md to reference/**

```bash
git mv docs/quick-reference/commands.md docs/reference/commands.md
```

- [ ] **Step 5: Remove empty quick-reference directory**

```bash
rmdir docs/quick-reference
```

- [ ] **Step 6: Commit**

```bash
git add -A docs/guides/overview.md docs/guides/integration-guide.md docs/reference/professional-standards.md docs/quick-reference/ docs/reference/commands.md
git commit -m "docs: remove redundant files, move commands.md to reference/"
```

---

### Task 2: Rewrite architecture.md — Header, Overview, and Phase Model

This is the big task. The new architecture.md becomes the comprehensive technical reference.

**Files:**
- Rewrite: `docs/reference/architecture.md`

**Source files to read for accuracy:**
- `plugin/scripts/post-tool-navigator.sh` — phase objectives, done criteria
- `plugin/scripts/workflow-state.sh` — milestones per phase

- [ ] **Step 1: Read source files for accuracy**

Read `plugin/scripts/post-tool-navigator.sh` and `plugin/scripts/workflow-state.sh` to verify all phase details, milestones, and coaching triggers against actual code.

- [ ] **Step 2: Write document header and System Overview**

Keep the existing ASCII diagram (lines 7-28 of current file) — it clearly shows the 3-component architecture (Hooks, Superpowers, claude-mem). Update the description labels if needed.

```markdown
# Architecture

How Workflow Manager, Superpowers, and claude-mem work together in Claude Code.

## System Overview

[existing ASCII diagram — Hooks/Superpowers/claude-mem]
```

- [ ] **Step 3: Write Phase Model with horizontal mermaid diagram**

Replace ALL three existing phase representations (ASCII flow, mermaid, text workflow) with a single mermaid diagram.

**Diagram design:** Phases as top-level boxes arranged horizontally left-to-right following the flow (OFF → DEFINE → DISCUSS → IMPLEMENT → REVIEW → COMPLETE → OFF). Under each phase box, vertical columns showing:
- Steps performed in that phase
- Gates (hard gate icon for blocked transitions, soft gate for warnings)
- What each step produces
- Skills activated
- Milestones tracked

The transition arrows between phase boxes should show the `/command` that triggers them. Include the skip path (OFF → DISCUSS directly).

Follow the diagram with a concise reference table:

```markdown
| Phase | Edits | Diamond | Focus |
|-------|-------|---------|-------|
| OFF | Allowed | — | No enforcement |
| DEFINE | Blocked* | 1 — Problem Space | Frame problem, define outcomes |
| DISCUSS | Blocked* | 2 — Solution Space | Research approaches, write plan |
| IMPLEMENT | Allowed | — | Execute plan with TDD |
| REVIEW | Allowed | — | Multi-agent code review |
| COMPLETE | Blocked** | — | Validate outcomes, handover |

*specs/plans allowed  **docs allowed
```

Do NOT duplicate the phase table anywhere else in the document.

- [ ] **Step 4: Write Autonomy Levels section**

Single table (same content as current lines 178-183). Add enforcement note. This is the ONE place the autonomy table lives.

- [ ] **Step 5: Commit scaffold**

```bash
git add docs/reference/architecture.md
git commit -m "docs: rewrite architecture.md with phase model and mermaid diagram"
```

---

### Task 3: Document Three-Layer Enforcement, Gates, and Milestones

**Files:**
- Modify: `docs/reference/architecture.md`

**Source files to read for accuracy:**
- `plugin/scripts/post-tool-navigator.sh` — all 3 coaching layers
- `plugin/scripts/workflow-state.sh` — hard gates, soft gates, milestone definitions
- `plugin/scripts/workflow-gate.sh` — whitelist tiers

- [ ] **Step 1: Read coaching and gate implementations**

Read the source scripts to verify every detail. Do not speculate — quote the code.

- [ ] **Step 2: Write Three-Layer Enforcement section**

Replace "Two-Layer Enforcement" with comprehensive documentation of all 3 layers:

```markdown
## Three-Layer Enforcement

| Layer | Mechanism | Fires | Can bypass? |
|-------|-----------|-------|-------------|
| **1. Phase Entry Guidance** | Coaching message on first tool use | Once per phase entry | Yes |
| **2. Professional Standards** | Contextual reinforcement | Once per phase, resets after 30 idle tool calls | Yes |
| **3. Anti-Laziness Checks** | Red-flag detection | Every match | Yes |

Hard gates (hooks) additionally block Write/Edit operations — see Gates and Milestones.
```

Then detail each layer with:
- Layer 1: table of phase objectives and done criteria
- Layer 2: trigger conditions and example messages per phase
- Layer 3: full table of all checks (short agent prompts, generic commits, skipped research, pipeline abandoned, etc.) with trigger conditions and applicable phases

- [ ] **Step 3: Write Gates and Milestones section**

Document hard gates (block transitions), soft gates (warn only), and milestones per phase:

Hard gates table:
| Transition | Required Milestones | Rationale |
- DISCUSS → any: `plan_written`
- IMPLEMENT → any: `plan_read`, `tests_passing`*, `all_tasks_complete`
- Skip REVIEW → COMPLETE: `findings_acknowledged`
- COMPLETE → OFF: all 9 milestones

Soft gates table:
| Transition | Warning |
- → IMPLEMENT: no plan
- → REVIEW: no changes
- → COMPLETE: no review

Milestones per phase table:
| Phase | Milestones |
- DEFINE through COMPLETE with all milestone names

- [ ] **Step 4: Write Write Blocking section**

Document whitelist tiers (restrictive for DEFINE/DISCUSS, docs-allowed for COMPLETE, open for IMPLEMENT/REVIEW), guard-system self-protection, and bash write guard summary.

- [ ] **Step 5: Write Pipeline-Abandoned Detection section**

Table with phase, abandoned pattern, detection condition, and coaching message for each:
- DISCUSS: approach selected but plan not written
- IMPLEMENT: tasks complete but tests not run
- REVIEW: agents dispatched but findings not presented
- COMPLETE: pushed but Steps 7-9 incomplete

- [ ] **Step 6: Commit enforcement documentation**

```bash
git add docs/reference/architecture.md
git commit -m "docs: add 3-layer enforcement, gates, milestones, pipeline detection"
```

---

### Task 4: Update Remaining Sections and Fix Terminology

**Files:**
- Modify: `docs/reference/architecture.md`

- [ ] **Step 1: Update Component Responsibilities**

Keep the 3-component structure (Workflow Manager, Superpowers, claude-mem). Fix terminology: all "decision record" → "plan" or "spec". Add auto-activated skills table (migrated from deleted integration-guide.md):

| Skill | Triggers When |
|-------|--------------|
| TDD | Creating new functions/modules |
| Systematic Debugging | Error logs or stack traces |
| Code Review | Refactoring existing code |
| Verification | Before claiming completion |
| Worktrees | Multiple features in parallel |

- [ ] **Step 2: Update File Organization**

Add `docs/specs/` directory. Update `post-tool-navigator.sh` description to "3-layer coaching system". Remove `quick-reference/` (deleted). Reflect the new simplified structure:

```
your-project/
├── .claude/
│   ├── hooks/                         # Enforcement hooks
│   ├── commands/                      # Phase commands (/define, /discuss, etc.)
│   ├── state/
│   │   └── workflow.json              # Workflow state (gitignored)
│   └── settings.json                  # Hook configuration
├── docs/
│   ├── guides/                        # Getting started, claude-mem, statusline
│   ├── reference/                     # Architecture, hooks, commands
│   ├── plans/                         # Implementation plans (per-feature)
│   └── specs/                         # Design specs (per-feature)
├── CLAUDE.md                          # Project rules (committed)
└── src/                               # Your code
```

- [ ] **Step 3: Keep Security section as-is**

No changes needed.

- [ ] **Step 4: Verify no stale terminology**

Search completed file for "decision record" — must be zero occurrences. Search for "two-layer" — must be zero. Search for "quick-reference" — must be zero.

- [ ] **Step 5: Commit final sections**

```bash
git add docs/reference/architecture.md
git commit -m "docs: update components, file org, fix terminology in architecture.md"
```

---

### Task 5: Trim hooks.md — Remove Concept Duplication

**Files:**
- Modify: `docs/reference/hooks.md`

- [ ] **Step 1: Read current hooks.md**

Read `docs/reference/hooks.md` to identify sections that now duplicate architecture.md.

- [ ] **Step 2: Remove duplicated concept sections**

Replace these with cross-references to architecture.md:
- **Phase Model section** (lines 26-42): Replace with "See [Architecture — Phase Model](architecture.md#phase-model) for the full phase model and permissions matrix." Keep only the permission matrix table (it's useful as a quick reference in the hooks context).
- **Autonomy Levels section** (lines 191-216): Replace with "See [Architecture — Autonomy Levels](architecture.md#autonomy-levels)."
- **Coaching System section** (lines 162-189): Replace with "See [Architecture — Three-Layer Enforcement](architecture.md#three-layer-enforcement) for complete coaching documentation." Keep only the implementation-specific details (PostToolUse hook wiring, observation ID capture).

Keep all implementation-specific content:
- Hook Details (workflow-gate.sh, bash-write-guard.sh, workflow-state.sh specifics)
- Files section (plugin directory structure)
- Configuration (hooks.json)
- Check Order
- Known Limitations

- [ ] **Step 3: Commit hooks.md trimming**

```bash
git add docs/reference/hooks.md
git commit -m "docs: trim hooks.md, cross-reference architecture.md for concepts"
```

---

### Task 6: Fix getting-started.md — Remove Duplicated Tables

**Files:**
- Modify: `docs/guides/getting-started.md`

- [ ] **Step 1: Read current getting-started.md**

Read to identify the duplicated phase table.

- [ ] **Step 2: Replace phase table with link**

Replace the phase table (lines 53-60) with:

```markdown
### The phases

Six phases control what's allowed. See [Architecture — Phase Model](../reference/architecture.md#phase-model) for the full reference.

The key rule: **code edits are blocked in DEFINE, DISCUSS, and COMPLETE.** You must plan before you code.
```

Keep the example walkthrough (lines 62-101) — that's the value of this file.

- [ ] **Step 3: Fix "decision record" terminology**

Lines 56-57 mention "decision record" — these are removed with the table replacement. Verify no other instances remain.

- [ ] **Step 4: Update Next Steps links**

Update links at the bottom to reflect new file locations:
- Remove link to integration-guide.md (deleted)
- Update commands.md link path from `../quick-reference/commands.md` to `../reference/commands.md`

- [ ] **Step 5: Commit getting-started.md fixes**

```bash
git add docs/guides/getting-started.md
git commit -m "docs: remove duplicated tables from getting-started.md, fix links"
```

---

### Task 7: Update README Links

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Read README.md Docs and Features sections**

Check lines 65-79 for links that need updating.

- [ ] **Step 2: Update links**

- Remove overview.md link (line 75, file deleted — README itself is the overview)
- Update commands.md link path: `docs/quick-reference/commands.md` → `docs/reference/commands.md`
- Update professional-standards.md link to point to `plugin/docs/reference/professional-standards.md` (canonical location)
- Remove integration-guide.md from Features table (file deleted)

- [ ] **Step 3: Verify all doc links resolve**

Check each link in the Docs and Features sections points to a file that exists.

- [ ] **Step 4: Commit README fixes**

```bash
git add README.md
git commit -m "docs: update README links after documentation consolidation"
```

---

### Task 8: Final Verification and Issue Update

**Files:**
- None (verification only)

- [ ] **Step 1: Verify file structure**

```bash
find docs/ -name "*.md" -not -path "docs/plans/*" -not -path "docs/specs/*" | sort
```

Expected:
```
docs/guides/claude-mem-guide.md
docs/guides/getting-started.md
docs/guides/statusline-guide.md
docs/reference/architecture.md
docs/reference/commands.md
docs/reference/hooks.md
```

Plus `docs/reference/SECURITY.md.template` if it exists.

- [ ] **Step 2: Verify no broken internal links**

Search all remaining docs for links to deleted files:
- `overview.md` — should appear zero times
- `integration-guide.md` — should appear zero times
- `quick-reference/` — should appear zero times
- `professional-standards.md` in docs/reference/ — should appear zero times

- [ ] **Step 3: Verify no stale terminology across all docs**

Search all remaining docs for "decision record" — should appear zero times (except in plans/specs which are out of scope).

- [ ] **Step 4: Read architecture.md end-to-end**

Verify document flow, no duplicate sections, consistent terminology, accurate content sourced from implementation scripts.

- [ ] **Step 5: Comment on issue #24**

```bash
COMMIT_HASH=$(git rev-parse --short HEAD)
gh issue comment 24 --body "## Architecture Documentation Overhaul

**Commit:** $COMMIT_HASH

### Changes
- **Rewrote** \`docs/reference/architecture.md\` — comprehensive technical reference with:
  - Single mermaid diagram (horizontal phases, vertical steps/gates)
  - 3-layer enforcement system (phase guidance, standards reinforcement, anti-laziness)
  - Hard gates, soft gates, milestones per phase
  - Write blocking whitelist tiers
  - Pipeline-abandoned detection
  - Updated file organization and terminology
- **Deleted** 3 redundant files: overview.md, integration-guide.md, professional-standards.md pointer
- **Moved** commands.md from quick-reference/ to reference/
- **Trimmed** hooks.md to remove concept duplication (cross-references architecture.md)
- **Fixed** getting-started.md duplicated tables and links
- **Updated** README.md links

### File count
- Before: 10 long-lived doc files
- After: 6 long-lived doc files + SECURITY.md.template
- Removed: ~400 lines of duplicated content"
```
