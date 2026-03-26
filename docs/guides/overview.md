# Claude Code Workflows — Overview

A workflow enforcement layer for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) (Anthropic's AI coding assistant) that structures AI-assisted development into disciplined phases: define → discuss → implement → review → complete.

## What problem does it solve?

Claude Code is a powerful AI coding assistant, but left to its defaults it behaves like an eager junior developer: it jumps straight to writing code before understanding the problem, loses track of early decisions as the conversation grows, and produces no auditable record of what was decided or why.

Over long sessions, this gets worse. The context window fills up, older decisions get compressed or forgotten, and the model starts hallucinating — confidently referencing functions that were renamed three steps ago, or implementing a solution that contradicts an earlier design choice.

Inspired by [cc-sessions](https://github.com/GWUDCAP/cc-sessions) (DAIC workflow enforcement with trigger-phrase automation and sub-agents for Claude Code), this project builds an opinionated workflow enforcement system that goes further. Workflow phases alone weren't enough — Claude also needed guardrails (hard edit gates that prevent coding before planning), structure (coaching and skills that guide each development phase), and accountability (decision records and multi-agent review pipelines).

The result makes Claude Code behave like a disciplined senior engineer: think first, plan second, code third, review before shipping.

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
| `▶` | off | Supervised | Step-by-step pair programming. Claude executes one plan step at a time, presents the change, and waits for review before proceeding. Writes follow phase rules. |
| `▶▶` | ask | Semi-Auto | Claude works freely within each phase but stops at phase boundaries for review and guidance before transitioning. No auto-commits. **Default.** |
| `▶▶▶` | auto | Unattended | Full autonomy. Claude auto-transitions between phases, auto-fixes review findings, auto-commits. Stops only when user input is genuinely needed or before git push. |

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

- [cc-sessions](https://github.com/GWUDCAP/cc-sessions) — DAIC workflow enforcement with trigger-phrase automation for Claude Code
- [claude-mem](https://github.com/thedotmack/claude-mem) — cross-session memory MCP server
- [Superpowers](https://github.com/obra/superpowers) — agentic skills framework and development methodology for Claude Code
- [everything-claude-code](https://github.com/affaan-m/everything-claude-code) — agent harness performance optimization, skills, instincts, memory
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) — Anthropic's AI coding assistant
- [Context Engineering for AI Agents](https://docs.claude-mem.ai/context-engineering) — context rot, progressive disclosure, agentic memory
- [Reduce Hallucinations](https://docs.anthropic.com/en/docs/test-and-evaluate/strengthen-guardrails/reduce-hallucinations) — grounding, citations, uncertainty
- [Claude Code Best Practices](https://code.claude.com/docs/en/best-practices) — agentic coding patterns
- [Building Effective Agents](https://www.anthropic.com/research/building-effective-agents) — tool design, evaluation loops
- [Effective Harnesses for Long-Running Agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents) — session state, progress checkpoints
