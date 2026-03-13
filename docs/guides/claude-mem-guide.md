# Cross-Session Memory with claude-mem

## Overview

claude-mem is an MCP (Model Context Protocol) server that gives Claude Code persistent memory across sessions. Without it, each new Claude Code session starts with zero knowledge of previous work. With it, Claude can search for prior decisions, solutions, and context.

## The Problem It Solves

Traditional session handover relies on:
- Manual handover files (e.g., `sessions/HANDOVER_CONTEXT.md`)
- Git commit history
- CLAUDE.md documentation

These work but have gaps:
- Handover files go stale if not updated
- Git history lacks conversational context (why decisions were made)
- CLAUDE.md is for permanent architecture, not session state

claude-mem fills the gap: it stores **observations** — facts, decisions, and context discovered during work — and makes them searchable in future sessions.

## Available Commands

### `mem-search`

Search previous session observations.

**When to use:**
- Starting a new session ("what were we working on?")
- Encountering a familiar problem ("did we solve this before?")
- Needing context on a past decision ("why did we choose X?")

**Examples:**
```
/claude-mem:mem-search "YubiKey signing setup"
/claude-mem:mem-search "transcription service deployment"
/claude-mem:mem-search "DNS resolution issue"
```

### `make-plan`

Create a detailed, phased implementation plan with documentation discovery.

**When to use:**
- Planning a feature before implementation
- Breaking down a complex task into phases
- Creating a plan that other sessions can execute

### `do`

Execute a phased implementation plan using subagents.

**When to use:**
- Running a plan created by `make-plan`
- Executing multi-step implementations with parallel work

## Session Lifecycle with claude-mem

### Starting a Session

1. **Search claude-mem first** — find prior context before reading any files
2. Read handover files if they exist (supplementary, not primary)
3. Check git log for recent changes
4. Read CLAUDE.md for permanent project rules

```
Session Start
    │
    ▼
Search claude-mem ──→ "What was the last session doing?"
    │
    ▼
Read handover files ──→ Supplementary context
    │
    ▼
Check git log ──→ What changed recently?
    │
    ▼
Begin work
```

### During a Session

Observations are saved as you work. Good observations to save:
- **Decisions**: "Chose X over Y because Z"
- **Discoveries**: "The macOS ssh-agent can't prompt for FIDO touch in non-tty contexts"
- **Solutions**: "Fixed DNS by running Stubby on Proxmox host as local resolver"
- **User preferences**: "User wants no GUI popups for YubiKey, just touch"
- **Blockers**: "Port 53 intercepted by GT-BE98 firmware"

### Ending a Session

Key findings are persisted automatically. For explicit handover:
1. Save a summary observation with current state and next steps
2. Update handover file if the project uses one
3. Commit any in-progress work

## Integration with DAIC Workflow

| DAIC Phase | claude-mem Role |
|------------|----------------|
| **mek:** (new task) | Search for prior work on similar tasks |
| **start^:** (gather context) | Load observations from previous sessions on this task |
| **yert** (implement) | Save key decisions and discoveries as you work |
| **finito** (complete) | Final observation summarizing what was done and outcome |

## Integration with File-Based Memory

Some projects use a file-based memory system (e.g., `memory/MEMORY.md` with topic files). claude-mem and file-based memory are complementary:

| Aspect | claude-mem | File-based memory |
|--------|-----------|-------------------|
| **Storage** | MCP server database | Git-tracked markdown files |
| **Scope** | All projects on this machine | Per-project |
| **Search** | Natural language queries | File reading |
| **Best for** | Cross-session context, decisions | Permanent project knowledge |
| **Survives** | Machine rebuild: no (unless backed up) | Always (in git) |

**Use both**: claude-mem for quick cross-session recall, file-based memory for durable project knowledge that persists across machines and collaborators.

## Troubleshooting

**claude-mem not available:**
- Check if the MCP server is running
- Verify Claude Code settings include the claude-mem server
- Fall back to handover files and git history

**Stale observations:**
- claude-mem observations don't auto-expire
- Periodically review and clean up outdated observations
- Recent observations should be weighted more heavily than old ones

**Conflicting information:**
- When claude-mem and docs disagree, verify against live system state
- Code and running systems are always the source of truth
- Update the stale source after verification
