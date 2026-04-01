#!/bin/bash
# Copyright (C) 2026 azevedo-home-lab
# SPDX-License-Identifier: GPL-3.0-only
#
# This file is part of Claude Code Workflows.
# See LICENSE for details.

# GitHub CLI safety checks — phase-aware gh command validation.

[ -n "${_WFM_GH_SAFETY_LOADED:-}" ] && return 0
_WFM_GH_SAFETY_LOADED=1

# Check if a gh command is allowed in the given phase.
# Returns 0 (allow) or 1 (deny).
# Args: $1 = command string, $2 = phase
_check_gh_command() {
    local cmd="$1" phase="$2"

    # Only applies to gh commands
    echo "$cmd" | grep -qE '^[[:space:]]*(gh)[[:space:]]' || return 1

    if [ "$phase" = "complete" ] && _gh_safe_chain "$cmd"; then
        return 0
    elif [ "$phase" = "define" ] || [ "$phase" = "discuss" ] || [ "$phase" = "error" ]; then
        if echo "$cmd" | grep -qE '^[[:space:]]*gh[[:space:]]+(repo[[:space:]]+view|issue[[:space:]]+(view|list|comment)|pr[[:space:]]+(view|list)|release[[:space:]]+(view|list)|api[[:space:]])' && \
           _gh_safe_chain "$cmd"; then
            return 0
        fi
    fi

    return 1
}

# Check if a gh command has safe chaining (no shell injection vectors).
_gh_safe_chain() {
    local cmd="$1"
    # Strip harmless fallback suffixes before chain check:
    # || true, || echo ..., || gh ... (retry/fallback patterns)
    local stripped
    stripped=$(echo "$cmd" | sed -E 's/\|\|[[:space:]]*(true|echo[[:space:]][^;&|]*|gh[[:space:]].*)$//')
    ! echo "$stripped" | grep -qE '(&&|\|\||;)' && \
    ! echo "$cmd" | grep -qE '\|[[:space:]]*(/[^[:space:]]*/)?((env[[:space:]]+(/[^[:space:]]*/)?)?'\
'(bash|sh|zsh|dash|ksh|fish|csh|tcsh))(\b|$)' && \
    ! echo "$cmd" | grep -qE '(/[^[:space:]]*/)?((bash|sh|zsh|dash|ksh|fish|csh|tcsh)|source|\.)[[:space:]]+<\(' && \
    ! echo "$cmd" | grep -qE '\|[[:space:]]*xargs[[:space:]]+(bash|sh|rm|mv|cp|tee|sed)' && \
    ! echo "$cmd" | grep -qE '\|[[:space:]]*(tee|sed|dd|cp|mv|install|python[3]?|node|ruby|perl|awk)\b'
}
