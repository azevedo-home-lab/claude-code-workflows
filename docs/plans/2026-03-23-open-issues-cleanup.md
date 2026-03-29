# Open Issues Cleanup & Tracked Observations Feature

**Date:** 2026-03-23
**Status:** Design
**Supersedes:** Observation #3416 (consolidated open issues list)

## Problem

The Workflow Manager has accumulated 12 open issues and tech debt items since the plugin conversion, plus a new feature (#13 — tracked observations lifecycle) that was partially implemented without proper safety design. The issues range from bash compatibility bugs to missing test coverage to COMPLETE pipeline gaps that allow invalid implementations to pass validation.

### Specific Problems

1. **No safe lifecycle for tracked observations** — The `tracked_observations` array in workflow.json has CRUD functions but no safe cleanup mechanism in the COMPLETE pipeline. Removing items in Step 7 and adding in Step 8 is a race condition — session crash between steps loses data.

2. **COMPLETE validation is confirmatory only** — Validation agents check "was the plan executed?" but never test edge cases the plan didn't specify, and never try to break the implementation adversarially.

3. **COMPLETE loop-back is destructive** — If validation finds a code fix is needed, jumping to `/implement` resets all completion milestones, requiring the entire pipeline to re-run.

4. **Bash 3.2 incompatibility** — 6 uses of `${PHASE^^}` in post-tool-navigator.sh fail with "bad substitution" on macOS default bash.

5. **Code quality debt** — Duplicated COMMAND extraction (4x), unreadable WRITE_PATTERN regex, 7 separate jq process spawns in statusline, exposed private helpers in workflow-cmd.sh.

6. **Missing test coverage** — No functional tests for setup.sh, no version detection tests, no tracked observations lifecycle tests.

7. **Stale documentation** — statusline-guide.md references removed file paths.

## Design

### Phase 1: Foundation Fixes

#### 1.1 Bash 3.2 Compat (#4)

Replace all 6 `${PHASE^^}` occurrences in `plugin/scripts/post-tool-navigator.sh` with:
```bash
$(echo "$PHASE" | tr '[:lower:]' '[:upper:]')
```

**Files:** `plugin/scripts/post-tool-navigator.sh` (lines 302, 328, 388, 411, 439, 458)

#### 1.2 COMMAND Extraction DRY (#5)

Add helper function at the top of `plugin/scripts/post-tool-navigator.sh`:
```bash
extract_bash_command() {
    echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('command',''))" 2>/dev/null || echo ""
}
```

Replace 4 duplicate extractions (lines 218, 241, 308, 470) with calls to `extract_bash_command`.

**Files:** `plugin/scripts/post-tool-navigator.sh`

#### 1.3 WRITE_PATTERN Readability (#6)

Break single 500+ char regex in `plugin/scripts/bash-write-guard.sh` into named fragments:

```bash
REDIRECT_OPS='(>[^&]|>>)'
INPLACE_EDITORS='(sed[[:space:]]+-i|perl[[:space:]]+-i|ruby[[:space:]]+-i)'
STREAM_WRITERS='(tee[[:space:]])'
HEREDOCS='(cat[[:space:]].*<<|bash[[:space:]].*<<|sh[[:space:]].*<<|python[3]?[[:space:]].*<<)'
FILE_OPS='(cp[[:space:]]|mv[[:space:]]|rm[[:space:]]|install[[:space:]]|patch[[:space:]]|ln[[:space:]]|touch[[:space:]]|truncate[[:space:]])'
DOWNLOADS='(curl[[:space:]].*-o[[:space:]]|wget[[:space:]].*-O[[:space:]])'
ARCHIVE_OPS='(tar[[:space:]].*-?x|unzip[[:space:]])'
BLOCK_OPS='(dd[[:space:]].*of=)'
SYNC_OPS='(rsync[[:space:]])'
EXEC_WRAPPERS='(eval[[:space:]]|bash[[:space:]]+-c|sh[[:space:]]+-c)'
ECHO_REDIRECT='(echo[[:space:]].*>)'

WRITE_PATTERN="$REDIRECT_OPS|$INPLACE_EDITORS|$STREAM_WRITERS|$HEREDOCS|$FILE_OPS|$DOWNLOADS|$ARCHIVE_OPS|$BLOCK_OPS|$SYNC_OPS|$EXEC_WRAPPERS|$ECHO_REDIRECT"
```

Same regex behavior, readable by group name.

**Files:** `plugin/scripts/bash-write-guard.sh`

#### 1.4 Consolidate jq Calls (#7)

Replace 7 separate `echo "$DATA" | jq` calls in `plugin/statusline/statusline.sh` (lines 14-20) with a single call:

```bash
read -r MODEL USED_PCT USED_TOKENS TOTAL_TOKENS CWD WORKTREE_NAME WORKTREE_BRANCH < <(
  echo "$DATA" | jq -r '[
    (.model.display_name // "?"),
    ((.context_window.used_percentage // 0) | floor | tostring),
    (((.context_window.current_usage.input_tokens // 0) + (.context_window.current_usage.cache_creation_input_tokens // 0) + (.context_window.current_usage.cache_read_input_tokens // 0)) | tostring),
    ((.context_window.context_window_size // 0) | tostring),
    (.cwd // ""),
    (.worktree.name // ""),
    (.worktree.branch // "")
  ] | @tsv'
)
```

7 process spawns reduced to 1. The `cut -d. -f1` for USED_PCT moves into jq as `floor`.

**Files:** `plugin/statusline/statusline.sh`

#### 1.5 workflow-cmd.sh Allowlist (#9)

Replace bare `"$@"` dispatch in `plugin/scripts/workflow-cmd.sh` with a `case` allowlist:

```bash
case "$1" in
    get_phase|set_phase|get_autonomy_level|set_autonomy_level|\
    get_active_skill|set_active_skill|\
    get_decision_record|set_decision_record|\
    get_message_shown|set_message_shown|\
    check_soft_gate|\
    reset_review_status|get_review_field|set_review_field|\
    reset_completion_status|get_completion_field|set_completion_field|\
    reset_implement_status|get_implement_field|set_implement_field|\
    increment_coaching_counter|reset_coaching_counter|\
    add_coaching_fired|has_coaching_fired|check_coaching_refresh|\
    set_pending_verify|get_pending_verify|\
    get_last_observation_id|set_last_observation_id|\
    get_tracked_observations|set_tracked_observations|\
    add_tracked_observation|remove_tracked_observation|\
    emit_deny)
        "$@"
        ;;
    *)
        echo "ERROR: Unknown command: $1" >&2
        exit 1
        ;;
esac
```

Private `_`-prefixed helpers (`_reset_section`, `_get_section_field`, `_set_section_field`, `_section_exists`, `_check_milestones`) excluded from allowlist.

**Files:** `plugin/scripts/workflow-cmd.sh`

#### 1.6 Stale Doc Paths (#12)

Update `docs/guides/statusline-guide.md` Files table to reference `plugin/statusline/statusline.sh`. Note that `settings.json.example` is no longer needed — plugin auto-configures via setup.sh.

**Files:** `docs/guides/statusline-guide.md`

#### 1.7 Duplicate plugin.json (#11)

**No change.** Both copies are needed (root for marketplace discovery, plugin/ for distribution). `scripts/check-version-sync.sh` already validates they stay in sync.

### Phase 2: Tracked Observations Lifecycle (#13)

#### 2.1 Atomic Replace Strategy

The tracked observations list is only modified during the COMPLETE phase, in a single atomic operation at the end of Step 8. No partial writes at any point.

**Step 7 (Tech Debt Audit) — read-only:**
1. Read current list: `get_tracked_observations`
2. Fetch observations via `get_observations([IDs])`
3. For each, assess: resolved this session or still open
4. Build two in-memory lists:
   - `KEEP_IDS` — still-open observation IDs
   - `RESOLVED_IDS` — items completed this session (for reporting)
5. Present both in the tech debt audit table
6. **No writes to `tracked_observations`** — state unchanged

**Step 8 (Handover) — single atomic write:**
1. Save handover observation → `HANDOVER_ID`
2. Collect any additional tech debt observation IDs saved during Step 7 → `NEW_IDS`
3. Build final list: `KEEP_IDS` + `HANDOVER_ID` + `NEW_IDS`
4. Single call: `set_tracked_observations "<comma-separated-final-list>"`
5. Update `set_last_observation_id` to handover

**Crash safety:** If session dies at any point before Step 8's `set_tracked_observations` call, the previous session's list is fully intact. No partial state.

**Edge cases:**
- First session (empty list): Step 7 has nothing to review, Step 8 sets `[HANDOVER_ID]`
- All items resolved: Step 8 sets `[HANDOVER_ID]` only
- Session crash mid-pipeline: old list survives, next session picks up where it left off

#### 2.2 complete.md Changes

**Step 7** gains a preamble:

> Read the tracked observations list. If non-empty, fetch them and review each: mark as resolved (if fixed this session) or still-open. Present a combined table of carried-over items and new tech debt. Build `KEEP_IDS` (still-open) and `RESOLVED_IDS` (completed) for use in Step 8. Do not modify the tracked_observations state.

**Step 8** gains a postamble (replaces the existing `add_tracked_observation` call):

> After saving the handover observation, build the final tracked observations list from: KEEP_IDS (from Step 7) + handover observation ID + any new tech debt observation IDs. Write atomically via a single `set_tracked_observations` call. This replaces the existing `add_tracked_observation` instruction.

#### 2.3 Version Bump in COMPLETE Step 5 (#14)

**Step 5 (Commit & Push)** gains a version bump before committing:

1. Dispatch a **Versioning agent** that:
   - Reads the phase history from the decision record and git log for this branch
   - Determines the bump type based on what happened:
     - **Major:** Breaking changes to public API (hook contracts, state schema, command interfaces)
     - **Minor:** New features — session went through DEFINE/DISCUSS (new capability added)
     - **Patch:** Bug fixes, refactors, tech debt cleanup — session went straight to IMPLEMENT or changes are internal only
   - Reads current version from `.claude-plugin/marketplace.json`
   - Computes the new version
   - Returns the bump type and new version with reasoning

2. Apply the bump to all 3 version files:
   - `.claude-plugin/marketplace.json`
   - `.claude-plugin/plugin.json`
   - `plugin/.claude-plugin/plugin.json`

3. Run `scripts/check-version-sync.sh` to validate sync

4. Include version bump in the commit

**No user interaction required.** At autonomy level 3, the agent decides autonomously. At levels 1-2, the agent's recommendation is presented as part of the commit summary but doesn't block for approval — the user can always amend if they disagree.

**Files:** `plugin/commands/complete.md`, `scripts/check-version-sync.sh` (no change, already validates)

### Phase 3: COMPLETE Pipeline Improvements

#### 3.1 Boundary Testing Agent (#1)

Added to **Step 2 (Outcome Validation)**, dispatched alongside the existing outcome validator.

**Agent prompt pattern:**
> "You are a boundary tester. Read the changed files from `git diff --name-only main...HEAD` and the plan/spec at [PATH]. Generate edge cases the plan didn't specify: different invocation paths, unusual inputs, empty inputs, boundary values, unexpected types. For each edge case, run the test and report PASS/FAIL with evidence."

**Output:** A **Boundary Tests** table added to Step 3's presentation:

| # | Edge Case | Expected | Actual | Status |
|---|-----------|----------|--------|--------|
| 1 | Empty input to X | Graceful error | Graceful error | PASS |
| 2 | Full path `/usr/bin/git commit` | Blocked by guard | Allowed through | FAIL |

**Files:** `plugin/commands/complete.md`

#### 3.2 Devil's Advocate Agent (#2)

Added to **Step 2**, dispatched after the boundary tester (it reads changed code, not the spec).

**Agent prompt pattern:**
> "You are an adversarial tester. Read the actual implementation files that changed. Your job is to break this. Generate: malformed data, race conditions, path traversal attempts, injection attempts, missing dependency scenarios, partial state. For each attack, run it and report the result."

**Key difference from boundary tester:** Boundary tester works spec-outward ("what did the spec miss?"). Devil's advocate works code-inward ("what can I break by reading the implementation?").

**Output:** A **Devil's Advocate** table in Step 3.

**Files:** `plugin/commands/complete.md`

#### 3.3 COMPLETE Loop-back Exception (#3)

When validation (Steps 1-3) finds a code fix is needed and the user chooses to fix it:

**New state:**
```json
{
  "completion_snapshot": {
    "plan_validated": true,
    "outcomes_validated": true,
    "results_presented": true,
    "docs_checked": true,
    "committed": false,
    "tech_debt_audited": false,
    "handover_saved": false
  }
}
```

**New functions in workflow-state.sh:**
- `save_completion_snapshot` — copies current completion milestones to `completion_snapshot`
- `restore_completion_snapshot` — restores milestones from snapshot, clears snapshot
- `has_completion_snapshot` — returns true/false

**Flow:**
1. Validation fails → user agrees to fix
2. `save_completion_snapshot` preserves current milestone state
3. `set_phase "implement"` — normal IMPLEMENT phase with all its gates
4. After fix, user runs `/complete`
5. At the **top of the Completion Pipeline** (before Step 1), `/complete` checks `has_completion_snapshot` → if true, restores milestones via `restore_completion_snapshot`
6. Re-runs Steps 1-3 only (re-validates with the fix applied)
7. Steps 4+ resume from where they left off

**Hard gate interaction:** IMPLEMENT's own hard gate (`plan_read`, `tests_passing`, `all_tasks_complete`) still applies during the excursion. The snapshot only preserves COMPLETE milestones, not IMPLEMENT milestones.

**Files:** `plugin/scripts/workflow-state.sh`, `plugin/commands/complete.md`, `plugin/commands/implement.md`

### Phase 4: Test Coverage

#### 4.1 setup.sh Functional Tests (#8)

New test section in `tests/run-tests.sh`:
- State directory creation
- `.gitignore` management (adds entry, idempotent on rerun)
- Statusline copy to target location
- Settings.json statusline configuration
- Idempotency (run twice, verify no duplication)

#### 4.2 Version Detection Tests (#10)

New test section:
- Empty plugin cache directory → version "?"
- Single version → correct detection
- Multiple versions (`1.0.0`, `1.1.0`, `2.0.0`) → highest picked via `sort -V`

#### 4.3 Tracked Observations Lifecycle Tests

New test section:
- `add_tracked_observation` adds to list
- `add_tracked_observation` is idempotent (no duplicates)
- `remove_tracked_observation` removes single item
- `set_tracked_observations` replaces entire list
- `get_tracked_observations` returns CSV
- Preservation across `set_phase` transitions (off → define → off)
- Empty list returns empty string

#### 4.4 COMPLETE Loop-back Tests

New test section:
- `save_completion_snapshot` captures current milestones
- `restore_completion_snapshot` restores them
- `has_completion_snapshot` returns true when snapshot exists, false otherwise
- Snapshot survives `set_phase` to implement and back

#### 4.5 workflow-cmd.sh Allowlist Tests

New test section:
- Public function call succeeds
- Private `_`-prefixed function call fails with error
- Unknown function call fails with error

## Outcomes

### Verifiable
1. All `${PHASE^^}` replaced — `grep -c '\${.*\^\^}' plugin/scripts/post-tool-navigator.sh` returns 0
2. COMMAND extraction uses helper — `grep -c 'extract_bash_command' plugin/scripts/post-tool-navigator.sh` returns 4+
3. WRITE_PATTERN is multi-line — `grep -c '_OPS\|_EDITORS\|_WRITERS\|_REDIRECT' plugin/scripts/bash-write-guard.sh` returns 10+
4. Single jq call in statusline — `grep -c 'echo "\$DATA" | jq' plugin/statusline/statusline.sh` returns 1
5. Allowlist blocks private helpers — `plugin/scripts/workflow-cmd.sh _reset_section` returns error
6. Tracked observations survive crash scenario — old list intact if Step 8 never runs
7. Boundary tester and devil's advocate agents dispatched in COMPLETE Step 2
8. Loop-back from COMPLETE preserves milestones via snapshot
9. All new test sections pass
10. Full test suite passes (current baseline + new tests, no regressions — verify baseline count at implementation time)
11. Version bump agent dispatched in COMPLETE Step 5 — all 3 version files updated and sync check passes

### Monitoring
- Statusline render time with consolidated jq (should be faster, measure if needed)
- COMPLETE pipeline duration with 2 new agents (acceptable overhead for validation quality)

## Files Modified

| File | Changes |
|------|---------|
| `plugin/scripts/post-tool-navigator.sh` | #4 bash compat, #5 DRY extraction |
| `plugin/scripts/bash-write-guard.sh` | #6 pattern readability |
| `plugin/statusline/statusline.sh` | #7 jq consolidation |
| `plugin/scripts/workflow-cmd.sh` | #9 allowlist |
| `plugin/scripts/workflow-state.sh` | #3 snapshot functions, #13 already has CRUD |
| `plugin/commands/complete.md` | #1 boundary agent, #2 devil's advocate, #3 loop-back, #13 lifecycle |
| `docs/guides/statusline-guide.md` | #12 stale paths |
| `tests/run-tests.sh` | #8, #10, tracked obs tests, loop-back tests, allowlist tests |


## Decision Record (Archived)

# Decision Record: Open Issues Cleanup & Tracked Observations

**Date:** 2026-03-23
**Phase:** DISCUSS
**Observation context:** #3416 (consolidated open issues list)

## Problem

13 accumulated open issues and tech debt items since plugin conversion. Ranging from bash compatibility bugs (#4) to missing adversarial validation in the COMPLETE pipeline (#1, #2) to a partially-implemented tracked observations feature with a race condition (#13).

The user wants all 13 items addressed in a single coordinated effort, properly designed and validated.

## Approaches Considered (DISCUSS phase — diverge)

### Approach A: Fix items individually as independent PRs
- Description: Each item gets its own branch, spec, and PR
- Pros: Minimal blast radius per change, easy to review
- Cons: 13 separate cycles is excessive overhead for items that are mostly S-effort. Many items touch the same files. Interactions between COMPLETE pipeline changes (#1, #2, #3, #13) would be hard to coordinate.

### Approach B: Phased implementation in dependency order (CHOSEN)
- Description: Group items into 4 phases by dependency and priority. Foundation fixes first (unblock everything), then tracked observations lifecycle, then COMPLETE pipeline improvements, then test coverage.
- Pros: Natural dependency ordering. Mechanical fixes done first reduce noise. Design-heavy items (#13, #1-3) done together since they interact. Tests last to validate everything.
- Cons: Larger single commit scope. If one phase has issues, it blocks subsequent phases.

### Approach C: Fix only HIGH priority items, defer the rest
- Description: Address #1, #2, #13 now, defer medium/low items
- Pros: Faster completion
- Cons: User explicitly asked for all items. Deferring again defeats the purpose of the cleanup.

## Decision (DISCUSS phase — converge)

- **Chosen approach:** B — Phased implementation in dependency order
- **Rationale:** All 13 items are in scope per user request. Grouping by dependency prevents blocked work. Mechanical fixes first clears the noise.
- **Trade-offs accepted:** Larger commit scope means more to review if something goes wrong. Acceptable because test coverage (Phase 4) validates everything.
- **Risks identified:** The jq consolidation (#7) changes statusline parsing — a bug here affects every prompt refresh. Mitigated by testing with real session data.
- **Constraints applied:** Tracked observations lifecycle must use atomic replace (option a) — no partial writes, crash-safe by design.
- **Tech debt acknowledged:** #11 (duplicate plugin.json) deliberately left unfixed — mitigated by existing version sync check.
- **Additional item discovered:** #14 — COMPLETE pipeline doesn't bump the plugin version before push. Added a versioning agent to Step 5 that determines bump type (major/minor/patch) from phase history and applies it autonomously.
- **Design spec:** `docs/superpowers/specs/2026-03-23-open-issues-cleanup-design.md`
