# Hook Guard Refactor Spec

## Problem

`pre-tool-write-gate.sh` (142 lines) and `pre-tool-bash-guard.sh` (345 lines) share ~60% structural overlap, bash-guard handles 8+ responsibilities in a single file, write detection uses a denylist regex arms race, and deny messages are duplicated.

## Decision

Refactor both hooks into focused modules with shared infrastructure. Apply hybrid enforcement: allowlist for DEFINE/DISCUSS (strict), denylist for COMPLETE (permissive). During implementation, use `/off` to edit enforcement files.

## Architecture

```
plugin/scripts/
├── infrastructure/
│   ├── hook-preamble.sh      # NEW — shared hook bootstrap
│   ├── write-patterns.sh     # NEW — write detection regex + language-specific detection
│   ├── git-safety.sh         # NEW — git commit parsing + destructive git blocking
│   ├── gh-safety.sh          # NEW — GitHub CLI safety checks by phase
│   ├── read-allowlist.sh     # NEW — allowlist of safe read-only command prefixes
│   ├── deny-messages.sh      # NEW — shared phase-aware deny message function
│   ├── state-io.sh           # existing (unchanged)
│   ├── phase.sh              # existing (unchanged)
│   ├── settings.sh           # existing (unchanged)
│   └── debug-log.sh          # existing (unchanged)
├── pre-tool-write-gate.sh    # SIMPLIFIED — ~80 lines
└── pre-tool-bash-guard.sh    # SIMPLIFIED — ~120 lines
```

## Module Contracts

### hook-preamble.sh

Sourced by both hooks. Handles: SCRIPT_DIR resolution, source infrastructure (state-io, phase, settings), stub `_log`, state file existence check (return 0 if missing), phase read, off-phase exit (return 0), debug mode read, source debug-log.sh.

After sourcing, caller has: `$PHASE`, `$SCRIPT_DIR`, `$STATE_FILE`, `_log()`, `_show()`, `$PROJECT_ROOT`.

Uses `return` not `exit` since it's sourced. Callers wrap in: `source hook-preamble.sh "caller-name" || exit 0`.

### read-allowlist.sh

Exports `_is_allowed_readonly()`. Takes a command string. Returns 0 if allowed, 1 if not.

Uses a case statement with glob patterns for readability. Categories:

- **Core reads:** cat, head, tail, less, more, wc, file, stat, du, df
- **Search:** find, grep, rg, ag, ack, locate, which, whereis, type, command
- **Git reads:** git log, git diff, git status, git show, git branch, git remote, git rev-parse, git ls-files, git blame, git tag, git stash list
- **JSON/data:** jq, yq, xmllint, csvtool
- **Text processing:** sort, uniq, cut, tr, awk, sed (without -i), column, fmt, fold, diff, comm
- **System info:** echo, printf, date, env, printenv, uname, hostname, pwd, id, whoami
- **Directory:** ls, tree, exa, fd
- **Network reads:** curl (without -o), wget (without -O), ping, dig, nslookup, host
- **Dev tools:** npm list, pip list, cargo --version, rustc --version
- **Workflow:** workflow-cmd.sh, workflow-facade.sh, source commands

Does NOT handle git commits (handled separately by git-safety.sh before allowlist check) or whitelisted write targets (handled by caller after allowlist denial).

### write-patterns.sh

Exports `_detect_write_operation()`. Takes a command string. Returns 0 if write detected, 1 if not. Sets `DETECTED_WRITE_TYPE` variable for logging.

Consolidates: WRITE_PATTERN regex fragments, safe-redirect stripping (2>/dev/null etc.), Python/Node/Ruby/Perl write detection. Used only in COMPLETE phase denylist path.

### git-safety.sh

Exports:
- `_check_git_commit()` — existing logic cleaned up. Returns 0 (allow standalone commit), 1 (deny chained commit), 2 (not a commit).
- `_is_destructive_git()` — returns 0 if destructive git op detected. Checks: reset --hard, push --force, branch -D, checkout --, clean -f, rebase --abort.

### gh-safety.sh

Exports `_check_gh_command()`. Takes command + phase. Returns 0 (allow), 1 (deny).

Logic:
- COMPLETE: all gh ops allowed if safe chain (no shell chaining to writers)
- DEFINE/DISCUSS: read-only gh ops only (view, list, comment) + safe chain check
- Encapsulates the `_gh_safe_chain()` helper

### deny-messages.sh

Exports `_phase_deny_message()`. Takes phase + context string. Returns the deny reason.

Contexts: "write" (for write-gate), "bash-write" (for bash-guard write detection), "guard-system" (for enforcement file protection), "state-file" (for workflow state protection).

## Data Flow

### pre-tool-write-gate.sh

```
1. source hook-preamble.sh "workflow-gate" || exit 0
2. Parse INPUT, extract FILE_PATH
3. Path traversal check (_canonicalize)
4. Guard-system self-protection check
5. implement/review → exit 0
6. Select whitelist by phase
7. Check FILE_PATH against whitelist → exit 0 if match
8. _phase_deny_message → emit_deny
```

### pre-tool-bash-guard.sh

```
1. source hook-preamble.sh "bash-write-guard" || exit 0
2. Parse INPUT, extract COMMAND
3. Allow workflow-cmd.sh / workflow-facade.sh (sole command check)
4. _check_git_commit → allow/deny/continue
5. _is_destructive_git → deny if match (ALL phases including implement/review)
6. Guard-system write check (ALL phases)
7. State file write check (ALL phases)
8. user-set-phase.sh execution block
9. implement/review → exit 0
10. Phase gate:
    - DEFINE/DISCUSS: _is_allowed_readonly → allow if match
                      Check write target against whitelist → allow if match
                      _phase_deny_message → emit_deny
    - COMPLETE:       gh-safety check → allow/deny
                      rm .claude/tmp/ check → allow
                      _detect_write_operation → deny if match
                      Allow (read-only)
```

## Behavioral Changes

1. **DEFINE/DISCUSS gets stricter** — currently, any Bash command that doesn't match the write regex passes. After refactor, only explicitly allowed read commands pass. Unknown commands are denied.
2. **No other behavioral changes** — COMPLETE phase, implement/review phases, guard-system protection, destructive git blocking all work identically.

## Testing Strategy

Since there are no automated tests for hooks, verification is manual:
- `/define` → verify read commands work (git log, cat, ls, jq, grep)
- `/define` → verify write commands blocked (echo > file, sed -i, cp, mv)
- `/define` → verify git commit to docs/plans/ still works
- `/discuss` → same as define
- `/implement` → verify everything works (reads + writes)
- `/complete` → verify docs writes allowed, code writes blocked
- Verify guard-system blocks in all phases
- Verify destructive git blocked in all phases

## Implementation Notes

- Use `/off` when editing enforcement files (plugin/scripts/, plugin/commands/)
- All new modules get include guards (`_WFM_*_LOADED`)
- hook-preamble.sh must use `return` not `exit` (sourced context)
- Allowlist uses case/glob not regex (readability)
- Existing infrastructure modules (state-io, phase, settings, debug-log) unchanged
