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
