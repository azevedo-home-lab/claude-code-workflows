#!/bin/bash
# Copyright (C) 2026 azevedo-home-lab
# SPDX-License-Identifier: GPL-3.0-only
#
# This file is part of Claude Code Workflows.
# See LICENSE for details.

# Read-only command allowlist for DEFINE/DISCUSS/ERROR phases.
# Commands not on this list are denied. This closes the regex arms race
# by defaulting to deny instead of trying to detect every write vector.

[ -n "${_WFM_READ_ALLOWLIST_LOADED:-}" ] && return 0
_WFM_READ_ALLOWLIST_LOADED=1

# Check if a command is on the read-only allowlist.
# For chained commands (&&, ||, ;), checks each segment independently.
# Returns 0 if allowed, 1 if not.
_is_allowed_readonly() {
    local cmd="$1"

    # Split chained commands and check each segment
    local segment
    while IFS= read -r segment; do
        segment=$(echo "$segment" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
        [ -z "$segment" ] && continue
        if ! _is_single_cmd_allowed "$segment"; then
            return 1
        fi
    done < <(echo "$cmd" | sed 's/&&/\n/g; s/||/\n/g; s/;/\n/g; s/|/\n/g')

    return 0
}

# Check if a single (non-chained, non-piped) command contains a redirect to a file.
# Returns 0 if redirect found (should deny), 1 if no redirect.
_has_file_redirect() {
    local cmd="$1"
    # Strip safe redirects (2>/dev/null, 2>&1, etc.) before checking
    local clean
    clean=$(echo "$cmd" | sed -E 's/[0-9]+>\/dev\/null//g; s/[0-9]*>&[0-9]+//g; s/>>[[:space:]]*\/dev\/null//g; s/>[[:space:]]*\/dev\/null//g')
    # Check for remaining > or >> (file redirects)
    echo "$clean" | grep -qE '(>[^&]|>>)'
}

# Check if a single (non-chained) command is allowed.
# Extracts the first command word, strips path prefixes.
# Also rejects commands with file redirects (> or >>).
_is_single_cmd_allowed() {
    local cmd="$1"

    # Reject any command with file redirects — even allowed commands
    # cannot write to files via > or >> in allowlist phases
    if _has_file_redirect "$cmd"; then
        return 1
    fi

    # Extract first word, strip path prefix (e.g., /usr/bin/git → git)
    local first_word
    first_word=$(echo "$cmd" | awk '{print $1}')
    first_word=$(basename "$first_word" 2>/dev/null || echo "$first_word")

    case "$first_word" in
        # Core reads
        cat|head|tail|less|more|wc|file|stat|du|df) return 0 ;;

        # Search
        find|grep|rg|ag|ack|locate|which|whereis|type|command) return 0 ;;

        # JSON/data
        jq|yq|xmllint|csvtool) return 0 ;;

        # Text processing (sed without -i is checked below)
        sort|uniq|cut|tr|awk|column|fmt|fold|diff|diff3|comm|paste) return 0 ;;

        # System info
        echo|printf|date|env|printenv|uname|hostname|pwd|id|whoami) return 0 ;;

        # Directory listing
        ls|tree|exa|eza|fd) return 0 ;;

        # Path utilities
        basename|dirname|realpath|readlink) return 0 ;;

        # Shell builtins/conditionals
        true|false|test|"["|"[[") return 0 ;;

        # Workflow commands
        workflow-cmd.sh|workflow-facade.sh|workflow-state.sh) return 0 ;;

        # Git — check subcommand
        git)
            local git_sub
            git_sub=$(echo "$cmd" | awk '{for(i=1;i<=NF;i++){if($i!~"^-"){if($i!="git"&&$i!~/^\//)print $i; break}}}' | head -1)
            # If we couldn't extract a subcommand, try second word
            [ -z "$git_sub" ] && git_sub=$(echo "$cmd" | awk '{print $2}')
            case "$git_sub" in
                log|diff|status|show|branch|remote|rev-parse|ls-files|blame|tag|describe|shortlog|reflog|config|help|version) return 0 ;;
                stash)
                    # stash list/show are read-only; stash push/pop/drop are not
                    echo "$cmd" | grep -qE 'stash[[:space:]]+(list|show)' && return 0
                    return 1 ;;
                add|commit)
                    # git add and git commit allowed — they write to git objects, not working tree files
                    return 0 ;;
                *) return 1 ;;
            esac ;;

        # sed — only without -i
        sed)
            echo "$cmd" | grep -qE 'sed[[:space:]]+-i' && return 1
            return 0 ;;

        # curl — only without -o/-O (download to file)
        curl)
            echo "$cmd" | grep -qE 'curl[[:space:]].*-[oO][[:space:]]' && return 1
            return 0 ;;

        # wget — only without -O (download to file)
        wget)
            echo "$cmd" | grep -qE 'wget[[:space:]].*-O[[:space:]]' && return 1
            return 0 ;;

        # Network reads
        ping|dig|nslookup|host|nc) return 0 ;;

        # Dev tools — read-only invocations
        npm)
            echo "$cmd" | grep -qE 'npm[[:space:]]+(list|ls|view|info|outdated|audit|explain|why|pack.*--dry)' && return 0
            echo "$cmd" | grep -qE 'npm[[:space:]]+(test|run[[:space:]]+lint|run[[:space:]]+check|run[[:space:]]+typecheck)' && return 0
            return 1 ;;
        pip|pip3)
            echo "$cmd" | grep -qE 'pip[3]?[[:space:]]+(list|show|freeze|check)' && return 0
            return 1 ;;
        cargo)
            echo "$cmd" | grep -qE 'cargo[[:space:]]+(check|clippy|test|doc|version|--version)' && return 0
            return 1 ;;
        make)
            echo "$cmd" | grep -qE 'make[[:space:]]+(-n|--dry-run|--just-print)' && return 0
            return 1 ;;
        rustc|gcc|clang|javac)
            echo "$cmd" | grep -qE '(--version|-v[[:space:]]*$)' && return 0
            return 1 ;;

        # Container reads
        docker)
            echo "$cmd" | grep -qE 'docker[[:space:]]+(ps|images|image[[:space:]]+ls|inspect|logs|info|version|stats|top|port|diff|history)' && return 0
            return 1 ;;
        kubectl)
            echo "$cmd" | grep -qE 'kubectl[[:space:]]+(get|describe|logs|top|explain|api-resources|version)' && return 0
            return 1 ;;

        # python/node/ruby/perl -c — check for write indicators
        python|python3)
            echo "$cmd" | grep -qiE '\.(write|open|read_text|write_text)|os\.(system|remove|rename|unlink|makedirs)|subprocess\.|shutil\.' && return 1
            return 0 ;;
        node)
            echo "$cmd" | grep -qiE 'fs\.|writeFile|appendFile|createWriteStream|child_process|exec\(|spawn\(' && return 1
            return 0 ;;
        ruby)
            echo "$cmd" | grep -qiE 'File\.|IO\.|open\(|system\(|exec\(|`' && return 1
            return 0 ;;
        perl)
            echo "$cmd" | grep -qiE 'open\(|system\(|unlink|rename' && return 1
            return 0 ;;

        # source/dot — allowed for workflow scripts
        source|.)
            echo "$cmd" | grep -qE 'workflow-(state|facade|cmd)\.sh' && return 0
            return 1 ;;

        # Path with workflow script
        *)
            echo "$first_word" | grep -qE 'workflow-cmd\.sh' && return 0
            return 1 ;;
    esac
}
