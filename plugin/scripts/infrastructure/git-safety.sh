#!/bin/bash
# Git safety checks — commit parsing and destructive operation detection.

[ -n "${_WFM_GIT_SAFETY_LOADED:-}" ] && return 0
_WFM_GIT_SAFETY_LOADED=1

# Check if a command is a git commit and whether it's safe.
# Returns 0: allow (standalone or safe chain)
# Returns 1: deny (commit chained with unsafe commands)
# Returns 2: not a git commit
# IMPORTANT: callers under set -e must use: _rc=0; _check_git_commit "$CMD" || _rc=$?
_check_git_commit() {
    local cmd="$1"

    # Strategy 1: single commit command (may have -m message with shell chars)
    if echo "$cmd" | grep -qE '^[[:space:]]*(git|/usr/bin/git|/usr/local/bin/git)[[:space:]]+commit\b'; then
        local first_line stripped
        first_line=$(echo "$cmd" | head -1)
        stripped=$(echo "$first_line" | sed -E 's/-m "[^"]*"/-m MSG/g; s/-m '"'"'[^'"'"']*'"'"'/-m MSG/g; s/-m [^ ;|&]+/-m MSG/g')
        if ! echo "$stripped" | grep -qE '(&&|\|\||;)'; then
            return 0
        fi
        return 1
    fi

    # Strategy 2: safe git chain (git add && git commit)
    if echo "$cmd" | grep -qE '(git|/usr/bin/git|/usr/local/bin/git)[[:space:]]+commit\b'; then
        local safe=true segment
        while IFS= read -r segment; do
            segment=$(echo "$segment" | sed 's/^[[:space:]]*//')
            [ -z "$segment" ] && continue
            echo "$segment" | grep -qE '^(git|/usr/bin/git|/usr/local/bin/git)[[:space:]]+commit\b' && continue
            if ! echo "$segment" | grep -qE '^(git|/usr/bin/git|/usr/local/bin/git)[[:space:]]+(add|status|diff|stash|log|show)\b'; then
                safe=false
                break
            fi
        done < <(echo "$cmd" | head -1 | sed -E 's/-m "[^"]*"/-m MSG/g; s/-m '"'"'[^'"'"']*'"'"'/-m MSG/g; s/-m [^ ;|&]+/-m MSG/g' | sed 's/&&/\n/g; s/||/\n/g; s/;/\n/g; s/|/\n/g')
        if [ "$safe" = true ]; then
            return 0
        fi
    fi

    return 2
}

# Check if a command is a destructive git operation.
# Returns 0 if destructive, 1 if safe.
_is_destructive_git() {
    local cmd="$1"
    local pattern='(git|/usr/bin/git|/usr/local/bin/git)[[:space:]]+(reset[[:space:]]+--hard|push[[:space:]]+--force|push[[:space:]]+-f[[:space:]]|branch[[:space:]]+-D[[:space:]]|checkout[[:space:]]+--[[:space:]]\.|clean[[:space:]]+-f|rebase[[:space:]]+--abort)'
    echo "$cmd" | grep -qE "$pattern"
}
