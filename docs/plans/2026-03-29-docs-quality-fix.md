# Documentation Quality Fix

## Problem

The documentation rework from the previous session was partially executed with significant drift from the agreed spec. architecture.md became AI slop — over-documented with nested tables, inconsistent diagram styles (ASCII + Mermaid), and the Mermaid diagram ignored the user's explicit layout spec. Phase tables are duplicated across 4-5 files. The Diamond terminology adds no value in a technical reference. See GitHub issue #25 for root cause analysis.

## Goals and Non-Goals

**Goals:**
- Rewrite architecture.md as a clean, scannable technical reference
- Mermaid diagram with horizontal phases and vertical steps beneath (as originally specified)
- Single source of truth for phase table (README owns it, others link)
- Consistent diagram style (Mermaid only, no ASCII art)
- Remove all duplication across docs

**Non-Goals:**
- Folder restructure (handled separately by docs-restructure plan)
- Code changes
- New documentation files

## Design Decisions (binding — re-read before each task)

1. **Mermaid diagram layout**: Phases as top boxes arranged horizontally L→R. Under each phase, vertical column of steps, gates, and outputs. No prose inside boxes. Transition arrows show /command triggers.
2. **No Diamond terminology**: Remove from all docs. Phases are just phases.
3. **Phase table**: Lives in README only. All other docs link to `README.md#workflow`.
4. **Autonomy table**: Lives in README only. All other docs link to `README.md#autonomy-levels`.
5. **Diagram style**: Mermaid everywhere. No ASCII art diagrams.
6. **Brevity rule**: If it can be one sentence, it's one sentence. No nested subsections with example messages. No tables with 5+ columns.

---

## Task 1: Rewrite architecture.md

**Files:** `docs/reference/architecture.md`

**Source files to read for accuracy before writing:**
- `plugin/scripts/post-tool-navigator.sh`
- `plugin/scripts/workflow-state.sh`
- `plugin/scripts/workflow-gate.sh`
- `plugin/scripts/bash-write-guard.sh`

**Target structure (this IS the document outline):**

```
# Architecture

One-line description.

## System Overview
Mermaid diagram: 3 components (Hooks, Superpowers, claude-mem) and how they connect to Claude Code CLI.

## Phase Model
Mermaid diagram: horizontal phases, vertical steps beneath.
Link to README for the phase summary table.
One sentence about /phase jumping and soft gates.

## Autonomy Levels
Link to README for the autonomy table.
One sentence about enforcement (hooks are source of truth, autonomy controls checkpoint granularity).

## Enforcement
One summary table: 3 layers + hard gates (4 rows total).
One paragraph per layer (not a subsection — a paragraph).
Layer 3 paragraph includes pipeline-abandoned detection in one sentence.

## Gates and Milestones
Hard gates table (4 transitions, required milestones, rationale).
Soft gates: 3 bullet points.
Milestones per phase: one table.

## Write Blocking
Whitelist tiers table (3 rows).
One sentence about guard-system self-protection.
One sentence about bash write guard.

## File Organization
Keep current tree diagram (update if needed).

## Security
Keep current section as-is.
```

**Verification after writing:**
- Zero occurrences of "Diamond"
- Zero occurrences of "decision record"
- Zero ASCII art diagrams
- No section exceeds 30 lines
- No duplicate tables within the document
- Mermaid diagram matches the layout spec in Decision #1

---

## Task 2: Trim hooks.md

**Files:** `docs/reference/hooks.md`

- Delete the ASCII architecture diagram (lines 12-22)
- Delete the Permission Matrix table (link to architecture.md#write-blocking instead)
- Delete PostToolUse three-layer description (link to architecture.md#enforcement instead)
- Keep: Overview paragraph, Files section, Hook Details (workflow-gate.sh, bash-write-guard.sh, workflow-state.sh), Commands, Configuration, Check Order, Known Limitations

---

## Task 3: Clean commands.md

**Files:** `docs/reference/commands.md`

- Delete the Quick Sequence section at bottom
- Delete the Auto-Activated Skills table (this info lives in architecture.md under Superpowers component)
- Keep: Workflow Manager commands table, Superpowers Skills table, claude-mem commands table

---

## Task 4: Verify getting-started.md

**Files:** `docs/guides/getting-started.md`

- Confirm no phase table exists (should already be removed)
- Confirm links point to correct files
- No changes expected — verification only

---

## Task 5: Update README as single source

**Files:** `README.md`

- Remove Diamond column from phase table (if present — check current state)
- Ensure phase table and autonomy table are clean and authoritative
- These are THE tables that all other docs reference
