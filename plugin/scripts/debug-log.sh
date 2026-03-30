#!/bin/bash
# Copyright (C) 2026 azevedo-home-lab
# SPDX-License-Identifier: GPL-3.0-only
#
# This file is part of Claude Code Workflows.
# See LICENSE for details.

# Shared debug logging module for workflow hook scripts.
# Provides _log() that writes to /tmp/wfm-<caller>-debug.log when DEBUG_MODE=true.
#
# Usage (source AFTER DEBUG_MODE is set):
#   DEBUG_MODE=$(get_debug)
#   source "$SCRIPT_DIR/debug-log.sh" "workflow-gate"
#
# Enable:  .claude/hooks/workflow-cmd.sh set_debug "true"
# Read:    cat /tmp/wfm-workflow-gate-debug.log
# Clear:   rm /tmp/wfm-*-debug.log

_WFM_DEBUG_CALLER="${1:-unknown}"
_WFM_DEBUG_LOG="/tmp/wfm-${_WFM_DEBUG_CALLER}-debug.log"

if [ "${DEBUG_MODE:-}" = "true" ]; then
    _log() { echo "[$(date +%H:%M:%S)] [$$] $*" >> "$_WFM_DEBUG_LOG"; }
    _log "=== $_WFM_DEBUG_CALLER invoked ==="
    _log "SCRIPT_DIR=${SCRIPT_DIR:-<unset>}"
    _log "CLAUDE_PROJECT_DIR=${CLAUDE_PROJECT_DIR:-<unset>}"
    _log "CLAUDE_PLUGIN_ROOT=${CLAUDE_PLUGIN_ROOT:-<unset>}"
    _log "STATE_FILE=${STATE_FILE:-<unset>}"
    _log "PWD=$(pwd)"
    _log "PHASE=${PHASE:-<unset>}"
else
    _log() { :; }
fi
