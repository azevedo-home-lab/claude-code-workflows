#!/bin/bash
# Write operation detection — regex patterns and language-specific write detection.
# Used only in COMPLETE phase denylist path.

[ -n "${_WFM_WRITE_PATTERNS_LOADED:-}" ] && return 0
_WFM_WRITE_PATTERNS_LOADED=1

# Detect if a command contains a write operation.
# Returns 0 if write detected, 1 if no write.
# Sets DETECTED_WRITE_TYPE for logging.
_detect_write_operation() {
    local cmd="$1"
    DETECTED_WRITE_TYPE=""

    # Strip safe redirects before checking
    local clean_cmd
    clean_cmd=$(echo "$cmd" | sed -E 's/[0-9]+>\/dev\/null//g; s/[0-9]*>&[0-9]+//g; s/>>[[:space:]]*\/dev\/null//g; s/>[[:space:]]*\/dev\/null//g')

    # --- Shell write patterns ---
    local REDIRECT_OPS='(>[^&]|>>)'
    local HEREDOCS='(cat[[:space:]].*<<|bash[[:space:]].*<<|sh[[:space:]].*<<|python[3]?[[:space:]].*<<)'
    local ECHO_REDIRECT='(echo[[:space:]].*>)'
    local INPLACE_EDITORS='(sed[[:space:]]+-i|perl[[:space:]]+-i|ruby[[:space:]]+-i)'
    local STREAM_WRITERS='(tee[[:space:]])'
    local FILE_OPS='((^|[;&|[:space:]])(cp|mv|rm|install|patch|ln|touch|truncate)[[:space:]])'
    local DOWNLOADS='(curl[[:space:]].*-o[[:space:]]|wget[[:space:]].*-O[[:space:]])'
    local ARCHIVE_OPS='(tar[[:space:]].*-?x|unzip[[:space:]])'
    local BLOCK_OPS='(dd[[:space:]].*of=)'
    local SYNC_OPS='(rsync[[:space:]])'
    local EXEC_WRAPPERS='(eval[[:space:]]|bash[[:space:]]+-c|sh[[:space:]]+-c)'
    local PIPE_SHELL='(\|[[:space:]]*(/[^[:space:]]*/)?((env[[:space:]]+(/[^[:space:]]*/)?)?'\
'(bash|sh|zsh|dash|ksh|fish|csh|tcsh))(\b|$))'
    local PROC_SUB='((/[^[:space:]]*/)?((bash|sh|zsh|dash|ksh|fish|csh|tcsh)|source|\.)[[:space:]]+<\()'
    local XARGS_EXEC='(\|[[:space:]]*xargs[[:space:]]+(bash|sh|rm|mv|cp|tee|sed))'
    local GH_OPS='(gh[[:space:]])'

    local WRITE_PATTERN="$REDIRECT_OPS|$INPLACE_EDITORS|$STREAM_WRITERS|$HEREDOCS|$FILE_OPS|$DOWNLOADS|$ARCHIVE_OPS|$BLOCK_OPS|$SYNC_OPS|$EXEC_WRAPPERS|$ECHO_REDIRECT|$PIPE_SHELL|$PROC_SUB|$XARGS_EXEC|$GH_OPS"

    if echo "$clean_cmd" | grep -qE "$WRITE_PATTERN"; then
        DETECTED_WRITE_TYPE="shell-pattern"
        return 0
    fi

    # --- Language-specific write detection ---
    if echo "$cmd" | grep -qE 'python[3]?[[:space:]]+-c'; then
        if echo "$cmd" | grep -qiE '\.(write|open|read_text|write_text)|os\.(system|remove|rename|unlink|makedirs)|subprocess\.(run|call|Popen|check_call|check_output)|shutil\.(copy|move|rmtree|copytree)'; then
            DETECTED_WRITE_TYPE="python-write"
            return 0
        fi
    fi

    if echo "$cmd" | grep -qE 'node[[:space:]]+(--eval|-e)[[:space:]]'; then
        if echo "$cmd" | grep -qiE 'fs\.|writeFile|appendFile|createWriteStream|child_process|exec\(|spawn\('; then
            DETECTED_WRITE_TYPE="node-write"
            return 0
        fi
    fi

    if echo "$cmd" | grep -qE 'ruby[[:space:]]+-e[[:space:]]'; then
        if echo "$cmd" | grep -qiE 'File\.|IO\.|open\(|system\(|exec\(|`'; then
            DETECTED_WRITE_TYPE="ruby-write"
            return 0
        fi
    fi

    if echo "$cmd" | grep -qE 'perl[[:space:]]+-e[[:space:]]'; then
        if echo "$cmd" | grep -qiE 'open\(|system\(|unlink|rename'; then
            DETECTED_WRITE_TYPE="perl-write"
            return 0
        fi
    fi

    return 1
}

# Extract the write target path from a command (best-effort heuristic).
# Returns the target path or empty string.
_extract_write_target() {
    local cmd="$1"
    local target

    # For redirections: extract path after > or >>
    target=$(echo "$cmd" | sed -n 's/.*>[[:space:]]*\([^[:space:];|&]*\).*/\1/p' | head -1)
    if [ -z "$target" ]; then
        # For cp/mv: extract the last argument
        target=$(echo "$cmd" | sed -n 's/.*\(cp\|mv\|install\)[[:space:]].*[[:space:]]\([^[:space:];|&]*\)[[:space:]]*$/\2/p' | head -1)
    fi

    # Reject path traversal
    if [ -n "$target" ] && echo "$target" | grep -qE '\.\.'; then
        echo ""
        return
    fi

    echo "$target"
}
