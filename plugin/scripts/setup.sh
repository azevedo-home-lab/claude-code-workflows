#!/bin/bash
# Copyright (C) 2026 azevedo-home-lab
# SPDX-License-Identifier: GPL-3.0-only
#
# This file is part of Claude Code Workflows.
# See LICENSE for details.

# Setup hook — runs on first plugin activation (Setup hook in hooks.json).
# Responsibilities:
#   A. Project state initialization (workflow.json + .gitignore)
#   B. Plugin updates (pull marketplace clone, then `claude plugin update`)
#   C. Global statusline installation (~/.claude/statusline.sh + settings.json)
#   D. Project permissions (ensure tools needed for unattended operation are allowed)
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

set -eo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Logging — all output goes to /tmp/wfm-setup.log for debugging
# ─────────────────────────────────────────────────────────────────────────────
mkdir -p "$HOME/.claude/logs"
SETUP_LOG="$HOME/.claude/logs/wfm-setup.log"
_log() { echo "[$(date +%H:%M:%S)] $*" >> "$SETUP_LOG"; }
trap '_log "ERROR at line $LINENO: $BASH_COMMAND"' ERR
_log "───── setup.sh start ─────"
_log "CLAUDE_PLUGIN_ROOT=${CLAUDE_PLUGIN_ROOT:-<unset>}"
_log "CLAUDE_PROJECT_DIR=${CLAUDE_PROJECT_DIR:-<unset>}"
_log "hook_event=${CLAUDE_HOOK_EVENT_NAME:-<unset>}"

# Verify jq is available (required for all JSON state management)
if ! command -v jq &>/dev/null; then
    echo "ERROR: jq is required but not installed. Install it:" >&2
    echo "  macOS:  brew install jq" >&2
    echo "  Ubuntu: sudo apt-get install jq" >&2
    echo "  Other:  https://jqlang.github.io/jq/download/" >&2
    _log "ABORT: jq not found"
    return 1 2>/dev/null || exit 1  # return when sourced, exit when run directly
fi

# Prefer CLAUDE_PLUGIN_ROOT (set by Claude Code hook runner) over BASH_SOURCE fallback
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
  PLUGIN_ROOT="$CLAUDE_PLUGIN_ROOT"
else
  PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

_log "PLUGIN_ROOT=$PLUGIN_ROOT"
_log "PROJECT_DIR=$PROJECT_DIR"

# SOURCE_ROOT: the authoritative plugin source directory.
# Dev mode (.claude-plugin/.dev marker): use the project's plugin/ directory as
# the live source so that edits take effect immediately without cache refresh.
# Production: use the cache ($PLUGIN_ROOT).
# See infrastructure/resolve-script-dir.sh for the shared resolution logic.
if [ -f "$PROJECT_DIR/.claude-plugin/.dev" ] && [ -d "$PROJECT_DIR/plugin/scripts" ]; then
  SOURCE_ROOT="$PROJECT_DIR/plugin"
  _log "MODE=dev (using project plugin/)"
else
  SOURCE_ROOT="$PLUGIN_ROOT"
  _log "MODE=production (using cache)"
fi


# ─────────────────────────────────────────────────────────────────────────────
# 0. Dependencies — ensure marketplaces are registered and plugins installed
# ─────────────────────────────────────────────────────────────────────────────
_log "Section 0: dependency check"
if command -v claude &>/dev/null; then
  INSTALLED_PLUGINS="$HOME/.claude/plugins/installed_plugins.json"
  MARKETPLACES_DIR="$HOME/.claude/plugins/marketplaces"

  # Marketplace → plugin mapping (marketplace-repo plugin@marketplace)
  _deps=(
    "obra/superpowers-marketplace superpowers@superpowers-marketplace"
    "thedotmack/claude-mem claude-mem@thedotmack"
  )

  for _entry in "${_deps[@]}"; do
    _mkt_repo="$(echo "$_entry" | cut -d' ' -f1)"
    _dep="$(echo "$_entry" | cut -d' ' -f2)"
    _dep_name="$(echo "$_dep" | cut -d@ -f1)"
    _mkt_name="$(echo "$_dep" | cut -d@ -f2)"

    # Register marketplace if missing
    if [ ! -d "$MARKETPLACES_DIR/$_mkt_name" ]; then
      _log "Registering marketplace: $_mkt_repo"
      echo "Registering marketplace: $_mkt_name…"
      claude plugin marketplace add "$_mkt_repo" 2>/dev/null || true
    fi

    # Install plugin if missing
    _dep_installed=false
    if [ -f "$INSTALLED_PLUGINS" ]; then
      if jq -e ".plugins[\"$_dep\"]" "$INSTALLED_PLUGINS" &>/dev/null; then
        _dep_installed=true
      fi
    fi
    if [ "$_dep_installed" = false ]; then
      echo "Installing dependency: $_dep_name…"
      _log "Installing dependency: $_dep"
      claude plugin install "$_dep" 2>/dev/null && echo "✔ $_dep_name installed." || echo "⚠ $_dep_name install failed."

      # Run claude-mem's smart-install after first install, since SessionStart
      # already fired and won't re-fire for newly installed plugins.
      # smart-install.js auto-installs Bun via curl, but corporate firewalls
      # may block bun.sh. Try Homebrew first if available.
      if [ "$_dep_name" = "claude-mem" ] && [ -f "$INSTALLED_PLUGINS" ]; then
        # Ensure Bun is available before smart-install runs
        if ! command -v bun &>/dev/null && [ ! -x "$HOME/.bun/bin/bun" ]; then
          if command -v brew &>/dev/null; then
            _log "Bun not found, attempting Homebrew install"
            echo "Installing Bun runtime via Homebrew…"
            brew tap oven-sh/bun 2>/dev/null || true
            brew install bun 2>/dev/null \
              && echo "✔ Bun installed via Homebrew." \
              || echo "⚠ Bun Homebrew install failed, smart-install will try curl fallback."
          fi
        fi

        _CMEM_ROOT=$(jq -r '.plugins["claude-mem@thedotmack"][0].installPath // ""' "$INSTALLED_PLUGINS" 2>/dev/null)
        if [ -n "$_CMEM_ROOT" ] && [ -f "$_CMEM_ROOT/scripts/smart-install.js" ]; then
          _log "Running claude-mem smart-install post-install"
          echo "Setting up claude-mem dependencies…"
          CLAUDE_PLUGIN_ROOT="$_CMEM_ROOT" node "$_CMEM_ROOT/scripts/smart-install.js" 2>/dev/null \
            && echo "✔ claude-mem dependencies ready." \
            || echo "⚠ claude-mem dependency setup failed (will retry next session)."
        fi
      fi
    fi
  done
fi

# ─────────────────────────────────────────────────────────────────────────────
# A. Project state initialization
# ─────────────────────────────────────────────────────────────────────────────
_log "Section A: state init"

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
# A2. Migration: remove stale hook registrations from pre-2.2.0
# ─────────────────────────────────────────────────────────────────────────────
_log "Section A2: migration cleanup"
# Old setup.sh versions copied scripts to .claude/hooks/ and registered them
# in settings.json with $CLAUDE_PROJECT_DIR paths. These stale entries cause
# errors in projects where the scripts don't exist or are outdated.
# The correct mechanism is hooks.json with ${CLAUDE_PLUGIN_ROOT} (set by
# Claude Code only for plugin hooks, not project hooks).
# See docs/plans/2026-04-06-stale-hook-cleanup.md for full investigation.
PROJECT_SETTINGS="$PROJECT_DIR/.claude/settings.json"

# Remove stale hook entries from settings files (user-level, project-level, local)
_STALE_HOOK_PATTERN='\.claude/hooks/(pre-tool-write-gate|pre-tool-bash-guard|post-tool-coaching)\.sh'
for _settings_file in "$HOME/.claude/settings.json" "$PROJECT_SETTINGS" "$PROJECT_DIR/.claude/settings.local.json"; do
  [ -f "$_settings_file" ] || continue
  if grep -qE "$_STALE_HOOK_PATTERN" "$_settings_file" 2>/dev/null; then
    jq '
      def remove_stale:
        if type == "array" then
          [.[] | select(
            (.hooks // []) | all(
              (.command // "") | test("\\.claude/hooks/(pre-tool-write-gate|pre-tool-bash-guard|post-tool-coaching)\\.sh") | not
            )
          )]
        else . end;
      if .hooks then
        .hooks |= with_entries(
          .value |= remove_stale | select(.value | length > 0)
        ) |
        if (.hooks | length) == 0 then del(.hooks) else . end
      else . end
    ' "$_settings_file" > "$_settings_file.tmp" && mv "$_settings_file.tmp" "$_settings_file" || true
  fi
done

# Remove stale .claude/hooks/ script copies (only WFM scripts, not user hooks)
_HOOKS_DIR="$PROJECT_DIR/.claude/hooks"
if [ -d "$_HOOKS_DIR" ]; then
  for _hook in pre-tool-write-gate.sh pre-tool-bash-guard.sh post-tool-coaching.sh; do
    rm -f "$_HOOKS_DIR/$_hook"
  done
  rmdir "$_HOOKS_DIR" 2>/dev/null || true
fi

# ─────────────────────────────────────────────────────────────────────────────
# B. Plugin updates — keep all plugins at latest version
# ─────────────────────────────────────────────────────────────────────────────
# Claude Code doesn't auto-update plugins or marketplace clones.
# Strategy: pull the marketplace clone, then let `claude plugin update` handle
# cache sync and registry updates. No manual cache copying needed.
_log "Section B: plugin updates"

if command -v claude &>/dev/null; then
  # Update external dependencies
  for plugin in \
    "superpowers@superpowers-marketplace" \
    "claude-mem@thedotmack"; do
    claude plugin update "$plugin" 2>/dev/null || true
  done

  # Pull marketplace clone so `claude plugin update` sees the latest version.
  WM_MARKETPLACE_DIR="$HOME/.claude/plugins/marketplaces/azevedo-home-lab"
  if [ -d "$WM_MARKETPLACE_DIR/.git" ]; then
    git -C "$WM_MARKETPLACE_DIR" reset --hard HEAD --quiet 2>/dev/null || true
    git -C "$WM_MARKETPLACE_DIR" clean -fd --quiet 2>/dev/null || true
    echo "Checking for updates for plugin \"workflow-manager@azevedo-home-lab\" at user scope…"
    _PULL_OUTPUT=$(GIT_SSH_COMMAND="ssh -o ConnectTimeout=10" git -C "$WM_MARKETPLACE_DIR" pull origin main 2>&1) || true
    if echo "$_PULL_OUTPUT" | grep -q "Already up to date"; then
      echo "✔ workflow-manager is already at the latest version."
    elif echo "$_PULL_OUTPUT" | grep -q "Updating"; then
      _NEW_VER=$(jq -r '.plugins[0].version // "unknown"' "$WM_MARKETPLACE_DIR/.claude-plugin/marketplace.json" 2>/dev/null) || _NEW_VER="unknown"
      echo "✔ workflow-manager updated to ${_NEW_VER}."
    else
      echo "⚠ workflow-manager update check failed (network or SSH)."
    fi
  fi

  # Let Claude Code update the cache from the freshly pulled marketplace clone
  claude plugin update "workflow-manager@azevedo-home-lab" 2>/dev/null || true
fi

# Clean up stale WFM cache versions — keep only the current one
WM_CACHE_DIR="$HOME/.claude/plugins/cache/azevedo-home-lab/workflow-manager"
if [ -d "$WM_CACHE_DIR" ]; then
  _current_ver="$(basename "$PLUGIN_ROOT")"
  for _old_dir in "$WM_CACHE_DIR"/*/; do
    [ -d "$_old_dir" ] || continue
    [ "$(basename "$_old_dir")" = "$_current_ver" ] && continue
    _log "Removing stale cache: $_old_dir"
    rm -rf "$_old_dir"
  done
fi

# ─────────────────────────────────────────────────────────────────────────────
# C. Global statusline installation
# ─────────────────────────────────────────────────────────────────────────────
_log "Section C: statusline"

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
# D. Project commands — copy to .claude/commands/ for un-namespaced /slash access
# ─────────────────────────────────────────────────────────────────────────────
_log "Section D: commands copy"
# Plugin commands are namespaced by Claude Code (e.g. /workflow-manager:discuss).
# We want /discuss, so we copy commands to the project's .claude/commands/ directory.
# Commands use ${CLAUDE_SKILL_DIR}/../scripts/ which only works from the plugin cache.
# For project-level copies, we rewrite that to the absolute cache scripts path.
COMMANDS_SRC="$SOURCE_ROOT/commands"
COMMANDS_DST="$PROJECT_DIR/.claude/commands"
SCRIPTS_PATH="$PLUGIN_ROOT/scripts"

if [ -d "$COMMANDS_SRC" ]; then
  mkdir -p "$COMMANDS_DST"
  _copied=0
  for cmd_file in "$COMMANDS_SRC/"*.md; do
    [ -f "$cmd_file" ] || continue
    sed "s|\${CLAUDE_SKILL_DIR}/../scripts|${SCRIPTS_PATH}|g" \
      "$cmd_file" > "$COMMANDS_DST/$(basename "$cmd_file")"
    _copied=$((_copied + 1))
  done
  _log "Copied $_copied commands to $COMMANDS_DST"
  echo "✔ $_copied slash commands installed to .claude/commands/"
else
  _log "WARN: commands source not found: $COMMANDS_SRC"
  echo "⚠ No commands found to install."
fi

# ─────────────────────────────────────────────────────────────────────────────
# E. Project permissions — ensure tools needed for workflow pipeline are allowed
# ─────────────────────────────────────────────────────────────────────────────
_log "Section E: permissions"

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

# Read version for summary
_WFM_VER=""
if [ -f "$PLUGIN_ROOT/.claude-plugin/plugin.json" ]; then
  _WFM_VER=$(jq -r '.version // ""' "$PLUGIN_ROOT/.claude-plugin/plugin.json" 2>/dev/null)
elif [ -f "$SOURCE_ROOT/.claude-plugin/plugin.json" ]; then
  _WFM_VER=$(jq -r '.version // ""' "$SOURCE_ROOT/.claude-plugin/plugin.json" 2>/dev/null)
fi
echo "✔ Workflow Manager ${_WFM_VER:-unknown} ready. Log: ~/.claude/logs/wfm-setup.log"

_log "───── setup.sh complete ─────"
