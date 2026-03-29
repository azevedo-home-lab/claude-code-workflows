# Dual Hook Execution Bug — Investigation & Fix

## Problem

When developing the workflow-manager plugin inside its own project repo while also having it installed via the marketplace, **two sets of hooks fire on every tool call** — the dev version (v1.12.0) and the stale cached version (v1.0.0). Both write to the same `workflow.json` state file with incompatible logic, causing silent state corruption.

### Symptoms Observed

1. **Autonomy silently downgraded** from `auto` to `ask` mid-session — caused `agent_set_phase "review"` to be blocked
2. **Phase reset to `off`** after failed transition — state became inconsistent between the two versions

### Root Cause

Claude Code has two independent hook registration mechanisms:

| Mechanism | File | Points to | Version |
|-----------|------|-----------|---------|
| **Project hooks** | `.claude/settings.json` → `hooks` section | `$CLAUDE_PROJECT_DIR/.claude/hooks/*.sh` (symlinks to `plugin/scripts/`) | Dev code (v1.12.0) |
| **Plugin hooks** | `~/.claude/plugins/cache/.../1.0.0/hooks/hooks.json` | `${CLAUDE_PLUGIN_ROOT}/scripts/*.sh` (cached snapshot) | Stale cached (v1.0.0) |

CC merges hooks from both sources and runs all matching hooks in parallel. It deduplicates by exact command string — but since the paths differ (`$CLAUDE_PROJECT_DIR/.claude/hooks/` vs `${CLAUDE_PLUGIN_ROOT}/scripts/`), CC treats them as independent hooks and runs both.

Both versions read and write `$CLAUDE_PROJECT_DIR/.claude/state/workflow.json`. The v1.0.0 cached code has completely different state management (no `_safe_write`, no `_update_state`, uses Python instead of jq for `emit_deny`, uses integer `2` for autonomy instead of string `"auto"`, doesn't know about milestone sections). When it writes to `workflow.json`, it corrupts fields that the v1.12.0 code depends on.

### Proof

Added `echo "[CACHED v1.0.0 <script> FIRED]" >&2` to the three cached hook scripts. Confirmed all three fire on every tool call alongside the dev hooks:
- `bash-write-guard.sh` — fires on every Bash tool call (twice)
- `workflow-gate.sh` — fires on every Write/Edit tool call (twice)
- `post-tool-navigator.sh` — fires on every tool call (twice)

## How CC's Plugin System Works

### Hook Registration (parallel, additive)

Plugin hooks and project hooks **merge and run in parallel**. Both fire for matching events. CC deduplicates by exact command string — if two hooks have the same command, only one runs. If they differ (as in our case), both run.

This design assumes plugin hooks and project hooks serve **different purposes**:
- **Plugin hooks** (`hooks/hooks.json`): The plugin's own enforcement rules, portable across projects
- **Project hooks** (`.claude/settings.json`): User/team customizations, project-specific

### Command Registration (shadowing)

Unlike hooks, commands use **name-based shadowing**. Project `.claude/commands/` takes precedence over plugin `commands/` when both have the same name. This is why our project commands (v1.12.0) work correctly despite the stale plugin commands (v1.0.0).

### State Management

CC provides `${CLAUDE_PLUGIN_DATA}` (`~/.claude/plugins/data/{id}/`) for plugin-persistent state that survives updates. Our plugin uses `$CLAUDE_PROJECT_DIR/.claude/state/workflow.json` instead — which is correct since workflow state is project-scoped, but it means both hook versions write to the same file with no isolation.

### Plugin Environment Variables

| Variable | Value | Purpose |
|----------|-------|---------|
| `${CLAUDE_PLUGIN_ROOT}` | Plugin installation directory | Reference bundled scripts, configs |
| `${CLAUDE_PLUGIN_DATA}` | `~/.claude/plugins/data/{id}/` | Persistent state (survives updates) |
| `${CLAUDE_PROJECT_DIR}` | Project root | Available in hook subprocesses |

### Plugin Development

The recommended dev workflow is `claude --plugin-dir ./my-plugin` which loads directly from source with no cache. `/reload-plugins` picks up changes without restarting.

## Why This Only Affects Plugin Developers

Normal users who install via marketplace get hooks ONLY from the plugin's `hooks.json`. They don't have project-level hooks in `.claude/settings.json`. No dual registration, no conflict.

The problem is specific to: **developing a plugin inside its own project while also having it installed via marketplace.**

## Fixes

### Fix 1: This project (dev environment)

Remove the marketplace plugin enablement. The project-level hooks are the real dev hooks and should be the only ones firing.

In `.claude/settings.json`, set:
```json
"enabledPlugins": {}
```

The project-level hooks in the `hooks` section continue to work and point to dev code via symlinks. Commands in `.claude/commands/` are loaded independently. Statusline is installed globally at `~/.claude/statusline.sh`.

### Fix 2: Plugin setup guard (for new users)

The plugin's `setup.sh` (Setup hook) should detect if project-level hooks already exist in `.claude/settings.json` pointing to workflow-manager scripts and warn the user about potential dual registration.

### Fix 3: Documentation

Document that plugin developers should NOT install their plugin via marketplace in the same project where they develop it. Use `claude --plugin-dir .` instead.
