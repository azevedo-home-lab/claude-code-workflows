# Workflow Manager Hooks Reference

## Overview

Two PreToolUse hooks and a PostToolUse coaching system enforce a plan-before-code workflow by blocking Write/Edit tool calls until the user explicitly approves a plan. This complements superpowers' prompt-based discipline with deterministic enforcement that Claude cannot rationalize away.

## Architecture

```
Layer 1: PreToolUse Hooks (Deterministic)       Layer 2: Superpowers Skills (Behavioral)
┌──────────────────────────────────────┐        ┌──────────────────────────────────┐
│ workflow-gate.sh                     │        │ /superpowers:brainstorm          │
│   Blocks Write/Edit in DEFINE,       │        │ /superpowers:write-plan          │
│   DISCUSS, and COMPLETE              │
│                                      │        │ /superpowers:execute-plan        │
│ bash-write-guard.sh                  │        │ /superpowers:tdd                 │
│   Blocks Bash write ops in DEFINE,   │        │ /superpowers:verify              │
│   DISCUSS, and COMPLETE              │        │ /superpowers:code-review         │
│ State: .claude/state/workflow.json   │        │                                  │
└──────────────────────────────────────┘        └──────────────────────────────────┘
```

Hooks read state but never write it. Phase transitions are driven by user commands (`/implement`, `/discuss`, etc.).

## Phase Model

```
OFF ──(/define)──> DEFINE ──(/discuss)──> DISCUSS ──(/implement)──> IMPLEMENT ──(/review)──> REVIEW ──(/complete)──> COMPLETE ──> OFF

Any /phase command can jump directly to any phase. Soft gates warn when skipping recommended steps.
```

| Phase | Write/Edit/MultiEdit | Bash writes | Read/Grep/Glob/Agent | Git |
|-------|---------------------|-------------|---------------------|-----|
| OFF | Allowed | Allowed | Allowed | Allowed |
| DEFINE | **BLOCKED** (except specs/plans) | **BLOCKED** (except specs/plans) | Allowed | Allowed |
| DISCUSS | **BLOCKED** (except specs/plans) | **BLOCKED** (except specs/plans) | Allowed | Allowed |
| IMPLEMENT | Allowed | Allowed | Allowed | Allowed |
| REVIEW | Allowed | Allowed | Allowed | Allowed |
| COMPLETE | **BLOCKED** (except docs) | **BLOCKED** (except docs) | Allowed | Allowed |

New sessions default to OFF if no state file exists.

## Files

```
.claude/
├── hooks/
│   ├── workflow-state.sh       # State read/write utility (sourced by hooks and wrapper)
│   ├── workflow-cmd.sh         # Shell-independent wrapper — always runs under bash via shebang
│   ├── workflow-gate.sh        # PreToolUse: blocks Write/Edit in DEFINE/DISCUSS/COMPLETE
│   ├── bash-write-guard.sh     # PreToolUse: blocks Bash writes in DEFINE/DISCUSS/COMPLETE
│   └── post-tool-navigator.sh  # PostToolUse: three-layer coaching system
├── commands/
│   ├── define.md               # /define → OFF to DEFINE
│   ├── discuss.md              # /discuss → any phase to DISCUSS
│   ├── implement.md            # /implement → DISCUSS to IMPLEMENT
│   ├── review.md               # /review → IMPLEMENT to REVIEW
│   └── complete.md             # /complete → REVIEW to COMPLETE
├── state/
│   └── workflow.json           # Consolidated workflow state (gitignored)
└── settings.json               # Hook configuration
```

## Hook Details

### workflow-gate.sh

- **Matcher**: `Write|Edit|MultiEdit|NotebookEdit`
- **Logic**: Read phase from state file. If `define`, `discuss`, or `complete` → deny with message (with phase-specific whitelist tiers). If `implement` or `review` → allow.
- **Whitelist tiers**: DEFINE/DISCUSS allow specs/plans paths. COMPLETE allows docs paths.
- **No state file**: Allow (no enforcement on first run before setup).

### bash-write-guard.sh

- **Matcher**: `Bash`
- **Logic**: Read phase. If `implement` or `review` → allow all. If `define`, `discuss`, or `complete` → extract command, pattern-match for write operations, deny if found.
- **Patterns caught**: `>`, `>>`, `sed -i`, `tee`, `cat << EOF`, `python -c` with file writes, `echo >`.
- **Coverage**: ~95%. Claude isn't adversarial — it uses Bash as a fallback when Edit is blocked. Common patterns are sufficient.

### workflow-state.sh

- **Not a hook** — sourced by other scripts.
- **State file**: `.claude/state/workflow.json` — consolidated state (phase, active skill, decision record, review status, coaching state).
- **Phase functions**: `get_phase`, `set_phase <phase>` (validates: off/define/discuss/implement/review/complete)
- **Message functions**: `get_message_shown`, `set_message_shown`
- **Skill tracking**: `set_active_skill <name>`, `get_active_skill`
- **Decision record**: `set_decision_record <path>`, `get_decision_record`
- **Soft gates**: `check_soft_gate <target_phase>` — returns warning message or empty string
- **Review status**: `reset_review_status`, `get_review_field <field>`, `set_review_field <field> <value>`
- **Coaching state**: `increment_coaching_counter`, `reset_coaching_counter`, `add_coaching_fired <type>`, `has_coaching_fired <type>`
- **Whitelists**: `RESTRICTED_WRITE_WHITELIST` (DEFINE/DISCUSS), `COMPLETE_WRITE_WHITELIST` (COMPLETE)

## Commands

### /implement

Sets phase to `implement`. Code edits are unblocked. Instructs Claude to use `executing-plans` and `test-driven-development` superpowers. Soft gate warns if no plan exists. Use after reviewing and approving a plan.

### /review

Sets phase to `review`. Instructs Claude to use `verification-before-completion` and `requesting-code-review` superpowers. Use when implementation is done and ready for verification.

### /complete

Sets phase to `complete`. Triggers verified completion with outcome validation, docs check, and handover. Soft gate warns if review wasn't completed. After completion, transitions to OFF.

### /discuss

Sets phase to `discuss`. Code edits are blocked. Instructs Claude to use `brainstorming` and `writing-plans` superpowers. Use to start a workflow or abort/rethink from any phase.

## Configuration

Hooks are auto-wired when the plugin is installed. The configuration lives in `plugin/hooks/hooks.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write|Edit|MultiEdit|NotebookEdit",
        "hooks": [{
          "type": "command",
          "command": "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-gate.sh"
        }]
      },
      {
        "matcher": "Bash",
        "hooks": [{
          "type": "command",
          "command": "${CLAUDE_PLUGIN_ROOT}/scripts/bash-write-guard.sh"
        }]
      }
    ]
  }
}
```

No manual `settings.json` configuration is required for end users.

## Coaching System (PostToolUse)

The `post-tool-navigator.sh` hook provides a three-layer coaching system via PostToolUse messages:

| Layer | Purpose | When | Phases |
|-------|---------|------|--------|
| **Phase entry** | Orients Claude to the current phase's objectives and done criteria | Once per phase transition | All active phases |
| **Standards reinforcement** | Contextual reminders from professional-standards.md | After specific tool patterns (Agent returns, Write/Edit to code, test runs, plan writes) | DEFINE, DISCUSS, IMPLEMENT, REVIEW, COMPLETE |
| **Anti-laziness** | Detects lazy behavior patterns | On every match: short agent prompts (<150 chars), generic commits (<30 chars), skipped research (>10 tool calls without agents in DEFINE/DISCUSS), all findings downgraded, minimal handovers | All active phases |

All coaching messages are prefixed with `[Workflow Coach — PHASE]` and visible to the user. They are non-blocking guidance — they inform Claude's behavior but do not prevent tool use.

### Layer 3: claude-mem project scoping check

A dedicated Layer 3 check fires when `save_observation` is called without a `project` parameter:

- **Trigger**: PostToolUse on `mcp__plugin_claude-mem_mcp-search__save_observation` where the tool input lacks a `project` field
- **Message**: Reminds Claude to derive the project name from `git remote get-url origin` and re-issue the call with `project=<name>`
- **Effect**: Non-blocking warning only. The observation is already saved; the check prompts correction before the session ends.

### PostToolUse: observation ID capture

The `post-tool-navigator.sh` hook also captures observation IDs from claude-mem responses:

- **Triggers**: `save_observation` and `get_observations` tool responses
- **Logic**: Parses the MCP response for the returned observation ID (or the last ID in a list)
- **Effect**: Writes the ID to `.claude/state/workflow.json` under `last_observation_id`
- **Consumer**: The status line script reads this field and renders `Claude-Mem ✓ #<id>` when present

## Autonomy Levels

Autonomy level is an orthogonal dimension to phase — phase controls **what** is allowed; autonomy controls **how much** Claude does independently.

### Levels

| Symbol | Level | Name | Behavior |
|--------|-------|------|----------|
| `▶` | 1 | Supervised | Read-only. All writes blocked regardless of phase. Local research only. |
| `▶▶` | 2 | Semi-Auto | Writes follow phase rules. Stops at phase transitions for user approval. **Default.** |
| `▶▶▶` | 3 | Unattended | Auto-transitions between phases. Auto-commits. Stops only for user input and push. |

Set the level with `/autonomy 1`, `/autonomy 2`, or `/autonomy 3`. Only the user can change it.

### Check Order

Both `workflow-gate.sh` and `bash-write-guard.sh` apply checks in this order:

```
1. No state file → allow (fails open)
2. Workflow OFF → allow
3. Autonomy Level 1 → deny all writes (regardless of phase)
4. Implement/Review phase check (phase gate)
5. Phase-specific whitelist check (specs/plans, docs)
```

Level 1 blocks all writes before the phase gate is even evaluated. Levels 2 and 3 fall through to the existing phase-based logic. The hooks are the single source of truth; Claude Code permission modes (`plan`/`default`/`acceptEdits`) are best-effort convenience only.

## Known Limitations

1. **Bash bypass is ~95% covered**. A sufficiently creative command can slip through. Anthropic closed this as NOT_PLANNED (GitHub #29709).
2. **Hooks are stateless validators**. They only read `.claude/state/workflow.json`. If the file is deleted or corrupted, enforcement stops (fails open).
3. **No scope enforcement**. Unlike cc-sessions, these hooks don't track which files are "in scope" for the approved plan. Any file can be edited in IMPLEMENT phase.
