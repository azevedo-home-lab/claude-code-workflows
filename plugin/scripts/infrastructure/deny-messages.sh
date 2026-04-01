#!/bin/bash
# Copyright (C) 2026 azevedo-home-lab
# SPDX-License-Identifier: GPL-3.0-only
#
# This file is part of Claude Code Workflows.
# See LICENSE for details.

# Phase-aware deny messages and PreToolUse deny JSON emitter.

[ -n "${_WFM_DENY_MESSAGES_LOADED:-}" ] && return 0
_WFM_DENY_MESSAGES_LOADED=1

# Emit a PreToolUse deny JSON response.
# Outputs JSON to stdout (Claude Code hook protocol) and reason to stderr (user visibility).
# Usage: emit_deny "reason message"
emit_deny() {
    local reason="$1"
    local caller="${_WFM_DEBUG_CALLER:-unknown-hook}"
    echo "[WFM $caller] $reason" >&2
    jq -n --arg reason "$reason" '{
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": $reason
        }
    }'
}

# Generate a phase-aware deny reason string.
# Usage: _phase_deny_message <phase> <context>
# Contexts: "write", "bash-write", "guard-system", "state-file", "destructive-git", "user-set-phase"
_phase_deny_message() {
    local phase="$1" context="$2"

    case "$context" in
        guard-system)
            echo "BLOCKED: Edits to enforcement files (.claude/hooks/, plugin/scripts/, plugin/commands/) are not allowed in any phase. These files define the workflow rules. Use !backtick if you need to make legitimate changes."
            return ;;
        state-file)
            echo "BLOCKED: Direct writes to workflow state files are not allowed."
            return ;;
        destructive-git)
            echo "BLOCKED: Destructive git operation detected (reset --hard, push --force, branch -D, checkout --, clean -f, rebase --abort). These operations can cause irreversible data loss. Use !backtick if you need to run this command."
            return ;;
        user-set-phase)
            echo "BLOCKED: user-set-phase.sh is the user-only phase transition path. It cannot be called via Bash tool — only from !backtick command files."
            return ;;
        chained-commit)
            echo "BLOCKED: 'git commit' chained with other commands is not allowed. Run git commit as a standalone command."
            return ;;
    esac

    case "$phase" in
        define)
            case "$context" in
                write)      echo "BLOCKED: Phase is DEFINE. Code changes are not allowed until you define the problem and outcomes." ;;
                bash-write) echo "BLOCKED: Bash write operation detected in DEFINE phase. Code changes are not allowed until you define the problem and outcomes." ;;
            esac ;;
        discuss)
            case "$context" in
                write)      echo "BLOCKED: Phase is DISCUSS. Code changes are not allowed until the design phase is complete. Use /implement to proceed to implementation." ;;
                bash-write) echo "BLOCKED: Bash write operation detected in DISCUSS phase. Code changes are not allowed until the design phase is complete. Use /implement to proceed to implementation." ;;
            esac ;;
        complete)
            case "$context" in
                write)      echo "BLOCKED: Phase is COMPLETE. Code changes are not allowed during completion. Only documentation updates are permitted." ;;
                bash-write) echo "BLOCKED: Bash write operation detected in COMPLETE phase. Code changes are not allowed during completion. Only documentation updates are permitted." ;;
            esac ;;
        error)
            echo "BLOCKED: Workflow state is corrupted. All writes blocked for safety. Run /off to reset." ;;
        *)
            echo "BLOCKED: Unexpected phase ($phase)." ;;
    esac
}
