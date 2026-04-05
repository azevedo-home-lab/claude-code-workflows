# Workflow Manager Hooks Reference

## Overview

Two PreToolUse hooks and a PostToolUse coaching system enforce a plan-before-code workflow by blocking Write/Edit tool calls until the user explicitly approves a plan. This complements superpowers' prompt-based discipline with deterministic enforcement that Claude cannot rationalize away.

For system-level documentation (phases, enforcement layers, gates, milestones), see [Architecture](architecture.md).

Hooks read state but never write it. Phase transitions are driven by user commands (`/implement`, `/discuss`, etc.) or agent auto-transitions (`agent_set_phase` in auto mode). For write permissions per phase, see [Architecture — Write Blocking](architecture.md#write-blocking).

## Files

The plugin distributes hooks and commands from `plugin/`. Hooks run directly from the plugin cache via `CLAUDE_PLUGIN_ROOT` — no copies or symlinks in the project. Only commands and state live in `.claude/`.

```
plugin/
├── .claude-plugin/
│   └── plugin.json                 # Plugin manifest (name, version)
├── hooks/
│   └── hooks.json                  # Auto-wires all hooks (CLAUDE_PLUGIN_ROOT set by Claude Code)
├── scripts/
│   ├── pre-tool-write-gate.sh      # PreToolUse: blocks Write/Edit in DEFINE/DISCUSS/COMPLETE
│   ├── pre-tool-bash-guard.sh      # PreToolUse: blocks Bash writes in DEFINE/DISCUSS/COMPLETE
│   ├── post-tool-coaching.sh       # PostToolUse: three-layer coaching system
│   ├── setup.sh                    # Setup/SessionStart: state init + cache freshness + commands
│   ├── workflow-facade.sh          # State read/write utility (sourced by hooks and wrapper)
│   ├── workflow-cmd.sh             # Shell-independent wrapper — always runs under bash via shebang
│   └── infrastructure/             # Shared modules (resolve-script-dir, hook-preamble, etc.)
├── commands/
│   ├── define.md                   # /define → OFF to DEFINE
│   ├── discuss.md                  # /discuss → any phase to DISCUSS
│   ├── implement.md                # /implement → DISCUSS to IMPLEMENT
│   ├── review.md                   # /review → IMPLEMENT to REVIEW
│   ├── complete.md                 # /complete → REVIEW to COMPLETE
│   ├── off.md                      # /off → close workflow
│   ├── autonomy.md                 # /autonomy → set autonomy level
│   └── proposals.md                # /proposals → view/manage proposals
├── coaching/                       # Coaching messages (editable prose)
├── statusline/
│   └── statusline.sh              # Status bar with version display
└── docs/
    └── reference/
        └── professional-standards.md

Per-project (gitignored):
.claude/state/
└── workflow.json                   # Consolidated workflow state
.claude/commands/                   # Copied from plugin by setup.sh
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

### Hook deployment: plugin hooks.json only

Hooks are defined **exclusively** in `plugin/hooks/hooks.json` and auto-wired by Claude Code when the plugin is installed. Claude Code sets `CLAUDE_PLUGIN_ROOT` at runtime, pointing to the plugin cache directory (`~/.claude/plugins/cache/azevedo-home-lab/workflow-manager/<version>/`). Scripts run directly from the cache — no copies or symlinks in the project.

**Why not project hooks (settings.json)?** Claude Code has two hook systems:

1. **Plugin hooks** (`hooks.json`) — Claude Code sets `CLAUDE_PLUGIN_ROOT` automatically
2. **Project hooks** (`settings.json`) — `CLAUDE_PLUGIN_ROOT` is **not** set

Our scripts depend on `CLAUDE_PLUGIN_ROOT` to find their dependencies (`infrastructure/`, `coaching/`, etc.). If hooks are registered in `settings.json` instead of `hooks.json`, the scripts crash because they can't resolve their own location.

This distinction is documented in the official Claude Code docs:
- [Plugins Reference — Environment variables](https://code.claude.com/docs/en/plugins-reference.md#environment-variables): `${CLAUDE_PLUGIN_ROOT}` is "exported as environment variables to hook processes and MCP or LSP server subprocesses" — but only for plugin-scoped hooks.
- [Hooks Reference — Environment Variables in Hooks](https://code.claude.com/docs/en/hooks.md#environment-variables-in-hooks): project hooks only get `$CLAUDE_PROJECT_DIR`.

**Why not symlinks?** Symlinks are fragile across environments and don't make sense for a distributed plugin. The plugin cache is the single source of truth, kept fresh by `setup.sh` on every session start (see [Cache freshness](#cache-freshness)).

```json
{
  "hooks": {
    "Setup": [{ "matcher": "*", "hooks": [{"type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh"}] }],
    "SessionStart": [{ "matcher": "startup|clear|compact", "hooks": [{"type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh"}] }],
    "PreToolUse": [
      { "matcher": "Write|Edit|MultiEdit|NotebookEdit", "hooks": [{"type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/scripts/pre-tool-write-gate.sh"}] },
      { "matcher": "Bash", "hooks": [{"type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/scripts/pre-tool-bash-guard.sh"}] }
    ],
    "PostToolUse": [
      { "matcher": "*", "hooks": [{"type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/scripts/post-tool-coaching.sh"}] }
    ]
  }
}
```

No manual `settings.json` hook configuration is required for end users.

### Cache freshness

`setup.sh` runs on every `Setup` and `SessionStart` event. It:
1. Pulls the latest code from the marketplace git clone
2. Compares the marketplace version against the cached version
3. If newer: copies to cache, removes stale versions, updates `installed_plugins.json`

This ensures `CLAUDE_PLUGIN_ROOT` always points to the latest plugin code.

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
