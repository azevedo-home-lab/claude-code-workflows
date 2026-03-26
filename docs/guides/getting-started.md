# Getting Started

Get up and running with Workflow Manager + Superpowers + claude-mem.

## Prerequisites

- Claude Code installed
- Git repository for your project

## Setup

### 1. Install Workflow Manager

**One-liner (from your project root):**
```bash
curl -fsSL https://raw.githubusercontent.com/azevedo-home-lab/claude-code-workflows/main/install.sh | bash
```

**Or clone and install:**
```bash
git clone https://github.com/azevedo-home-lab/claude-code-workflows.git /tmp/ccw
/tmp/ccw/install.sh
rm -rf /tmp/ccw
```

The installer copies hooks, commands, creates `.claude/settings.json` (or warns if one exists), and adds `.claude/state/` to `.gitignore`.

Restart Claude Code after installing.

### 2. Install Superpowers

```bash
plugin marketplace add obra/superpowers-marketplace
plugin install superpowers@superpowers-marketplace
```

### 3. Install claude-mem (optional)

Follow the claude-mem installation guide for your platform. See [claude-mem guide](claude-mem-guide.md).

### 4. Copy CLAUDE.md Template

```bash
cp claude.md.template CLAUDE.md
```

Edit `CLAUDE.md` to fill in project-specific placeholders.

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

## Next Steps

- [Integration Guide](integration-guide.md) — How Superpowers skills work together
- [Hooks Reference](../reference/hooks.md) — How the enforcement hooks work
- [Command Reference](../quick-reference/commands.md) — All commands with descriptions
- [Cross-Session Memory](claude-mem-guide.md) — Persistent memory across sessions
