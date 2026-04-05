#!/bin/bash
# Copyright (C) 2026 azevedo-home-lab
# SPDX-License-Identifier: GPL-3.0-only
#
# This file is part of Claude Code Workflows.
# See LICENSE for details.

# Resolve SCRIPT_DIR and PLUGIN_ASSETS_ROOT for hook scripts.
#
# Two variables are exported:
#   SCRIPT_DIR          — path to plugin/scripts/ (for sourcing .sh modules)
#   PLUGIN_ASSETS_ROOT  — path to plugin root (for coaching/, agents/, config/, phases/)
#
# Resolution order:
#   1. Dev marker: if .claude-plugin/.dev exists in the current project,
#      use the project's plugin/ directory as the live source.
#      This gives developers instant feedback — edit a script, see it run.
#   2. Plugin cache: use CLAUDE_PLUGIN_ROOT (set by Claude Code's hook runner)
#      which points to the installed, cached plugin version.
#   3. Fallback: derive from this script's own filesystem location (BASH_SOURCE).
#      Covers manual invocation outside Claude Code.
#
# Dev mode setup:
#   touch .claude-plugin/.dev    # in the ClaudeWorkflows repo root
#   # .gitignore already excludes this file — it won't ship to users.
#
# IMPORTANT: This file resolves paths to PLUGIN assets (scripts, coaching, agents).
# For PROJECT paths (state files, .claude/state/), use CLAUDE_PROJECT_DIR directly.
# These are different concepts:
#   PLUGIN_ASSETS_ROOT → where the plugin code lives (cache or dev source)
#   CLAUDE_PROJECT_DIR → where the user's project lives (state, hooks, commands)

[ -n "${_WFM_RESOLVE_SCRIPT_DIR_LOADED:-}" ] && return 0
_WFM_RESOLVE_SCRIPT_DIR_LOADED=1

_PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

if [ -f "$_PROJECT_DIR/.claude-plugin/.dev" ]; then
    # Dev mode: use live source from project for instant edit-run feedback
    PLUGIN_ASSETS_ROOT="$_PROJECT_DIR/plugin"
    SCRIPT_DIR="$PLUGIN_ASSETS_ROOT/scripts"
elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
    # Production: use the cached plugin installed by Claude Code
    PLUGIN_ASSETS_ROOT="$CLAUDE_PLUGIN_ROOT"
    SCRIPT_DIR="$PLUGIN_ASSETS_ROOT/scripts"
else
    # Fallback: derive from this file's location (manual invocation)
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    PLUGIN_ASSETS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
fi

unset _PROJECT_DIR
