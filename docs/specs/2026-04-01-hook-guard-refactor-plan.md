# Hook Guard Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor pre-tool-write-gate.sh and pre-tool-bash-guard.sh into focused modules with shared infrastructure, switching DEFINE/DISCUSS to allowlist enforcement.

**Architecture:** Extract shared hook bootstrap, deny messages, write detection, git safety, gh safety, and read allowlist into separate infrastructure modules. Both hooks become thin orchestrators. DEFINE/DISCUSS use allowlist (strict), COMPLETE uses denylist (permissive).

**Tech Stack:** Bash, jq, Claude Code PreToolUse hooks

**Spec:** `docs/plans/2026-04-01-hook-guard-refactor.md`

**Critical:** All tasks that create/modify files in `plugin/scripts/` require the workflow phase to be `off`. Each task includes the `/off` and `/implement` commands needed.

---

## File Structure

### New files (in `plugin/scripts/infrastructure/`)

| File | Responsibility |
|------|---------------|
| `deny-messages.sh` | `_phase_deny_message()` + `emit_deny()` (moved from state-io.sh) |
| `hook-preamble.sh` | Shared hook bootstrap: source infra, get phase, debug setup, early exits |
| `read-allowlist.sh` | `_is_allowed_readonly()` — allowlist of safe read-only commands |
| `write-patterns.sh` | `_detect_write_operation()` — write regex + language-specific detection |
| `git-safety.sh` | `_check_git_commit()` + `_is_destructive_git()` |
| `gh-safety.sh` | `_check_gh_command()` — phase-aware GitHub CLI safety |

### Modified files

| File | Change |
|------|--------|
| `plugin/scripts/infrastructure/state-io.sh` | Remove `emit_deny()`, add re-export from deny-messages.sh |
| `plugin/scripts/pre-tool-write-gate.sh` | Rewrite to use preamble + modules (~80 lines) |
| `plugin/scripts/pre-tool-bash-guard.sh` | Rewrite to use preamble + modules (~120 lines) |

---

### Task 1: Create deny-messages.sh

**Files:**
- Create: `plugin/scripts/infrastructure/deny-messages.sh`
- Modify: `plugin/scripts/infrastructure/state-io.sh:79-90`

- [ ] **Step 1: Run `/off` to disable enforcement**

- [ ] **Step 2: Create deny-messages.sh**

```bash
#!/bin/bash
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
```

- [ ] **Step 3: Update state-io.sh — replace emit_deny with re-export**

Replace the `emit_deny` function in `state-io.sh` (lines 79-90) with:

```bash
# emit_deny moved to deny-messages.sh. Re-export for backward compatibility.
SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
if [ -z "${_WFM_DENY_MESSAGES_LOADED:-}" ]; then
    source "$SCRIPT_DIR/deny-messages.sh"
fi
```

- [ ] **Step 4: Test deny-messages.sh loads correctly**

```bash
source plugin/scripts/infrastructure/deny-messages.sh
_WFM_DEBUG_CALLER="test"
emit_deny "test message" 2>/dev/null | jq .hookSpecificOutput.permissionDecision
# Expected: "deny"

_phase_deny_message "define" "write"
# Expected: "BLOCKED: Phase is DEFINE..."

_phase_deny_message "discuss" "guard-system"
# Expected: "BLOCKED: Edits to enforcement files..."
```

- [ ] **Step 5: Commit**

```bash
git add plugin/scripts/infrastructure/deny-messages.sh plugin/scripts/infrastructure/state-io.sh
git commit -m "refactor: extract deny-messages.sh from state-io.sh"
```

- [ ] **Step 6: Run `/implement` to re-enable enforcement**

---

### Task 2: Create hook-preamble.sh

**Files:**
- Create: `plugin/scripts/infrastructure/hook-preamble.sh`

- [ ] **Step 1: Run `/off` to disable enforcement**

- [ ] **Step 2: Create hook-preamble.sh**

```bash
#!/bin/bash
# Shared hook bootstrap — sourced by PreToolUse hooks.
# Sets up: SCRIPT_DIR, PROJECT_ROOT, PHASE, _log(), _show()
# Returns early (return 0) if no enforcement needed (no state file or off phase).
# No include guard — must run fresh each invocation.
#
# Usage: source hook-preamble.sh "caller-name" || exit 0

_PREAMBLE_CALLER="${1:-unknown}"

SCRIPT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}/plugin/scripts"
PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

source "$SCRIPT_DIR/infrastructure/state-io.sh"
source "$SCRIPT_DIR/infrastructure/phase.sh"
source "$SCRIPT_DIR/infrastructure/settings.sh"

# Stub _log before debug-log.sh is sourced
_log() { :; }

# No state file = no enforcement
if [ ! -f "$STATE_FILE" ]; then
    return 0
fi

PHASE=$(get_phase)

# OFF phase: no enforcement
if [ "$PHASE" = "off" ]; then
    return 0
fi

# Debug mode (read after OFF exit to avoid unnecessary jq call)
DEBUG_MODE=$(get_debug)
source "$SCRIPT_DIR/infrastructure/debug-log.sh" "$_PREAMBLE_CALLER"
_log "PHASE=$PHASE"
_log "PROJECT_ROOT=$PROJECT_ROOT"
```

- [ ] **Step 3: Test hook-preamble.sh returns early when off**

```bash
# With phase=off, sourcing should return 0 (no enforcement)
bash -c '
  CLAUDE_PROJECT_DIR="$(git rev-parse --show-toplevel)"
  source "$CLAUDE_PROJECT_DIR/plugin/scripts/infrastructure/hook-preamble.sh" "test" || echo "RETURNED_EARLY"
  echo "PHASE=${PHASE:-unset}"
' 2>/dev/null
# Expected: RETURNED_EARLY and PHASE=unset (or PHASE=off)
```

- [ ] **Step 4: Commit**

```bash
git add plugin/scripts/infrastructure/hook-preamble.sh
git commit -m "refactor: create hook-preamble.sh — shared hook bootstrap"
```

- [ ] **Step 5: Run `/implement` to re-enable enforcement**

---

### Task 3: Create git-safety.sh

**Files:**
- Create: `plugin/scripts/infrastructure/git-safety.sh`

- [ ] **Step 1: Run `/off` to disable enforcement**

- [ ] **Step 2: Create git-safety.sh**

Move `_check_git_commit()` from `pre-tool-bash-guard.sh` (lines 114-149) and the destructive git pattern (line 233) into this module.

```bash
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
```

- [ ] **Step 3: Test git-safety.sh**

```bash
source plugin/scripts/infrastructure/git-safety.sh

# Standalone commit — should return 0
_rc=0; _check_git_commit 'git commit -m "test"' || _rc=$?; echo "standalone: $_rc"
# Expected: standalone: 0

# Chained commit — should return 1
_rc=0; _check_git_commit 'git commit -m "test" && echo pwned' || _rc=$?; echo "chained: $_rc"
# Expected: chained: 1

# Not a commit — should return 2
_rc=0; _check_git_commit 'git log' || _rc=$?; echo "not-commit: $_rc"
# Expected: not-commit: 2

# Destructive git — should return 0
_is_destructive_git 'git reset --hard' && echo "destructive: yes" || echo "destructive: no"
# Expected: destructive: yes

# Safe git — should return 1
_is_destructive_git 'git log' && echo "destructive: yes" || echo "destructive: no"
# Expected: destructive: no
```

- [ ] **Step 4: Commit**

```bash
git add plugin/scripts/infrastructure/git-safety.sh
git commit -m "refactor: extract git-safety.sh — commit parsing and destructive git detection"
```

- [ ] **Step 5: Run `/implement` to re-enable enforcement**

---

### Task 4: Create gh-safety.sh

**Files:**
- Create: `plugin/scripts/infrastructure/gh-safety.sh`

- [ ] **Step 1: Run `/off` to disable enforcement**

- [ ] **Step 2: Create gh-safety.sh**

Move gh command logic from `pre-tool-bash-guard.sh` (lines 256-284) into this module.

```bash
#!/bin/bash
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
        if echo "$cmd" | grep -qE '^[[:space:]]*gh[[:space:]]+(repo[[:space:]]+view|issue[[:space:]]+view|issue[[:space:]]+list|issue[[:space:]]+comment|pr[[:space:]]+view|pr[[:space:]]+list|release[[:space:]]+(view|list))' && \
           _gh_safe_chain "$cmd"; then
            return 0
        fi
    fi

    return 1
}

# Check if a gh command has safe chaining (no shell injection vectors).
_gh_safe_chain() {
    local cmd="$1"
    # Strip harmless "|| true" / "|| echo ..." suffixes before chain check
    local stripped
    stripped=$(echo "$cmd" | sed -E 's/\|\|[[:space:]]*(true|echo[[:space:]][^;&|]*)$//')
    ! echo "$stripped" | grep -qE '(&&|\|\||;)' && \
    ! echo "$cmd" | grep -qE '\|[[:space:]]*(/[^[:space:]]*/)?((env[[:space:]]+(/[^[:space:]]*/)?)?'\
'(bash|sh|zsh|dash|ksh|fish|csh|tcsh))(\b|$)' && \
    ! echo "$cmd" | grep -qE '(/[^[:space:]]*/)?((bash|sh|zsh|dash|ksh|fish|csh|tcsh)|source|\.)[[:space:]]+<\(' && \
    ! echo "$cmd" | grep -qE '\|[[:space:]]*xargs[[:space:]]+(bash|sh|rm|mv|cp|tee|sed)' && \
    ! echo "$cmd" | grep -qE '\|[[:space:]]*(tee|sed|dd|cp|mv|install|python[3]?|node|ruby|perl|awk)\b'
}
```

- [ ] **Step 3: Test gh-safety.sh**

```bash
source plugin/scripts/infrastructure/gh-safety.sh

# Read-only in discuss — should allow
_check_gh_command 'gh issue list' 'discuss' && echo "allow" || echo "deny"
# Expected: allow

# Write in discuss — should deny
_check_gh_command 'gh issue create' 'discuss' && echo "allow" || echo "deny"
# Expected: deny

# Write in complete — should allow
_check_gh_command 'gh issue create --title "test"' 'complete' && echo "allow" || echo "deny"
# Expected: allow

# Chained in complete — should deny
_check_gh_command 'gh issue list && rm -rf /' 'complete' && echo "allow" || echo "deny"
# Expected: deny
```

- [ ] **Step 4: Commit**

```bash
git add plugin/scripts/infrastructure/gh-safety.sh
git commit -m "refactor: extract gh-safety.sh — phase-aware GitHub CLI safety"
```

- [ ] **Step 5: Run `/implement` to re-enable enforcement**

---

### Task 5: Create write-patterns.sh

**Files:**
- Create: `plugin/scripts/infrastructure/write-patterns.sh`

- [ ] **Step 1: Run `/off` to disable enforcement**

- [ ] **Step 2: Create write-patterns.sh**

Move write detection logic from `pre-tool-bash-guard.sh` (lines 27-60, 158-193, 309) into this module.

```bash
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
```

- [ ] **Step 3: Test write-patterns.sh**

```bash
source plugin/scripts/infrastructure/write-patterns.sh

_detect_write_operation 'echo "hello" > file.txt' && echo "write: $DETECTED_WRITE_TYPE" || echo "no write"
# Expected: write: shell-pattern

_detect_write_operation 'cat file.txt' && echo "write: $DETECTED_WRITE_TYPE" || echo "no write"
# Expected: no write

_detect_write_operation 'python3 -c "open(\"f\",\"w\").write(\"x\")"' && echo "write: $DETECTED_WRITE_TYPE" || echo "no write"
# Expected: write: python-write

_extract_write_target 'echo "x" > /tmp/foo.txt'
# Expected: /tmp/foo.txt
```

- [ ] **Step 4: Commit**

```bash
git add plugin/scripts/infrastructure/write-patterns.sh
git commit -m "refactor: extract write-patterns.sh — write detection for COMPLETE denylist"
```

- [ ] **Step 5: Run `/implement` to re-enable enforcement**

---

### Task 6: Create read-allowlist.sh

**Files:**
- Create: `plugin/scripts/infrastructure/read-allowlist.sh`

- [ ] **Step 1: Run `/off` to disable enforcement**

- [ ] **Step 2: Create read-allowlist.sh**

```bash
#!/bin/bash
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
    local cmd="$1"

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
```

- [ ] **Step 3: Test read-allowlist.sh**

```bash
source plugin/scripts/infrastructure/read-allowlist.sh

# Simple reads
_is_allowed_readonly 'cat README.md' && echo "allow" || echo "deny"
# Expected: allow

_is_allowed_readonly 'git log --oneline' && echo "allow" || echo "deny"
# Expected: allow

_is_allowed_readonly 'jq .phase .claude/state/workflow.json' && echo "allow" || echo "deny"
# Expected: allow

# Writes should be denied — redirect detection catches allowed commands writing to files
_is_allowed_readonly 'echo "x" > file' && echo "allow" || echo "deny"
# Expected: deny (echo is allowed but _has_file_redirect catches the >)

# Chained: all segments must be allowed
_is_allowed_readonly 'cat file && wc -l' && echo "allow" || echo "deny"
# Expected: allow

_is_allowed_readonly 'cat file && rm -rf /' && echo "allow" || echo "deny"
# Expected: deny

# Pipe to writer should be denied (pipe is split)
_is_allowed_readonly 'cat file | tee output.txt' && echo "allow" || echo "deny"
# Expected: deny (tee is not on allowlist)

# sed -i should be denied
_is_allowed_readonly 'sed -i "s/old/new/" file.txt' && echo "allow" || echo "deny"
# Expected: deny

# sed without -i should be allowed
_is_allowed_readonly 'sed "s/old/new/" file.txt' && echo "allow" || echo "deny"
# Expected: allow

# git commit should be allowed (goes through git-safety.sh first in practice)
_is_allowed_readonly 'git add file && git commit -m "msg"' && echo "allow" || echo "deny"
# Expected: allow
```

- [ ] **Step 4: Commit**

```bash
git add plugin/scripts/infrastructure/read-allowlist.sh
git commit -m "feat: create read-allowlist.sh — allowlist for DEFINE/DISCUSS enforcement"
```

- [ ] **Step 5: Run `/implement` to re-enable enforcement**

---

### Task 7: Rewrite pre-tool-write-gate.sh

**Files:**
- Modify: `plugin/scripts/pre-tool-write-gate.sh`

- [ ] **Step 1: Run `/off` to disable enforcement**

- [ ] **Step 2: Rewrite pre-tool-write-gate.sh**

Replace the entire file with:

```bash
#!/bin/bash
# Copyright (C) 2026 azevedo-home-lab
# SPDX-License-Identifier: GPL-3.0-only
#
# This file is part of Claude Code Workflows.
# See LICENSE for details.

# Workflow Manager: blocks Write/Edit/MultiEdit/NotebookEdit in DEFINE, DISCUSS, and COMPLETE phases
# Matcher: Write|Edit|MultiEdit|NotebookEdit
#
# Whitelist tiers:
#   Restrictive (DEFINE/DISCUSS/ERROR): .claude/state/, docs/plans/, docs/specs/
#   Docs-allowed (COMPLETE):            .claude/state/, docs/ (all), *.md at project root

set -euo pipefail

# --- Preamble: shared hook bootstrap ---
SCRIPT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}/plugin/scripts"
source "$SCRIPT_DIR/infrastructure/hook-preamble.sh" "workflow-gate" || exit 0

source "$SCRIPT_DIR/infrastructure/deny-messages.sh"

# --- Parse file path ---
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null) || FILE_PATH=""
_log "FILE_PATH=$FILE_PATH"

# --- Path traversal check ---
_canonicalize() {
    realpath "$1" 2>/dev/null || \
    python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$1" 2>/dev/null || \
    echo ""
}

if [ -n "$FILE_PATH" ]; then
    CANONICAL_PATH=$(_canonicalize "$FILE_PATH")
    CANONICAL_ROOT=$(_canonicalize "$PROJECT_ROOT")
    _log "CANONICAL_PATH=$CANONICAL_PATH CANONICAL_ROOT=$CANONICAL_ROOT"

    if [ -n "$CANONICAL_PATH" ] && [ -n "$CANONICAL_ROOT" ]; then
        if [ "${CANONICAL_PATH#"$CANONICAL_ROOT"/}" = "$CANONICAL_PATH" ]; then
            FILE_PATH=""
            _log "FILE_PATH emptied: traversal check failed"
        fi
    else
        if echo "$FILE_PATH" | grep -qE '\.\.'; then
            FILE_PATH=""
            _log "FILE_PATH emptied: dotdot check (no realpath or python3)"
        fi
    fi
fi

# Normalize: strip project root prefix
NORMALIZED_PATH="$FILE_PATH"
[ -n "$PROJECT_ROOT" ] && NORMALIZED_PATH="${FILE_PATH#"$PROJECT_ROOT"/}"
_log "NORMALIZED_PATH=$NORMALIZED_PATH"

# --- Guard-system self-protection (ALL phases) ---
GUARD_SYSTEM_PATTERN='(\.claude/hooks/|(^|[^a-z-])plugin/scripts/|(^|[^a-z-])plugin/commands/)'
if [ -n "$NORMALIZED_PATH" ] && echo "$NORMALIZED_PATH" | grep -qE "$GUARD_SYSTEM_PATTERN"; then
    _log "DENY: guard-system match on '$NORMALIZED_PATH'"
    emit_deny "$(_phase_deny_message "$PHASE" "guard-system")"
    exit 0
fi

# --- implement/review: allow everything ---
case "$PHASE" in
    implement|review) _log "ALLOW: phase=$PHASE"; exit 0 ;;
esac

# --- Phase-gate: whitelist check ---
case "$PHASE" in
    define|discuss|error) WHITELIST="$RESTRICTED_WRITE_WHITELIST" ;;
    complete)             WHITELIST="$COMPLETE_WRITE_WHITELIST" ;;
    *)                    exit 0 ;;
esac

_log "WHITELIST=$WHITELIST"
if [ -n "$NORMALIZED_PATH" ] && echo "$NORMALIZED_PATH" | grep -qE "$WHITELIST"; then
    _log "ALLOW: whitelist match on '$NORMALIZED_PATH'"
    exit 0
fi

# --- Deny ---
_log "DENY: phase=$PHASE path=$NORMALIZED_PATH"
emit_deny "$(_phase_deny_message "$PHASE" "write")"
exit 0
```

- [ ] **Step 3: Test write-gate in off phase (should allow everything)**

```bash
echo '{"tool_input":{"file_path":"src/main.py"}}' | CLAUDE_PROJECT_DIR="$(git rev-parse --show-toplevel)" .claude/hooks/pre-tool-write-gate.sh
# Expected: no output (allowed)
```

- [ ] **Step 4: Commit**

```bash
git add plugin/scripts/pre-tool-write-gate.sh
git commit -m "refactor: rewrite pre-tool-write-gate.sh with shared modules"
```

- [ ] **Step 5: Run `/implement` to re-enable enforcement**

---

### Task 8: Rewrite pre-tool-bash-guard.sh

**Files:**
- Modify: `plugin/scripts/pre-tool-bash-guard.sh`

- [ ] **Step 1: Run `/off` to disable enforcement**

- [ ] **Step 2: Rewrite pre-tool-bash-guard.sh**

Replace the entire file. This is the largest task — the new version uses allowlist for DEFINE/DISCUSS/ERROR and denylist for COMPLETE.

```bash
#!/bin/bash
# Copyright (C) 2026 azevedo-home-lab
# SPDX-License-Identifier: GPL-3.0-only
#
# This file is part of Claude Code Workflows.
# See LICENSE for details.

# Workflow Manager: blocks Bash write operations based on phase
# Matcher: Bash
#
# DEFINE/DISCUSS/ERROR: allowlist — only known read-only commands pass
# COMPLETE: denylist — known write operations blocked, rest passes
# IMPLEMENT/REVIEW: everything allowed (except guard-system and destructive git)

set -euo pipefail

# --- Preamble: shared hook bootstrap ---
SCRIPT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}/plugin/scripts"
source "$SCRIPT_DIR/infrastructure/hook-preamble.sh" "bash-write-guard" || exit 0

source "$SCRIPT_DIR/infrastructure/deny-messages.sh"
source "$SCRIPT_DIR/infrastructure/git-safety.sh"
source "$SCRIPT_DIR/infrastructure/gh-safety.sh"
source "$SCRIPT_DIR/infrastructure/write-patterns.sh"
source "$SCRIPT_DIR/infrastructure/read-allowlist.sh"

# --- Parse command ---
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null) || COMMAND=""

if [ -z "$COMMAND" ]; then
    emit_deny "BLOCKED: Could not parse Bash command in $PHASE phase. Fail-closed for security."
    exit 0
fi

# --- Allow workflow state commands (sole command, no chaining) ---
if echo "$COMMAND" | grep -qE '^[[:space:]]*(source[[:space:]]|\.[ /]).*workflow-(state|facade)\.sh'; then
    if ! echo "$COMMAND" | grep -qE '(&&|\|\||;|\|)'; then
        _log "ALLOW: workflow state command"
        exit 0
    fi
fi

if echo "$COMMAND" | grep -qE '(^|[[:space:]/])workflow-cmd\.sh[[:space:]]'; then
    if ! echo "$COMMAND" | grep -qE '(&&|\|\||;|\|)'; then
        _log "ALLOW: workflow-cmd.sh call"
        exit 0
    fi
fi

# --- Git commit check ---
_git_rc=0; _check_git_commit "$COMMAND" || _git_rc=$?
case $_git_rc in
    0) _log "ALLOW: git commit"; exit 0 ;;
    1) emit_deny "$(_phase_deny_message "$PHASE" "chained-commit")"; exit 0 ;;
    2) ;;  # not a commit, continue
esac

# --- Strip safe redirects for write detection ---
CLEAN_CMD=$(echo "$COMMAND" | sed -E 's/[0-9]+>\/dev\/null//g; s/[0-9]*>&[0-9]+//g; s/>>[[:space:]]*\/dev\/null//g; s/>[[:space:]]*\/dev\/null//g')

# --- Destructive git (ALL phases including implement/review) ---
if _is_destructive_git "$COMMAND"; then
    _log "DENY: destructive git"
    emit_deny "$(_phase_deny_message "$PHASE" "destructive-git")"
    exit 0
fi

# --- State file write protection (ALL phases) ---
STATE_FILE_PATTERN='\.claude/(state/workflow\.json|state/phase-intent\.json)'
if echo "$COMMAND" | grep -qE "$STATE_FILE_PATTERN"; then
    if _detect_write_operation "$COMMAND"; then
        _log "DENY: write to state file"
        emit_deny "$(_phase_deny_message "$PHASE" "state-file")"
        exit 0
    fi
fi

# --- user-set-phase.sh execution block (ALL phases) ---
if echo "$COMMAND" | grep -qE '(^|[;&|[:space:]])(\\./|source[[:space:]]|bash[[:space:]]|sh[[:space:]]|/)[^[:space:]]*user-set-phase\.sh'; then
    _log "DENY: user-set-phase.sh via Bash"
    emit_deny "$(_phase_deny_message "$PHASE" "user-set-phase")"
    exit 0
fi

# --- Guard-system write protection (ALL phases including implement/review) ---
GUARD_SYSTEM_PATTERN='(\.claude/hooks/|plugin/scripts/|plugin/commands/)'
if echo "$COMMAND" | grep -qE "$GUARD_SYSTEM_PATTERN"; then
    if _detect_write_operation "$COMMAND"; then
        _log "DENY: write to enforcement file"
        emit_deny "$(_phase_deny_message "$PHASE" "guard-system")"
        exit 0
    fi
fi

# --- implement/review: allow everything else ---
case "$PHASE" in
    implement|review) _log "ALLOW: phase=$PHASE"; exit 0 ;;
esac

# --- Phase gate ---
case "$PHASE" in
    # DEFINE/DISCUSS/ERROR: allowlist enforcement
    define|discuss|error)
        # gh commands get special handling
        if echo "$COMMAND" | grep -qE '^[[:space:]]*(gh)[[:space:]]'; then
            if _check_gh_command "$COMMAND" "$PHASE"; then
                _log "ALLOW: gh read-only in $PHASE"
                exit 0
            fi
        fi

        # Check against read-only allowlist
        if _is_allowed_readonly "$COMMAND"; then
            _log "ALLOW: allowlist match"
            exit 0
        fi

        # Check write target against phase whitelist (for allowed writes like docs/plans/)
        if _detect_write_operation "$COMMAND"; then
            local write_target
            write_target=$(_extract_write_target "$COMMAND")
            if [ -n "$write_target" ] && echo "$write_target" | grep -qE "$RESTRICTED_WRITE_WHITELIST"; then
                _log "ALLOW: write target whitelisted ($write_target)"
                exit 0
            fi
        fi

        _log "DENY: not on allowlist in $PHASE"
        emit_deny "$(_phase_deny_message "$PHASE" "bash-write")"
        exit 0
        ;;

    # COMPLETE: denylist enforcement
    complete)
        # gh commands — all allowed in COMPLETE if safe chain
        if echo "$COMMAND" | grep -qE '^[[:space:]]*(gh)[[:space:]]'; then
            if _check_gh_command "$COMMAND" "$PHASE"; then
                _log "ALLOW: gh in COMPLETE"
                exit 0
            fi
        fi

        # rm .claude/tmp/ cleanup
        local _rm_stripped
        _rm_stripped=$(echo "$COMMAND" | sed -E 's/\|\|[[:space:]]*(true|echo[[:space:]][^;&|]*)$//')
        if echo "$_rm_stripped" | grep -qE '^[[:space:]]*rm[[:space:]]' && \
           echo "$_rm_stripped" | grep -qE '\.claude/tmp/' && \
           ! echo "$_rm_stripped" | grep -qE '\.\.' && \
           ! echo "$_rm_stripped" | grep -qE '(&&|\|\||;|\|)'; then
            _log "ALLOW: rm .claude/tmp/ in COMPLETE"
            exit 0
        fi

        # Write detection
        if _detect_write_operation "$COMMAND"; then
            local write_target
            write_target=$(_extract_write_target "$COMMAND")
            if [ -n "$write_target" ] && echo "$write_target" | grep -qE "$COMPLETE_WRITE_WHITELIST"; then
                _log "ALLOW: write target whitelisted ($write_target)"
                exit 0
            fi
            _log "DENY: write detected in COMPLETE ($DETECTED_WRITE_TYPE)"
            emit_deny "$(_phase_deny_message "$PHASE" "bash-write")"
            exit 0
        fi

        # No write detected — read-only command, allow
        _log "ALLOW: no write pattern in COMPLETE"
        exit 0
        ;;

    *)
        exit 0
        ;;
esac
```

- [ ] **Step 3: Test bash-guard in off phase**

```bash
echo '{"tool_input":{"command":"rm -rf /"}}' | CLAUDE_PROJECT_DIR="$(git rev-parse --show-toplevel)" .claude/hooks/pre-tool-bash-guard.sh
# Expected: no output (off phase, no enforcement)
```

- [ ] **Step 4: Commit**

```bash
git add plugin/scripts/pre-tool-bash-guard.sh
git commit -m "refactor: rewrite pre-tool-bash-guard.sh with allowlist/denylist hybrid"
```

- [ ] **Step 5: Run `/implement` to re-enable enforcement**

---

### Task 9: Integration testing

Run manual verification in each phase to confirm the refactored hooks work correctly.

- [ ] **Step 1: Test DEFINE phase (allowlist)**

Run `/define`, then verify:
```bash
# Should ALLOW:
cat README.md
git log --oneline -5
jq .phase .claude/state/workflow.json
ls plugin/scripts/

# Should BLOCK:
echo "test" > /tmp/testfile
sed -i 's/old/new/' README.md
cp file1 file2
```

- [ ] **Step 2: Test IMPLEMENT phase (everything allowed except guard-system)**

Run `/implement`, then verify:
```bash
# Should ALLOW:
echo "test" > /tmp/testfile
cat /tmp/testfile

# Should BLOCK (guard-system):
# Try Edit on plugin/scripts/setup.sh — should be blocked by write-gate
```

- [ ] **Step 3: Test guard-system in implement**

Verify that Write/Edit to `plugin/scripts/` is blocked even in implement phase.

- [ ] **Step 4: Test destructive git blocking**

```bash
# Should BLOCK in any phase:
git reset --hard HEAD
git push --force
```

- [ ] **Step 5: Run `/off` to end testing**

- [ ] **Step 6: Commit any fixes found during testing**

---

### Task 10: Cleanup and version bump

- [ ] **Step 1: Run `/off` to disable enforcement**

- [ ] **Step 2: Delete `plugin/scripts/l1/phase-entry.sh`** (no longer called — L1 now fires at transition time)

- [ ] **Step 3: Update version in plugin.json files**

Bump patch version in both:
- `plugin/.claude-plugin/plugin.json`
- `.claude-plugin/plugin.json`

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "refactor!: v2.1.0 — hook guard refactor with allowlist enforcement

BREAKING: DEFINE/DISCUSS phases now use allowlist (deny-by-default) instead
of denylist for Bash commands. Unknown commands are blocked.

- Extract 6 focused modules from monolithic hooks
- Shared hook-preamble.sh eliminates 60% code duplication
- deny-messages.sh centralizes all phase-aware deny messages
- read-allowlist.sh: explicit safe-command list for DEFINE/DISCUSS
- write-patterns.sh: write detection for COMPLETE denylist
- git-safety.sh: commit parsing + destructive git detection
- gh-safety.sh: phase-aware GitHub CLI validation
- Guard-system check now fires before implement/review exit in bash-guard
- L1 coaching fires at transition time, not deferred to next tool call"
```

- [ ] **Step 5: Run `/implement` to re-enable enforcement**
