#!/bin/bash
# Copyright (C) 2026 azevedo-home-lab
# SPDX-License-Identifier: GPL-3.0-only
#
# This file is part of Claude Code Workflows.
# See LICENSE for details.

# Setup hook — runs on first plugin activation (Setup hook in hooks.json).
# Responsibilities:
#   A. Project state initialization (workflow.json + .gitignore)
#   B. Plugin updates (claude plugin update for all dependencies)
#   C. Global statusline installation (~/.claude/statusline.sh + settings.json)
#   D. Project hooks (copy scripts to .claude/hooks/ + settings.json registration)
#   E. Project commands (copy to .claude/commands/)
#   F. Project permissions (ensure tools needed for unattended operation are allowed)

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
# Dev mode (.claude-plugin/.dev marker): use the project's plugin/ directory as
# the live source so that edits take effect immediately without cache refresh.
# Production: use the cache ($PLUGIN_ROOT).
# See infrastructure/resolve-script-dir.sh for the shared resolution logic.
if [ -f "$PROJECT_DIR/.claude-plugin/.dev" ] && [ -d "$PROJECT_DIR/plugin/scripts" ]; then
  SOURCE_ROOT="$PROJECT_DIR/plugin"
else
  SOURCE_ROOT="$PLUGIN_ROOT"
fi

# PLUGIN_JSON: version metadata lives at repo root, not inside plugin/
if [ -f "$PROJECT_DIR/.claude-plugin/plugin.json" ]; then
  SOURCE_PLUGIN_JSON="$PROJECT_DIR/.claude-plugin/plugin.json"
elif [ -f "$SOURCE_ROOT/.claude-plugin/plugin.json" ]; then
  SOURCE_PLUGIN_JSON="$SOURCE_ROOT/.claude-plugin/plugin.json"
else
  SOURCE_PLUGIN_JSON=""
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

# Ensure generated/runtime paths are in .gitignore.
# .claude/settings.json is deliberately NOT gitignored — it holds team-sharable
# project config (permissions, hook registrations) that should be committed.
GITIGNORE="$PROJECT_DIR/.gitignore"
_WFM_GITIGNORE_ENTRIES=(
  ".claude/state/"
  ".claude/hooks/"
  ".claude/commands/"
  ".claude/settings.local.json"
)
_WFM_GITIGNORE_ADDED=false
for _entry in "${_WFM_GITIGNORE_ENTRIES[@]}"; do
  if [ -f "$GITIGNORE" ]; then
    if ! grep -qxF "$_entry" "$GITIGNORE"; then
      _WFM_GITIGNORE_ADDED=true
    fi
  else
    _WFM_GITIGNORE_ADDED=true
  fi
done
if [ "$_WFM_GITIGNORE_ADDED" = true ]; then
  _WFM_BLOCK=""
  for _entry in "${_WFM_GITIGNORE_ENTRIES[@]}"; do
    if ! { [ -f "$GITIGNORE" ] && grep -qxF "$_entry" "$GITIGNORE"; }; then
      _WFM_BLOCK="${_WFM_BLOCK}${_entry}\n"
    fi
  done
  if [ -n "$_WFM_BLOCK" ]; then
    if [ -f "$GITIGNORE" ]; then
      printf '\n# Workflow Manager — generated/runtime files (not committed)\n'"$_WFM_BLOCK" >> "$GITIGNORE"
    else
      printf '# Workflow Manager — generated/runtime files (not committed)\n'"$_WFM_BLOCK" > "$GITIGNORE"
    fi
  fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# B. Plugin updates — keep all plugins at latest version
# ─────────────────────────────────────────────────────────────────────────────
# Claude Code doesn't auto-update plugins or marketplace clones.
#
# For external dependencies: `claude plugin update` handles it.
# For workflow-manager: Claude Code resolves versions from its marketplace
# clone at ~/.claude/plugins/marketplaces/azevedo-home-lab/ which is a
# stale git checkout. We must git pull it, then sync the cache and registry.

# Update external dependencies
if command -v claude &>/dev/null; then
  for plugin in \
    "superpowers@superpowers-marketplace" \
    "claude-mem@thedotmack"; do
    claude plugin update "$plugin" 2>/dev/null || true
  done
fi

# Update workflow-manager marketplace clone (the root cause of stale versions).
# Claude Code's plugin loader may have dirtied the clone, so reset before pulling.
WM_MARKETPLACE_DIR="$HOME/.claude/plugins/marketplaces/azevedo-home-lab"
if [ -d "$WM_MARKETPLACE_DIR/.git" ]; then
  git -C "$WM_MARKETPLACE_DIR" reset --hard HEAD --quiet 2>/dev/null || true
  git -C "$WM_MARKETPLACE_DIR" clean -fd --quiet 2>/dev/null || true
  git -C "$WM_MARKETPLACE_DIR" pull origin main --quiet 2>/dev/null || true
fi

# Sync workflow-manager cache from local source
INSTALLED_PLUGINS="$HOME/.claude/plugins/installed_plugins.json"
WM_CACHE_DIR="$HOME/.claude/plugins/cache/azevedo-home-lab/workflow-manager"

if [ -n "$SOURCE_PLUGIN_JSON" ] && [ -f "$INSTALLED_PLUGINS" ]; then
  SOURCE_VERSION=$(jq -r '.version // ""' "$SOURCE_PLUGIN_JSON" 2>/dev/null)

  if [ -n "$SOURCE_VERSION" ]; then
    # Update cache directory with current source
    mkdir -p "$WM_CACHE_DIR/$SOURCE_VERSION"
    cp -r "$SOURCE_ROOT"/* "$WM_CACHE_DIR/$SOURCE_VERSION/"
    mkdir -p "$WM_CACHE_DIR/$SOURCE_VERSION/.claude-plugin"
    cp "$SOURCE_PLUGIN_JSON" "$WM_CACHE_DIR/$SOURCE_VERSION/.claude-plugin/plugin.json"

    # Remove stale cache versions
    for old_dir in "$WM_CACHE_DIR"/*/; do
      [ -d "$old_dir" ] || continue
      [ "$(basename "$old_dir")" = "$SOURCE_VERSION" ] && continue
      rm -rf "$old_dir"
    done

    # Update installed_plugins.json to reflect current version, path, and commit
    CURRENT_SHA=$(git -C "$PROJECT_DIR" rev-parse HEAD 2>/dev/null || echo "")
    jq --arg ver "$SOURCE_VERSION" \
       --arg path "$WM_CACHE_DIR/$SOURCE_VERSION" \
       --arg now "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)" \
       --arg sha "$CURRENT_SHA" \
      '(.plugins["workflow-manager@azevedo-home-lab"] // []) |= map(
        .version = $ver | .installPath = $path | .lastUpdated = $now | .gitCommitSha = $sha
      )' "$INSTALLED_PLUGINS" > "$INSTALLED_PLUGINS.tmp" \
      && mv "$INSTALLED_PLUGINS.tmp" "$INSTALLED_PLUGINS"
  fi
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
# D. Project hooks — copy hook scripts and register in settings.json
# ─────────────────────────────────────────────────────────────────────────────
# Claude Code reads hooks from .claude/settings.json, NOT from plugin/hooks/hooks.json.
# Copy hook scripts from plugin/scripts/ to .claude/hooks/ as real files (no symlinks).

HOOKS_DIR="$PROJECT_DIR/.claude/hooks"
mkdir -p "$HOOKS_DIR"

for hook in pre-tool-write-gate.sh pre-tool-bash-guard.sh post-tool-coaching.sh; do
  if [ -f "$SOURCE_ROOT/scripts/$hook" ]; then
    cp "$SOURCE_ROOT/scripts/$hook" "$HOOKS_DIR/$hook"
    chmod +x "$HOOKS_DIR/$hook"
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
