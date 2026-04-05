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
#   D. Project commands (copy to .claude/commands/)
#   E. Project permissions (ensure tools needed for unattended operation are allowed)
#
# Hook deployment strategy:
#   Hooks are defined exclusively in plugin/hooks/hooks.json — Claude Code auto-wires
#   them and sets CLAUDE_PLUGIN_ROOT at runtime, pointing to the plugin cache. Scripts
#   run directly from the cache. No copies or symlinks are placed in .claude/hooks/.
#   This avoids two broken alternatives:
#     - Symlinks: fragile across environments, don't make sense for distributed plugins.
#     - Copies in settings.json: Claude Code does NOT set CLAUDE_PLUGIN_ROOT for project
#       hooks (only for plugin hooks), so scripts can't resolve their dependencies.
#   Cache freshness is handled by section B (marketplace pull + version comparison).

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
# project config (permissions) that should be committed.
# .claude/hooks/ is no longer created — hooks run from the plugin cache.
GITIGNORE="$PROJECT_DIR/.gitignore"
_WFM_GITIGNORE_ENTRIES=(
  ".claude/state/"
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

# After pulling, check if the marketplace clone has a newer version than our
# current SOURCE_ROOT. This handles the case where setup.sh is running from
# an old cache — the marketplace clone now has the latest code from git pull,
# so we should sync from it instead of re-copying stale cache over itself.
WM_MARKETPLACE_PLUGIN_JSON="$WM_MARKETPLACE_DIR/.claude-plugin/plugin.json"
if [ -f "$WM_MARKETPLACE_PLUGIN_JSON" ]; then
  _MKT_VERSION=$(jq -r '.version // ""' "$WM_MARKETPLACE_PLUGIN_JSON" 2>/dev/null)
  _SRC_VERSION=$(jq -r '.version // ""' "${SOURCE_PLUGIN_JSON:-/dev/null}" 2>/dev/null) || _SRC_VERSION=""
  if [ -n "$_MKT_VERSION" ] && [ "$_MKT_VERSION" != "$_SRC_VERSION" ]; then
    # Marketplace has a different (newer) version — use it as source
    SOURCE_ROOT="$WM_MARKETPLACE_DIR/plugin"
    SOURCE_PLUGIN_JSON="$WM_MARKETPLACE_PLUGIN_JSON"
  fi
  unset _MKT_VERSION _SRC_VERSION
fi

# Sync workflow-manager cache from source (local dev, cache, or marketplace clone)
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

    # Update installed_plugins.json to reflect current version, path, and commit.
    # Read SHA from whichever source we're syncing from (marketplace clone or project).
    _SHA_DIR="$WM_MARKETPLACE_DIR"
    [ -f "$PROJECT_DIR/.claude-plugin/.dev" ] && _SHA_DIR="$PROJECT_DIR"
    CURRENT_SHA=$(git -C "$_SHA_DIR" rev-parse HEAD 2>/dev/null || echo "")
    unset _SHA_DIR
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
# [Removed] Project hooks — no longer copied or registered here.
# ─────────────────────────────────────────────────────────────────────────────
# Hooks are defined exclusively in plugin/hooks/hooks.json and auto-wired by
# Claude Code, which sets CLAUDE_PLUGIN_ROOT at runtime. Scripts run directly
# from the plugin cache. Copying to .claude/hooks/ and registering in
# settings.json was the old approach — it broke because Claude Code does NOT
# set CLAUDE_PLUGIN_ROOT for project hooks (settings.json), only for plugin
# hooks (hooks.json). Symlinks were also rejected as fragile across environments.
#
# Migration cleanup: remove stale hook files and settings.json registrations
# left by previous versions.
PROJECT_SETTINGS="$PROJECT_DIR/.claude/settings.json"
HOOKS_DIR="$PROJECT_DIR/.claude/hooks"
if [ -d "$HOOKS_DIR" ]; then
  for hook in pre-tool-write-gate.sh pre-tool-bash-guard.sh post-tool-coaching.sh; do
    rm -f "$HOOKS_DIR/$hook"
  done
  # Remove hooks dir if empty (may contain user's own hooks)
  rmdir "$HOOKS_DIR" 2>/dev/null || true
fi
# Remove stale hook registrations from settings.json and settings.local.json
for _settings_file in "$PROJECT_SETTINGS" "$PROJECT_DIR/.claude/settings.local.json"; do
  if [ -f "$_settings_file" ]; then
    if jq -e 'has("hooks")' "$_settings_file" &>/dev/null; then
      jq 'del(.hooks)' "$_settings_file" > "$_settings_file.tmp" \
        && mv "$_settings_file.tmp" "$_settings_file" || true
    fi
  fi
done

# ─────────────────────────────────────────────────────────────────────────────
# D. Project commands — copy plugin commands to .claude/commands/
# ─────────────────────────────────────────────────────────────────────────────

COMMANDS_DIR="$PROJECT_DIR/.claude/commands"
mkdir -p "$COMMANDS_DIR"

for cmd_file in "$SOURCE_ROOT/commands/"*.md; do
  [ -f "$cmd_file" ] || continue
  cp "$cmd_file" "$COMMANDS_DIR/$(basename "$cmd_file")"
done

# ─────────────────────────────────────────────────────────────────────────────
# E. Project permissions — ensure tools needed for workflow pipeline are allowed
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
