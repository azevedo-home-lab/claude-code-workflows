# Hook Guard Refactor Spec

## Problem

`pre-tool-write-gate.sh` (142 lines) and `pre-tool-bash-guard.sh` (345 lines) share ~60% structural overlap, bash-guard handles 8+ responsibilities in a single file, write detection uses a denylist regex arms race, and deny messages are duplicated.

## Alternatives Considered

1. **Merge into one hook** — rejected because Write/Edit and Bash have fundamentally different detection strategies (file path matching vs command analysis). A single hook would be even larger.
2. **External config file for allow/denylists** — rejected as over-engineering. Shell arrays/case statements are simpler to maintain and don't require a parser. Config adds a failure mode (missing/corrupt config) without clear benefit.
3. **Pure allowlist everywhere** — rejected for COMPLETE phase because it needs broad command support (gh create, rm cleanup, doc writes) that would require a very large allowlist. Denylist is more practical there.

## Decision

Refactor both hooks into focused modules with shared infrastructure. Apply hybrid enforcement: allowlist for DEFINE/DISCUSS (strict), denylist for COMPLETE (permissive). During implementation, use `/off` to edit enforcement files.

**Why hybrid:** The allowlist closes the regex arms race for DEFINE/DISCUSS — instead of chasing every possible write vector, unknown commands are denied by default. COMPLETE retains the denylist because its permitted operations (gh issue create, doc writes, rm cleanup) are too varied for a clean allowlist.

## Architecture

```
plugin/scripts/
├── infrastructure/
│   ├── hook-preamble.sh      # NEW — shared hook bootstrap
│   ├── write-patterns.sh     # NEW — write detection regex + language-specific detection
│   ├── git-safety.sh         # NEW — git commit parsing + destructive git blocking
│   ├── gh-safety.sh          # NEW — GitHub CLI safety checks by phase
│   ├── read-allowlist.sh     # NEW — allowlist of safe read-only command prefixes
│   ├── deny-messages.sh      # NEW — shared phase-aware deny message function + emit_deny
│   ├── state-io.sh           # existing (unchanged)
│   ├── phase.sh              # existing (unchanged)
│   ├── settings.sh           # existing (unchanged)
│   └── debug-log.sh          # existing (unchanged)
├── pre-tool-write-gate.sh    # SIMPLIFIED — ~80 lines
└── pre-tool-bash-guard.sh    # SIMPLIFIED — ~120 lines
```

### Source Order (dependency graph)

```
state-io.sh          ← no deps (base)
phase.sh             ← state-io
settings.sh          ← state-io
debug-log.sh         ← no deps (configured by caller via DEBUG_MODE)
deny-messages.sh     ← no deps (emit_deny is self-contained; state-io re-exports for compat)
hook-preamble.sh     ← state-io, phase, settings, debug-log
read-allowlist.sh    ← no deps (pure function)
write-patterns.sh    ← no deps (pure function)
git-safety.sh        ← no deps (pure function)
gh-safety.sh         ← no deps (pure function, caller passes phase)
```

## Module Contracts

### hook-preamble.sh

Sourced by both hooks. Handles: SCRIPT_DIR resolution, source infrastructure (state-io, phase, settings), stub `_log`, state file existence check (return 0 if missing), phase read, off-phase exit (return 0), debug mode read, source debug-log.sh.

After sourcing, caller has: `$PHASE`, `$SCRIPT_DIR`, `$STATE_FILE`, `_log()`, `_show()`, `$PROJECT_ROOT`.

`PROJECT_ROOT` is derived as: `${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}`.

Uses `return` not `exit` since it's sourced. Callers wrap in: `source hook-preamble.sh "caller-name" || exit 0`. No include guard — it must run fresh each invocation (reads phase state on every call).

### read-allowlist.sh

Exports `_is_allowed_readonly()`. Takes a command string. Returns 0 if allowed, 1 if not.

Extracts the first command word (handles leading whitespace and path prefixes like `/usr/bin/`). Uses a case statement with glob patterns for readability.

Categories:

- **Core reads:** cat, head, tail, less, more, wc, file, stat, du, df
- **Search:** find, grep, rg, ag, ack, locate, which, whereis, type, command
- **Git reads:** git log, git diff, git status, git show, git branch, git remote, git rev-parse, git ls-files, git blame, git tag, git stash list
- **JSON/data:** jq, yq, xmllint, csvtool
- **Text processing:** sort, uniq, cut, tr, awk, sed (without -i), column, fmt, fold, diff, comm
- **System info:** echo, printf, date, env, printenv, uname, hostname, pwd, id, whoami
- **Directory:** ls, tree, exa, fd
- **Network reads:** curl (without -o), wget (without -O), ping, dig, nslookup, host
- **Dev tools:** npm list, pip list, cargo --version, rustc --version, node -e (without fs writes), python3 -c (without file writes)
- **Path utilities:** basename, dirname, realpath, readlink, test, [, [[
- **Shell builtins:** true, false, :, source, .
- **Build tools (dry-run):** make -n, make --dry-run, cargo check, cargo clippy, npm test, npm run lint
- **Container reads:** docker ps, docker images, docker inspect, docker logs
- **Workflow:** workflow-cmd.sh, workflow-facade.sh

**Chain handling:** For chained commands (`cmd1 && cmd2`), each segment is checked independently. If any segment is not on the allowlist, the entire command is denied.

Does NOT handle git commits (handled separately by git-safety.sh before allowlist check) or whitelisted write targets (handled by caller after allowlist denial).

### write-patterns.sh

Exports `_detect_write_operation()`. Takes a command string. Returns 0 if write detected, 1 if not. Sets `DETECTED_WRITE_TYPE` variable for logging.

Consolidates: WRITE_PATTERN regex fragments, safe-redirect stripping (2>/dev/null, 2>&1, etc.), Python/Node/Ruby/Perl write detection. Used only in COMPLETE phase denylist path.

### git-safety.sh

Exports:
- `_check_git_commit()` — existing logic cleaned up. Returns 0 (allow standalone commit), 1 (deny chained commit), 2 (not a commit). **Note:** callers under `set -e` must capture the return code via `_rc=0; _check_git_commit "$CMD" || _rc=$?` to prevent premature exit.
- `_is_destructive_git()` — returns 0 if destructive git op detected. Checks: reset --hard, push --force, branch -D, checkout --, clean -f, rebase --abort.

### gh-safety.sh

Exports `_check_gh_command()`. Takes command + phase. Returns 0 (allow), 1 (deny).

Logic:
- COMPLETE: all gh ops allowed if safe chain (no shell chaining to writers)
- DEFINE/DISCUSS/ERROR: read-only gh ops only (view, list, comment) + safe chain check
- Encapsulates the `_gh_safe_chain()` helper

### deny-messages.sh

Exports `_phase_deny_message()` and `emit_deny()` (moved from state-io.sh).

`_phase_deny_message()` takes phase + context string. Returns the deny reason string.

Contexts: "write" (for write-gate), "bash-write" (for bash-guard write detection), "guard-system" (for enforcement file protection), "state-file" (for workflow state protection).

`emit_deny()` takes a reason string. Outputs PreToolUse deny JSON response. Same implementation as current state-io.sh, relocated here for cohesion.

## Data Flow

### pre-tool-write-gate.sh

```
1. source hook-preamble.sh "workflow-gate" || exit 0
2. Parse INPUT, extract FILE_PATH
3. Path traversal check (_canonicalize)
4. Guard-system self-protection check → deny if match (ALL phases)
5. implement/review → exit 0
6. Select whitelist by phase (define/discuss/error → restricted, complete → docs-allowed)
7. Check FILE_PATH against whitelist → exit 0 if match
8. _phase_deny_message → emit_deny
```

### pre-tool-bash-guard.sh

```
1. source hook-preamble.sh "bash-write-guard" || exit 0
2. Parse INPUT, extract COMMAND (fail-closed if empty)
3. Allow workflow-cmd.sh / workflow-facade.sh (sole command, no chaining)
4. _check_git_commit → allow/deny/continue
5. Strip safe redirects (2>/dev/null etc.) → CLEAN_CMD
6. _is_destructive_git → deny if match (ALL phases including implement/review)
7. State file write check — deny if write operation targets workflow.json (ALL phases)
8. user-set-phase.sh execution block — deny if called via Bash tool (ALL phases)
9. Guard-system write check — deny if write operation targets enforcement files (ALL phases)
   NOTE: This is a behavioral change from current code where bash guard-system
   check fires AFTER implement/review exit. The spec intentionally tightens this
   to match write-gate behavior. See Behavioral Changes #2.
10. implement/review → exit 0
11. Phase gate:
    - DEFINE/DISCUSS/ERROR: _is_allowed_readonly → allow if match
                            Check write target against whitelist → allow if match
                            _phase_deny_message → emit_deny
    - COMPLETE:            _check_gh_command → allow/deny
                            rm .claude/tmp/ check → allow
                            _detect_write_operation → deny if match, then whitelist check
                            Allow (no write pattern detected = read-only)
```

## Behavioral Changes

1. **DEFINE/DISCUSS/ERROR gets stricter** — currently, any Bash command that doesn't match the write regex passes. After refactor, only explicitly allowed read commands pass. Unknown commands are denied. This closes the regex arms race but means novel read-only commands (not on the allowlist) will be blocked until added.
2. **Guard-system check tightened in bash-guard** — currently, the bash guard-system path check fires after the implement/review early exit, meaning implement/review phases bypass it. The refactor moves it before the implement/review exit to match write-gate behavior. This means Claude cannot write to enforcement files via Bash even in implement/review phases. This is intentional — the user uses `/off` or `!backtick` for legitimate enforcement file edits.
3. **`emit_deny` relocates** — moves from `state-io.sh` to `deny-messages.sh`. `state-io.sh` keeps a re-export for backward compatibility during transition; removed after all callers are updated.
4. **No other behavioral changes** — COMPLETE phase denylist, implement/review freedom (minus guard-system), whitelists, destructive git blocking all work identically.

## Testing Strategy

Since there are no automated tests for hooks, verification is manual:

**Allowlist boundary (DEFINE/DISCUSS):**
- Verify allowed: `git log`, `cat`, `ls`, `jq .`, `grep pattern`, `wc -l`, `diff`, `basename`, `make -n`, `docker ps`
- Verify blocked: `echo > file`, `sed -i`, `cp`, `mv`, `rm`, `touch`, `tee`, `python3 -c "open('f','w')"`
- Verify git commit to docs/plans/ still works
- Verify chained commands: `cat file && echo done` → blocked (echo could write), `cat file && wc -l` → allowed

**COMPLETE phase (denylist):**
- Verify docs writes allowed
- Verify code writes blocked
- Verify `gh issue create` allowed
- Verify `rm .claude/tmp/` allowed
- Verify Python/Node/Ruby/Perl write detection works

**Guard-system (ALL phases including implement/review):**
- Verify Write/Edit to plugin/scripts/ blocked in implement
- Verify Bash write to plugin/scripts/ blocked in implement
- Verify destructive git blocked in all phases

**Error phase:**
- Verify error phase uses same allowlist as define/discuss
- Verify gh read-only allowed, gh write blocked

**Edge cases:**
- Path traversal in write-gate (`../../../etc/passwd`)
- user-set-phase.sh called via Bash tool → blocked
- Empty command → fail-closed deny

## Implementation Notes

- Use `/off` when editing enforcement files (plugin/scripts/, plugin/commands/)
- All new modules except hook-preamble.sh get include guards (`_WFM_*_LOADED`)
- hook-preamble.sh has no include guard — it reads fresh state on every invocation
- Allowlist uses case/glob not regex (readability and maintenance)
- Existing infrastructure modules (state-io, phase, settings, debug-log) unchanged except emit_deny re-export
- `_check_git_commit` callers must use `_rc=0; func || _rc=$?` pattern under `set -e`
- Rollback: `git revert <commit>` while in `/off` mode restores previous hooks immediately
- Incremental implementation: extract shared modules first (preamble, deny-messages), then refactor write-gate (smaller), then refactor bash-guard (larger). Each step can be committed and tested independently.
