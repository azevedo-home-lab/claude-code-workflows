#!/bin/bash
# Copyright (C) 2026 azevedo-home-lab
# SPDX-License-Identifier: GPL-3.0-only
#
# This file is part of Claude Code Workflows.
# See LICENSE for details.

# Shared debug logging module for workflow hook scripts.
# Provides _log() for file-only logging and _show() for user-visible output.
# Three levels: off (no logging), log (file only), show (file + stderr).
#
# Usage (source AFTER DEBUG_MODE is set):
#   DEBUG_MODE=$(get_debug)
#   source "$SCRIPT_DIR/debug-log.sh" "workflow-gate"
#
# Enable:  .claude/hooks/workflow-cmd.sh set_debug "log"    (file only)
#          .claude/hooks/workflow-cmd.sh set_debug "show"   (file + stderr)
# Read:    cat /tmp/wfm-workflow-gate-debug.log
# Clear:   rm /tmp/wfm-*-debug.log

_WFM_DEBUG_CALLER="${1:-unknown}"
_WFM_DEBUG_LOG="/tmp/wfm-${_WFM_DEBUG_CALLER}-debug.log"

# Normalize DEBUG_MODE: true→log, false/empty→off, otherwise keep as-is
case "${DEBUG_MODE:-}" in
    true)  _WFM_DEBUG_LEVEL="log" ;;
    false|"") _WFM_DEBUG_LEVEL="off" ;;
    off|log|show) _WFM_DEBUG_LEVEL="$DEBUG_MODE" ;;
    *) _WFM_DEBUG_LEVEL="off" ;;
esac

if [ "$_WFM_DEBUG_LEVEL" = "log" ] || [ "$_WFM_DEBUG_LEVEL" = "show" ]; then
    _log() { echo "[$(date +%H:%M:%S)] [$$] $*" >> "$_WFM_DEBUG_LOG"; }
    if [ "$_WFM_DEBUG_LEVEL" = "show" ]; then
        _show() { echo "$*" >> "$_WFM_DEBUG_LOG"; echo "$*" >&2; }
    else
        _show() { echo "$*" >> "$_WFM_DEBUG_LOG"; }
    fi
    _log "=== $_WFM_DEBUG_CALLER invoked ==="
    _log "SCRIPT_DIR=${SCRIPT_DIR:-<unset>}"
    _log "CLAUDE_PROJECT_DIR=${CLAUDE_PROJECT_DIR:-<unset>}"
    _log "CLAUDE_PLUGIN_ROOT=${CLAUDE_PLUGIN_ROOT:-<unset>}"
    _log "STATE_FILE=${STATE_FILE:-<unset>}"
    _log "PWD=$(pwd)"
    _log "PHASE=${PHASE:-<unset>}"
else
    _log() { :; }
    _show() { :; }
fi
