#!/bin/bash
# Copyright (C) 2026 azevedo-home-lab
# SPDX-License-Identifier: GPL-3.0-only
#
# This file is part of Claude Code Workflows.
# See LICENSE for details.

# Setup hook — runs on first plugin activation (Setup hook in hooks.json).
# Responsibilities:
#   A. Project state initialization (workflow.json + .gitignore)
#   B. Plugin cache version sync
#   C. Global statusline installation (~/.claude/statusline.sh + settings.json)
#   D. Project hooks (symlinks + settings.json registration)
#   E. Project permissions (ensure tools needed for unattended operation are allowed)

set -euo pipefail

# Verify jq is available (required for all JSON state management)
if ! command -v jq &>/dev/null; then
    echo "ERROR: jq is required but not installed. Install it:" >&2
    echo "  macOS:  brew install jq" >&2
    echo "  Ubuntu: sudo apt-get install jq" >&2
    echo "  Other:  https://jqlang.github.io/jq/download/" >&2
    return 1 2>/dev/null || exit 1  # return when sourced, exit when run directly
fi

# Prefer CLAUDE_PLUGIN_ROOT (set by Claude Code hook runner) over BASH_SOURCE fallback
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
  PLUGIN_ROOT="$CLAUDE_PLUGIN_ROOT"
else
  PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

# SOURCE_ROOT: the authoritative plugin source directory.
# When developing locally, $PROJECT_DIR/plugin/ IS the source — prefer it over
# the cache ($PLUGIN_ROOT) so that edits to source files take effect immediately.
if [ -f "$PROJECT_DIR/plugin/.claude-plugin/plugin.json" ]; then
  SOURCE_ROOT="$PROJECT_DIR/plugin"
else
  SOURCE_ROOT="$PLUGIN_ROOT"
fi

# ─────────────────────────────────────────────────────────────────────────────
# A. Project state initialization
# ─────────────────────────────────────────────────────────────────────────────

STATE_DIR="$PROJECT_DIR/.claude/state"
STATE_FILE="$STATE_DIR/workflow.json"

# Create state directory
mkdir -p "$STATE_DIR"

# Clean up stale temp files from interrupted writes (older than 5 minutes)
find "$STATE_DIR" -name '*.tmp.*' -mmin +5 -delete 2>/dev/null || true

# Write default workflow.json if it doesn't exist
if [ ! -f "$STATE_FILE" ]; then
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  jq -n --arg ts "$ts" '{
    phase: "off",
    message_shown: false,
    active_skill: "",
    plan_path: "",
    spec_path: "",
    coaching: {
      tool_calls_since_agent: 0,
      layer2_fired: []
    },
    updated: $ts,
    autonomy_level: "ask"
  }' > "$STATE_FILE"
fi

# Add .claude/state/ to .gitignore if not already there
GITIGNORE="$PROJECT_DIR/.gitignore"
if [ -f "$GITIGNORE" ]; then
  if ! grep -qxF '.claude/state/' "$GITIGNORE"; then
    printf '\n# Workflow Manager state (per-session, not committed)\n.claude/state/\n' >> "$GITIGNORE"
  fi
else
  printf '# Workflow Manager state (per-session, not committed)\n.claude/state/\n' > "$GITIGNORE"
fi

# ─────────────────────────────────────────────────────────────────────────────
# B. Plugin updates — keep all plugins at latest version
# ─────────────────────────────────────────────────────────────────────────────
# Claude Code doesn't auto-update plugins. Run `claude plugin update` for
# each dependency so installed_plugins.json and the cache stay current.

if command -v claude &>/dev/null; then
  for plugin in \
    "workflow-manager@azevedo-home-lab" \
    "superpowers@superpowers-marketplace" \
    "claude-mem@thedotmack"; do
    claude plugin update "$plugin" 2>/dev/null || true
  done
fi

# ─────────────────────────────────────────────────────────────────────────────
# C. Global statusline installation
# ─────────────────────────────────────────────────────────────────────────────

STATUSLINE_SRC="$SOURCE_ROOT/statusline/statusline.sh"
STATUSLINE_DST="$HOME/.claude/statusline.sh"
GLOBAL_SETTINGS="$HOME/.claude/settings.json"

# Only install if the plugin ships a statusline
if [ -f "$STATUSLINE_SRC" ]; then
  mkdir -p "$HOME/.claude"

  # Back up existing statusline if it differs from ours
  if [ -f "$STATUSLINE_DST" ]; then
    if ! cmp -s "$STATUSLINE_SRC" "$STATUSLINE_DST"; then
      cp "$STATUSLINE_DST" "${STATUSLINE_DST}.backup"
    fi
  fi

  cp "$STATUSLINE_SRC" "$STATUSLINE_DST"
  chmod +x "$STATUSLINE_DST"

  # Configure statusLine in global settings.json
  if [ -f "$GLOBAL_SETTINGS" ]; then
    jq '.statusLine = {"type": "command", "command": "~/.claude/statusline.sh", "padding": 2}' \
      "$GLOBAL_SETTINGS" > "$GLOBAL_SETTINGS.tmp" && mv "$GLOBAL_SETTINGS.tmp" "$GLOBAL_SETTINGS"
  else
    jq -n '{"statusLine": {"type": "command", "command": "~/.claude/statusline.sh", "padding": 2}}' \
      > "$GLOBAL_SETTINGS"
  fi || true
fi

# ─────────────────────────────────────────────────────────────────────────────
# D. Project hooks — ensure all plugin hooks are registered in settings.json
# ─────────────────────────────────────────────────────────────────────────────
# Claude Code reads hooks from .claude/settings.json, NOT from plugin/hooks/hooks.json.
# This section creates symlinks and registers hooks so the plugin's hook scripts fire.

HOOKS_DIR="$PROJECT_DIR/.claude/hooks"
mkdir -p "$HOOKS_DIR"

# Create symlinks for all plugin hook scripts (idempotent)
# Uses glob instead of hardcoded list so new scripts are automatically included.
# setup.sh is excluded — it runs from the plugin root, not from .claude/hooks/.
for script_path in "$PLUGIN_ROOT"/scripts/*.sh; do
  script=$(basename "$script_path")
  [ "$script" = "setup.sh" ] && continue
  if [ ! -e "$HOOKS_DIR/$script" ]; then
    ln -s "../../plugin/scripts/$script" "$HOOKS_DIR/$script"
  fi
done

# Symlink script subdirectories (e.g., checks/) — coaching check modules
for subdir in "$PLUGIN_ROOT"/scripts/*/; do
  [ -d "$subdir" ] || continue
  dirname=$(basename "$subdir")
  if [ ! -e "$HOOKS_DIR/$dirname" ]; then
    ln -s "../../plugin/scripts/$dirname" "$HOOKS_DIR/$dirname"
  fi
done

# Register hooks in settings.json via jq (idempotent — only adds missing hooks)
PROJECT_SETTINGS="$PROJECT_DIR/.claude/settings.json"
if [ -f "$PROJECT_SETTINGS" ]; then

  # Ensure PreToolUse hooks exist
  HAS_PTU=$(jq 'has("hooks") and (.hooks | has("PreToolUse"))' "$PROJECT_SETTINGS" 2>/dev/null)
  if [ "$HAS_PTU" != "true" ]; then
    jq '.hooks.PreToolUse = [
      {"matcher": "Write|Edit|MultiEdit|NotebookEdit", "hooks": [{"type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/pre-tool-write-gate.sh"}]},
      {"matcher": "Bash", "hooks": [{"type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/pre-tool-bash-guard.sh"}]}
    ]' "$PROJECT_SETTINGS" > "$PROJECT_SETTINGS.tmp" && mv "$PROJECT_SETTINGS.tmp" "$PROJECT_SETTINGS" || true
  fi

  # Ensure PostToolUse hook exists
  HAS_POST=$(jq 'has("hooks") and (.hooks | has("PostToolUse"))' "$PROJECT_SETTINGS" 2>/dev/null)
  if [ "$HAS_POST" != "true" ]; then
    jq '.hooks.PostToolUse = [{"hooks": [{"type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/post-tool-coaching.sh"}]}]' \
      "$PROJECT_SETTINGS" > "$PROJECT_SETTINGS.tmp" && mv "$PROJECT_SETTINGS.tmp" "$PROJECT_SETTINGS" || true
  fi
fi || true

# ─────────────────────────────────────────────────────────────────────────────
# E. Project commands — copy plugin commands to .claude/commands/
# ─────────────────────────────────────────────────────────────────────────────
# Plugin commands are namespaced (/plugin-name:cmd), but users expect bare /cmd.
# Copying (not symlinking) to .claude/commands/ gives bare names and survives
# fresh installs. Files are always overwritten to stay in sync with source.

COMMANDS_DIR="$PROJECT_DIR/.claude/commands"
mkdir -p "$COMMANDS_DIR"

for cmd_file in "$SOURCE_ROOT/commands/"*.md; do
  [ -f "$cmd_file" ] || continue
  cp "$cmd_file" "$COMMANDS_DIR/$(basename "$cmd_file")"
done

# ─────────────────────────────────────────────────────────────────────────────
# F. Project permissions — ensure tools needed for workflow pipeline are allowed
# ─────────────────────────────────────────────────────────────────────────────

# The workflow pipeline (hooks, coaching, COMPLETE agents) needs these tools
# to operate without permission prompts. Without them, autonomy level 3
# (unattended) is broken by constant approval dialogs.
if [ -f "$PROJECT_SETTINGS" ]; then
  NEEDS_PERMS=false
  for perm in Read Agent Glob Grep; do
    if ! jq -e ".permissions.allow // [] | index(\"$perm\")" "$PROJECT_SETTINGS" &>/dev/null; then
      NEEDS_PERMS=true
      break
    fi
  done
  if [ "$NEEDS_PERMS" = "true" ]; then
    jq '.permissions.allow = ((.permissions.allow // []) + ["Read", "Agent", "Glob", "Grep"] | unique)' \
      "$PROJECT_SETTINGS" > "$PROJECT_SETTINGS.tmp" && mv "$PROJECT_SETTINGS.tmp" "$PROJECT_SETTINGS" || true
  fi
fi
