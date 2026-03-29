# Documentation Improvements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix documentation inconsistencies across 6 files and add 3 pieces of missing content (origin story, simple walkthrough, colleague-friendly overview).

**Architecture:** Documentation-only changes. Two workstreams: surgical fixes to existing files (tasks 1-5), then new content creation (tasks 6-8). Each task targets one file or one logical change.

**Tech Stack:** Markdown. No code changes, no tests.

**Spec:** `docs/superpowers/specs/2026-03-26-documentation-improvements-design.md`

---

### Task 1: Fix autonomy syntax and descriptions in README.md

**Traces to:** Spec section 1.1 (Autonomy level syntax and terminology)

**Files:**
- Modify: `README.md:31-38`

- [ ] **Step 1: Update autonomy section heading and syntax**

Change `/autonomy 1|2|3` to `/autonomy off|ask|auto` and update the level descriptions.

Replace lines 31-38:
```markdown
### Autonomy Levels

Orthogonal to phase, the autonomy level controls how independently Claude operates. Set with `/autonomy off|ask|auto` (default: ask):

- `▶` **Supervised (off)**: All writes blocked regardless of phase. Claude can only read files and research.
- `▶▶` **Semi-Auto (ask)**: Writes follow phase rules (blocked in define/discuss/complete, allowed in implement/review). Stops at phase transitions for user approval.
- `▶▶▶` **Unattended (auto)**: Full autonomy within phase rules. Auto-transitions between phases, auto-commits. Stops only when user input is needed or before git push.
```

- [ ] **Step 2: Verify the change**

Read `README.md` lines 31-38. Confirm:
- Syntax shows `off|ask|auto` not `1|2|3`
- No mention of "Level 1", "Level 2", "Level 3"
- Each level has a full description of what it allows/blocks

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: fix autonomy syntax and descriptions in README

Replace /autonomy 1|2|3 with /autonomy off|ask|auto. Add full
descriptions of what each level allows and blocks."
```

---

### Task 2: Fix autonomy, skill names, review agents, and file org in architecture.md

**Traces to:** Spec sections 1.1, 1.2, 1.3, 1.4

**Files:**
- Modify: `docs/reference/architecture.md:94-99,167-182,194-198,235,258-279`

- [ ] **Step 1: Update autonomy table (lines 167-182)**

Replace the autonomy table and set-via line:

```markdown
## Autonomy Levels

Phase and autonomy are two orthogonal dimensions of control:

- **Phase** (WHAT) — which operations are allowed at each stage of the workflow
- **Autonomy** (HOW MUCH) — how independently Claude proceeds within those permissions

| Symbol | Level | Name | Description |
|--------|-------|------|-------------|
| `▶` | off | Supervised | All writes blocked regardless of phase. Claude can only read files and research. |
| `▶▶` | ask | Semi-Auto | Writes follow phase rules (blocked in define/discuss/complete, allowed in implement/review). Stops at phase transitions for user approval. **Default.** |
| `▶▶▶` | auto | Unattended | Full autonomy within phase rules. Auto-transitions between phases, auto-commits. Stops only when user input is needed or before git push. |

**Enforcement**: Hooks (`workflow-gate.sh`, `bash-write-guard.sh`) are the single source of truth and apply the autonomy check before the phase gate. Claude Code permission modes (`plan`/`default`/`acceptEdits`) are best-effort convenience that mirror the active autonomy level but are not relied upon for enforcement.

Set via `/autonomy off|ask|auto`. Only the user can change it.
```

- [ ] **Step 2: Update deprecated skill names in Component Responsibilities (lines 194-198)**

Replace:
```
- `/superpowers:brainstorm` — requirements refinement
- `/superpowers:write-plan` — plan generation
- `/superpowers:execute-plan` — batch execution with checkpoints
```

With:
```
- `/superpowers:brainstorming` — requirements refinement
- `/superpowers:writing-plans` — plan generation
- `/superpowers:executing-plans` — batch execution with checkpoints
```

- [ ] **Step 3: Update mermaid diagram — review agents (lines 94-99)**

Replace the 3-agent subgraph:
```
subgraph R3 ["3 Parallel Review Agents"]
    direction LR
    R3A["Code Quality\nDRY, SOLID, YAGNI\ncomplexity, naming\n<b>skill: requesting-code-review</b>"]
    R3B["Security\ninjection, credentials\nunsafe operations\n<b>skill: requesting-code-review</b>"]
    R3C["Architecture\nplan compliance\npatterns, boundaries\n<b>skill: requesting-code-review</b>"]
end
```

With 5-agent subgraph:
```
subgraph R3 ["5 Parallel Review Agents"]
    direction LR
    R3A["Code Quality\nDRY, SOLID, YAGNI\ncomplexity, naming\n<b>skill: requesting-code-review</b>"]
    R3B["Security\ninjection, credentials\nunsafe operations\n<b>skill: requesting-code-review</b>"]
    R3C["Architecture\nplan compliance\npatterns, boundaries\n<b>skill: requesting-code-review</b>"]
    R3D["Governance\nproduction readiness\n<b>skill: requesting-code-review</b>"]
    R3E["Codebase Hygiene\ndead code, orphans\n<b>skill: requesting-code-review</b>"]
end
```

Also add mermaid styles for the new nodes (after existing R3C style line):
```
    style R3D fill:#e0f2fe,stroke:#0ea5e9,color:#0c4a6e
    style R3E fill:#e0f2fe,stroke:#0ea5e9,color:#0c4a6e
```

- [ ] **Step 4: Update text workflow section (line 235)**

Replace:
```
  3 parallel review agents: code quality, security, architecture
```

With:
```
  5 parallel review agents: code quality, security, architecture, governance, codebase hygiene
```

- [ ] **Step 5: Update file organization diagram (lines 266-271)**

Replace the commands section:
```
│   ├── commands/
│   │   ├── define.md               # /define command
│   │   ├── discuss.md              # /discuss command
│   │   ├── implement.md            # /implement command
│   │   ├── review.md               # /review command
│   │   └── complete.md             # /complete command
```

With:
```
│   ├── commands/
│   │   ├── define.md               # /define command
│   │   ├── discuss.md              # /discuss command
│   │   ├── implement.md            # /implement command
│   │   ├── review.md               # /review command
│   │   ├── complete.md             # /complete command
│   │   ├── off.md                  # /off command
│   │   ├── autonomy.md             # /autonomy command
│   │   └── proposals.md            # /proposals command
```

- [ ] **Step 6: Verify all changes**

Read `docs/reference/architecture.md` and verify:
- Autonomy table uses `off|ask|auto` with full descriptions
- Skill names use `brainstorming`, `writing-plans`, `executing-plans`
- Mermaid diagram shows 5 review agents with R3D and R3E nodes + styles
- Text workflow says "5 parallel review agents"
- File org diagram lists all 8 command files

- [ ] **Step 7: Commit**

```bash
git add docs/reference/architecture.md
git commit -m "docs: fix autonomy, skill names, review agents, file org in architecture

Update autonomy to off/ask/auto with full descriptions. Fix deprecated
skill names. Update review agent count from 3 to 5 (add governance +
hygiene). Add missing off.md, autonomy.md, proposals.md to file diagram."
```

---

### Task 3: Fix deprecated skill names in commands.md

**Traces to:** Spec section 1.2

**Files:**
- Modify: `docs/quick-reference/commands.md`

- [ ] **Step 1: Update Superpowers Skills table (lines 17-19)**

Replace:
```
| `/superpowers:brainstorm` | Requirements | Structured Q&A to refine requirements |
| `/superpowers:write-plan` | Planning | Generate numbered implementation plan |
| `/superpowers:execute-plan` | Implementation | Batch execution with review checkpoints |
```

With:
```
| `/superpowers:brainstorming` | Requirements | Structured Q&A to refine requirements |
| `/superpowers:writing-plans` | Planning | Generate numbered implementation plan |
| `/superpowers:executing-plans` | Implementation | Batch execution with review checkpoints |
```

- [ ] **Step 2: Update Quick Sequence (lines 45-48)**

Replace:
```
/superpowers:brainstorm          → Clarify requirements
/superpowers:write-plan          → Generate plan
...
/superpowers:execute-plan        → Implement with checkpoints
```

With:
```
/superpowers:brainstorming       → Clarify requirements
/superpowers:writing-plans       → Generate plan
...
/superpowers:executing-plans     → Implement with checkpoints
```

- [ ] **Step 3: Verify and commit**

Read `docs/quick-reference/commands.md`. Confirm no occurrences of `brainstorm`, `write-plan`, or `execute-plan` (without the `-ing`/`-s` suffix) remain.

```bash
git add docs/quick-reference/commands.md
git commit -m "docs: fix deprecated skill names in command reference

Replace brainstorm/write-plan/execute-plan with current names
brainstorming/writing-plans/executing-plans."
```

---

### Task 4: Fix deprecated skill names in integration-guide.md

**Traces to:** Spec section 1.2

**Files:**
- Modify: `docs/guides/integration-guide.md`

- [ ] **Step 1: Update Manual Commands table (lines 13-15)**

Replace:
```
| `/superpowers:brainstorm` | Before any feature work | Structured Q&A, refined requirements |
| `/superpowers:write-plan` | After requirements are clear | Numbered implementation plan with testing steps |
| `/superpowers:execute-plan` | When plan is approved | Batch execution with review checkpoints |
```

With:
```
| `/superpowers:brainstorming` | Before any feature work | Structured Q&A, refined requirements |
| `/superpowers:writing-plans` | After requirements are clear | Numbered implementation plan with testing steps |
| `/superpowers:executing-plans` | When plan is approved | Batch execution with review checkpoints |
```

- [ ] **Step 2: Update Recommended Workflow diagram (lines 33-42)**

Replace all deprecated skill names in the workflow diagram:
```
/superpowers:brainstorming       # Clarify requirements
...
/superpowers:writing-plans       # Generate plan
...
/superpowers:executing-plans     # Implement with checkpoints
```

- [ ] **Step 3: Verify and commit**

Read `docs/guides/integration-guide.md`. Confirm no deprecated names remain.

```bash
git add docs/guides/integration-guide.md
git commit -m "docs: fix deprecated skill names in integration guide

Replace brainstorm/write-plan/execute-plan with current names."
```

---

### Task 5: Replace professional-standards.md with pointer

**Traces to:** Spec section 1.5

**Files:**
- Modify: `docs/reference/professional-standards.md`

- [ ] **Step 1: Replace file content with pointer**

Replace the entire file content with:

```markdown
# Professional Standards

> This document lives in `plugin/docs/reference/professional-standards.md`.
> See that file for the full content. This pointer exists so doc links don't break.
```

- [ ] **Step 2: Verify the pointer target exists**

Read `plugin/docs/reference/professional-standards.md` line 1 to confirm the source of truth file exists and has content.

- [ ] **Step 3: Commit**

```bash
git add docs/reference/professional-standards.md
git commit -m "docs: replace professional-standards.md with pointer to plugin source

The plugin copy at plugin/docs/reference/professional-standards.md is the
source of truth read by command files. This prevents content drift between
two identical copies."
```

---

### Task 6: Add "Why" section to README.md

**Traces to:** Spec section 2.1

**Files:**
- Modify: `README.md:5-7`

- [ ] **Step 1: Insert "Why" section before the tools description**

After line 5 (`Structured development with Claude Code. Think before coding, review before shipping.`), insert:

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

- [ ] **Step 2: Verify placement**

Read `README.md` lines 1-25. Confirm the "Why" section appears after the tagline and before "Four tools that work together".

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: add 'Why' section to README explaining the problem

Explains: undisciplined AI coding, context rot, no audit trail.
Origin story from cc-sessions to full workflow enforcement."
```

---

### Task 7: Replace getting-started walkthrough with phases table and example

**Traces to:** Spec section 2.2

**Files:**
- Modify: `docs/guides/getting-started.md:49-68`

- [ ] **Step 1: Replace "Your First Workflow" section**

Replace lines 49-68 (the current 13-command sequence and closing paragraph) with:

```markdown
## Your First Workflow

### The phases

| Phase | Edits | Purpose |
|-------|-------|---------|
| **OFF** | Allowed | No enforcement — standard Claude Code behavior |
| **DEFINE** | Blocked | Frame the problem: who is affected, what's the pain, what does success look like? Research agents challenge assumptions and structure measurable outcomes. Produces the Problem section of the decision record. |
| **DISCUSS** | Blocked | Brainstorm and design the solution: research approaches, evaluate trade-offs, pick one. Write a step-by-step implementation plan. Produces the Approaches + Decision sections of the decision record. |
| **IMPLEMENT** | Allowed | Execute the plan with TDD. Tests first, code second, commit at checkpoints. |
| **REVIEW** | Allowed | Five parallel review agents (quality, security, architecture, governance, hygiene) analyze changes. Fix findings or acknowledge them. |
| **COMPLETE** | Blocked | Validate outcomes against the plan. Update docs, commit, push. Create a handover record for future sessions. Audit tech debt. Return to OFF. |

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

- [ ] **Step 2: Verify the replacement**

Read `docs/guides/getting-started.md` lines 49-100. Confirm:
- Phase summary table is present with all 6 phases
- DISCUSS says "Brainstorm and design"
- Example includes `/define` as step 1
- Examples use "e.g." prefix
- No deprecated skill names remain

- [ ] **Step 3: Commit**

```bash
git add docs/guides/getting-started.md
git commit -m "docs: replace getting-started walkthrough with phases table and example

Replaces 13-command sequence with a phase summary table explaining what
each phase does, followed by a concrete example that includes /define."
```

---

### Task 8: Create overview.md — colleague-friendly explainer

**Traces to:** Spec section 2.3

**Files:**
- Create: `docs/guides/overview.md`

- [ ] **Step 1: Write the overview document**

Create `docs/guides/overview.md` with the following content (~80-100 lines):

```markdown
# Claude Code Workflows — Overview

A workflow enforcement layer for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) (Anthropic's AI coding assistant) that structures AI-assisted development into disciplined phases: define → discuss → implement → review → complete.

## What problem does it solve?

Claude Code is a powerful AI coding assistant, but left to its defaults it behaves like an eager junior developer: it jumps straight to writing code before understanding the problem, loses track of early decisions as the conversation grows, and produces no auditable record of what was decided or why.

Over long sessions, this gets worse. The context window fills up, older decisions get compressed or forgotten, and the model starts hallucinating — confidently referencing functions that were renamed three steps ago, or implementing a solution that contradicts an earlier design choice.

This project started as **cc-sessions** — a cross-session memory layer to fight context rot. We quickly found that memory alone wasn't enough. Claude also needed guardrails (hard edit gates that prevent coding before planning), structure (coaching and skills that guide each development phase), and accountability (decision records and multi-agent review pipelines).

The result is a workflow enforcement system that makes Claude Code behave like a disciplined senior engineer: think first, plan second, code third, review before shipping.

## How does it work?

Two layers of enforcement work together:

- **Hooks (hard gates)** — PreToolUse hooks that block file writes in certain phases. Claude literally cannot edit code during the planning phases. This is deterministic and cannot be bypassed.
- **Skills (behavioral guidance)** — Prompt-based techniques (brainstorming, TDD, code review, verification) that guide quality at each phase. Claude follows these because the instructions are loaded at phase entry.

### The phases

| Phase | Edits | Purpose |
|-------|-------|---------|
| **OFF** | Allowed | No enforcement — standard Claude Code behavior |
| **DEFINE** | Blocked | Frame the problem: who is affected, what's the pain, what does success look like? Research agents challenge assumptions and structure measurable outcomes. |
| **DISCUSS** | Blocked | Brainstorm and design the solution: research approaches, evaluate trade-offs, pick one. Write a step-by-step implementation plan. |
| **IMPLEMENT** | Allowed | Execute the plan with TDD. Tests first, code second, commit at checkpoints. |
| **REVIEW** | Allowed | Five parallel review agents (quality, security, architecture, governance, hygiene) analyze changes. Fix findings or acknowledge them. |
| **COMPLETE** | Blocked | Validate outcomes against the plan. Update docs, commit, push. Create a handover record for future sessions. Audit tech debt. |

Any phase command can jump to any phase. Soft gates warn when skipping steps but never block.

### Autonomy levels

Orthogonal to phase, the autonomy level controls how independently Claude operates:

| Symbol | Level | Name | Description |
|--------|-------|------|-------------|
| `▶` | off | Supervised | All writes blocked regardless of phase. Claude can only read files and research. |
| `▶▶` | ask | Semi-Auto | Writes follow phase rules. Stops at phase transitions for user approval. **Default.** |
| `▶▶▶` | auto | Unattended | Full autonomy within phase rules. Auto-transitions, auto-commits. Stops only for user input or before git push. |

## What does it produce?

Each workflow cycle produces:

- **Decision records** — problem statement, approaches considered, rationale, chosen approach, outcomes
- **Reviewed, tested code** — TDD-enforced implementation with 5-agent review pipeline
- **Cross-session handover** — persistent observations (via claude-mem) with commit hashes, decisions, and gotchas for the next session
- **Tech debt audit** — every shortcut and trade-off documented and visible

## Four tools that work together

| Tool | What it does |
|------|-------------|
| **Workflow Manager** | Phase-based enforcement with hard edit gates and coaching |
| **Superpowers** | Auto-activated skills for brainstorming, TDD, planning, debugging, code review |
| **claude-mem** | Cross-session memory via MCP server — observations persist across conversations |
| **Status Line** | Context usage, git branch, workflow phase, autonomy level at a glance |

## Getting started

### As a Claude Code Plugin (recommended)

```
/plugin marketplace add azevedo-home-lab/claude-code-workflows
/plugin install workflow-manager
```

The plugin auto-wires hooks, installs the statusline, and initializes project state. No manual configuration needed.

See the [Getting Started guide](getting-started.md) for a walkthrough of your first workflow.

## Sources

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) — Anthropic's AI coding assistant
- [claude-mem](https://github.com/thedotmack/claude-mem) — cross-session memory MCP server
- [Context Engineering for AI Agents](https://docs.claude-mem.ai/context-engineering) — context rot, progressive disclosure, agentic memory
- [Reduce Hallucinations](https://docs.anthropic.com/en/docs/test-and-evaluate/strengthen-guardrails/reduce-hallucinations) — grounding, citations, uncertainty
- [Claude Code Best Practices](https://code.claude.com/docs/en/best-practices) — agentic coding patterns
- [Building Effective Agents](https://www.anthropic.com/research/building-effective-agents) — tool design, evaluation loops
- [Effective Harnesses for Long-Running Agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents) — session state, progress checkpoints
```

- [ ] **Step 2: Add overview link to README.md Docs section**

In `README.md`, in the `## Docs` section, add a line for the overview:

```markdown
- [Overview](docs/guides/overview.md) — what this is, why it exists, how it works
```

Add it as the first item in the list (before Getting Started).

- [ ] **Step 3: Verify**

Read `docs/guides/overview.md` lines 1-10. Confirm file exists and starts with the expected title. Read `README.md` Docs section to confirm the link is present.

- [ ] **Step 4: Commit**

```bash
git add docs/guides/overview.md README.md
git commit -m "docs: add colleague-friendly overview document

Standalone explainer covering what the project is, what problem it
solves, how it works (phases + autonomy), what it produces, and
sources. Suitable for sharing with colleagues who haven't used
Claude Code."
```

---

### Task 9: Final verification sweep

**Traces to:** All spec sections — cross-file consistency check

- [ ] **Step 1: Search for remaining deprecated terms**

Run grep across all docs for:
- `autonomy 1` or `autonomy 2` or `autonomy 3` — should return zero hits outside archive/
- `Level 1` / `Level 2` / `Level 3` in autonomy context — should return zero
- `superpowers:brainstorm` (without `-ing`) — should return zero outside archive/
- `superpowers:write-plan` (without `-s`) — should return zero outside archive/
- `superpowers:execute-plan` (without `-ing`) — should return zero outside archive/
- `3 parallel review` — should return zero

- [ ] **Step 2: Verify all links resolve**

Check that every cross-reference in modified files points to a file that exists:
- `README.md` links: `docs/guides/overview.md`, `docs/guides/getting-started.md`, etc.
- `overview.md` links: `getting-started.md`

- [ ] **Step 3: Fix any remaining issues found**

If grep finds stale references in any file not already addressed, fix them and commit.

- [ ] **Step 4: Final commit if needed**

```bash
git add <files with remaining stale references>
git commit -m "docs: final sweep — fix any remaining stale references"
```

Only commit if there were changes in step 3. If the sweep is clean, skip this step.
