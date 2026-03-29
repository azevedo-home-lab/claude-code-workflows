# Workflow Manager Hooks Reference

## Overview

Two PreToolUse hooks and a PostToolUse coaching system enforce a plan-before-code workflow by blocking Write/Edit tool calls until the user explicitly approves a plan. This complements superpowers' prompt-based discipline with deterministic enforcement that Claude cannot rationalize away.

For system-level documentation (phases, enforcement layers, gates, milestones), see [Architecture](architecture.md).

Hooks read state but never write it. Phase transitions are driven by user commands (`/implement`, `/discuss`, etc.) or agent auto-transitions (`agent_set_phase` in auto mode). For write permissions per phase, see [Architecture — Write Blocking](architecture.md#write-blocking).

## Files

The plugin distributes hooks and commands from `plugin/`:

```
plugin/
├── .claude-plugin/
│   └── plugin.json             # Plugin manifest (name, version)
├── hooks/
│   └── hooks.json              # Auto-wires PreToolUse and PostToolUse hooks
├── scripts/
│   ├── workflow-state.sh       # State read/write utility (sourced by hooks and wrapper)
│   ├── workflow-cmd.sh         # Shell-independent wrapper — always runs under bash via shebang
│   ├── workflow-gate.sh        # PreToolUse: blocks Write/Edit in DEFINE/DISCUSS/COMPLETE
│   ├── bash-write-guard.sh     # PreToolUse: blocks Bash writes in DEFINE/DISCUSS/COMPLETE
│   ├── post-tool-navigator.sh  # PostToolUse: three-layer coaching system
│   └── setup.sh                # Setup hook: initializes state + installs statusline
├── commands/
│   ├── define.md               # /define → OFF to DEFINE
│   ├── discuss.md              # /discuss → any phase to DISCUSS
│   ├── implement.md            # /implement → DISCUSS to IMPLEMENT
│   ├── review.md               # /review → IMPLEMENT to REVIEW
│   ├── complete.md             # /complete → REVIEW to COMPLETE
│   ├── off.md                  # /off → close workflow
│   ├── autonomy.md             # /autonomy → set autonomy level
│   └── proposals.md            # /proposals → view/manage proposals
├── statusline/
│   └── statusline.sh           # Status bar with version display
└── docs/
    └── reference/
        └── professional-standards.md

Per-project state (gitignored):
.claude/state/
└── workflow.json               # Consolidated workflow state
```

## Hook Details

### workflow-gate.sh

- **Matcher**: `Write|Edit|MultiEdit|NotebookEdit`
- **Logic**: Read phase from state file. If `define`, `discuss`, or `complete` → deny with message (with phase-specific whitelist tiers). If `implement` or `review` → allow.
- **Whitelist tiers**: DEFINE/DISCUSS allow specs/plans paths. COMPLETE allows docs paths. See [Architecture — Write Blocking](architecture.md#write-blocking) for tier details.
- **Guard-system self-protection**: Blocks edits to `.claude/hooks/`, `plugin/scripts/`, `plugin/commands/` in all active phases.
- **Path traversal protection**: Canonicalizes file paths via `python3 os.path.realpath` to catch encoded/symlinked traversal.
- **No state file**: Allow (no enforcement on first run before setup).

### bash-write-guard.sh

- **Matcher**: `Bash`
- **Logic**: Read phase. Block destructive git operations in ALL active phases (before phase-specific logic). Then: if `implement` or `review` → allow all. If `define`, `discuss`, or `complete` → extract command, pattern-match for write operations, deny if found.
- **Patterns caught**: Destructive git (all phases: `reset --hard`, `push --force/-f`, `branch -D`, `checkout -- .`, `clean -f`, `rebase --abort`), `>`, `>>`, `sed -i`, `tee`, `cat << EOF`, `python -c` with file writes, `echo >`, `cp`, `mv`, `rm`, `curl -o`, pipe-to-shell, xargs execution, `gh` operations (phase-restricted).
- **Exceptions**: `git commit` (standalone), safe git chains, workflow state calls, `workflow-cmd.sh` calls, `gh` read-only in DEFINE/DISCUSS, `gh` all ops in COMPLETE, `rm .claude/tmp/` in COMPLETE, redirects to `/dev/null`.
- **Coverage**: ~95%. Claude isn't adversarial — it uses Bash as a fallback when Edit is blocked. Common patterns are sufficient.

### workflow-state.sh

- **Not a hook** — sourced by other scripts.
- **State file**: `.claude/state/workflow.json` — consolidated state (phase, active skill, plan path, spec path, milestones, coaching state).
- **Phase functions**: `get_phase`, `agent_set_phase <phase>` (auto mode, forward-only)
- **Message functions**: `get_message_shown`, `set_message_shown`
- **Skill tracking**: `set_active_skill <name>`, `get_active_skill`
- **Plan/spec paths**: `set_plan_path <path>`, `get_plan_path`, `set_spec_path`, `get_spec_path`
- **Soft gates**: `check_soft_gate <target_phase>` — returns warning message or empty string
- **Milestone sections**: `reset_*_status`, `get_*_field`, `set_*_field` for discuss, implement, review, completion
- **Coaching state**: `increment_coaching_counter`, `reset_coaching_counter`, `add_coaching_fired <type>`, `has_coaching_fired <type>`
- **Debug mode**: `get_debug`, `set_debug <true|false>` — preserved across transitions, cleared on OFF
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

### /debug

Toggles debug mode. When enabled (`/debug on`), all hook coaching messages and gate decisions are echoed to stderr with `[WFM DEBUG]` prefix, making them visible to the user. `/debug off` disables. `/debug` (no argument) reports current state. Status line shows `[DEBUG]` indicator when active.

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

## PostToolUse Implementation Details

For the coaching system overview, see [Architecture — Enforcement](architecture.md#enforcement).

Implementation specifics in `post-tool-navigator.sh`:

### Observation ID capture

Captures observation IDs from claude-mem responses:

- **Triggers**: `save_observation` and `get_observations` tool responses
- **Logic**: Parses the MCP response for the returned observation ID (or the last ID in a list)
- **Effect**: Writes the ID to `.claude/state/workflow.json` under `last_observation_id`
- **Consumer**: The status line script reads this field and renders `Claude-Mem ✓ #<id>` when present

### Check order

Both `workflow-gate.sh` and `bash-write-guard.sh` apply checks in this order:

```
1. No state file → allow (fails open)
2. Workflow OFF → allow
3. Guard-system self-protection (all active phases)
4. Implement/Review phase → allow all
5. Phase-specific whitelist check (specs/plans, docs)
6. Deny with phase-aware message
```

## Known Limitations

1. **Bash bypass is ~95% covered**. A sufficiently creative command can slip through. Anthropic closed this as NOT_PLANNED (GitHub #29709).
2. **Hooks are stateless validators**. They only read `.claude/state/workflow.json`. If the file is deleted or corrupted, enforcement stops (fails open).
3. **No scope enforcement**. Unlike cc-sessions, these hooks don't track which files are "in scope" for the approved plan. Any file can be edited in IMPLEMENT phase.
