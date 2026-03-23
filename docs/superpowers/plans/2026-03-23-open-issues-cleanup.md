# Open Issues Cleanup & Tracked Observations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Resolve all 15 open issues and tech debt items from observation #3416, add safe tracked observations lifecycle, improve COMPLETE pipeline with boundary testing / devil's advocate / loop-back exception / version bumping, and fix setup.sh permissions for unattended operation.

**Architecture:** Four implementation phases in dependency order. Phase 1 is mechanical refactors (6 files). Phase 2 adds atomic tracked observations lifecycle to complete.md. Phase 3 adds three new COMPLETE pipeline features (agents + snapshot). Phase 4 adds test coverage for everything.

**Tech Stack:** Bash, Python3 (inline), jq, git

**Spec:** `docs/superpowers/specs/2026-03-23-open-issues-cleanup-design.md`
**Decision Record:** `docs/superpowers/specs/2026-03-23-open-issues-cleanup-decision.md`

---

### Task 0: Commit Spec and Decision Record

The spec and decision record were written during DISCUSS but couldn't be committed (write guard). Commit them now.

**Files:**
- Stage: `docs/superpowers/specs/2026-03-23-open-issues-cleanup-design.md`
- Stage: `docs/superpowers/specs/2026-03-23-open-issues-cleanup-decision.md`

- [ ] **Step 1: Commit spec and decision record**

```bash
git add docs/superpowers/specs/2026-03-23-open-issues-cleanup-design.md docs/superpowers/specs/2026-03-23-open-issues-cleanup-decision.md
echo "========== YUBIKEY: TOUCH NOW FOR GIT COMMIT ==========" && git commit -m "$(cat <<'EOF'
docs: add design spec and decision record for open issues cleanup

Covers all 14 items: bash 3.2 compat, DRY extraction, pattern
readability, jq consolidation, allowlist, tracked observations
lifecycle, COMPLETE pipeline improvements, version bumping, and
test coverage.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 0.5: Setup.sh Auto-Permissions (#15)

The plugin's `setup.sh` runs every session but doesn't configure project permissions. Tools like `Read`, `Agent`, `Glob`, `Grep` are needed by the workflow pipeline (hooks, coaching, COMPLETE agents) but aren't auto-allowed. This breaks autonomy level 3 with constant approval prompts.

**Files:**
- Modify: `plugin/scripts/setup.sh` (add section C)
- Test: `tests/run-tests.sh` (add setup.sh permission tests)

- [ ] **Step 1: Add section C to setup.sh**

After section B (statusline installation), add:

```bash
# ─────────────────────────────────────────────────────────────────────────────
# C. Project permissions — ensure tools needed for workflow pipeline are allowed
# ─────────────────────────────────────────────────────────────────────────────

# The workflow pipeline (hooks, coaching, COMPLETE agents) needs these tools
# to operate without permission prompts. Without them, autonomy level 3
# (unattended) is broken by constant approval dialogs.
PROJECT_SETTINGS="$PROJECT_DIR/.claude/settings.json"
if [ -f "$PROJECT_SETTINGS" ]; then
  python3 -c "
import json, sys

settings_path = sys.argv[1]
with open(settings_path, 'r') as f:
    settings = json.load(f)

permissions = settings.setdefault('permissions', {})
allow = permissions.setdefault('allow', [])

# Tools required for unattended workflow operation
required_tools = ['Read', 'Agent', 'Glob', 'Grep']

changed = False
for tool in required_tools:
    if tool not in allow:
        allow.append(tool)
        changed = True

if changed:
    with open(settings_path, 'w') as f:
        json.dump(settings, f, indent=2)
        f.write('\n')
" "$PROJECT_SETTINGS" || true
fi
```

Also update the comment at the top of setup.sh to mention the third responsibility.

- [ ] **Step 2: Verify it works on a test project**

Create a temp directory with a minimal `.claude/settings.json` that has `Bash` in allow but not `Read`/`Agent`/`Glob`/`Grep`. Run setup.sh. Verify all 4 tools were added. Run again. Verify no duplicates.

- [ ] **Step 3: Verify idempotency on current project**

Run setup.sh on the current project. Check that `Read`, `Agent`, `Glob`, `Grep` appear in `.claude/settings.json` permissions. Run again. Check no duplicates.

---

### Task 1: Bash 3.2 Compatibility (#4)

Replace all `${PHASE^^}` bash 4+ uppercase syntax with portable `tr` alternative.

**Files:**
- Modify: `plugin/scripts/post-tool-navigator.sh` (lines 302, 328, 388, 411, 439, 458)

- [ ] **Step 1: Replace all 6 occurrences**

Replace every `${PHASE^^}` with `$(echo "$PHASE" | tr '[:lower:]' '[:upper:]')` at these locations:

Line 302 (Layer 3 — short agent prompt):
```
Old: [Workflow Coach — ${PHASE^^}] Agent prompts must be
New: [Workflow Coach — $(echo "$PHASE" | tr '[:lower:]' '[:upper:]')] Agent prompts must be
```

Line 328 (Layer 3 — generic commit):
```
Old: [Workflow Coach — ${PHASE^^}] Commit messages must explain
New: [Workflow Coach — $(echo "$PHASE" | tr '[:lower:]' '[:upper:]')] Commit messages must explain
```

Line 388 (Layer 3 — project field):
```
Old: [Workflow Coach — ${PHASE^^}] save_observation called without
New: [Workflow Coach — $(echo "$PHASE" | tr '[:lower:]' '[:upper:]')] save_observation called without
```

Line 411 (Layer 3 — research skip):
```
Old: [Workflow Coach — ${PHASE^^}] You're in a research phase
New: [Workflow Coach — $(echo "$PHASE" | tr '[:lower:]' '[:upper:]')] You're in a research phase
```

Line 439 (Layer 3 — options recommendation):
```
Old: [Workflow Coach — ${PHASE^^}] Don't just list options
New: [Workflow Coach — $(echo "$PHASE" | tr '[:lower:]' '[:upper:]')] Don't just list options
```

Line 458 (Layer 3 — verify changes):
```
Old: [Workflow Coach — ${PHASE^^}] You've edited source code
New: [Workflow Coach — $(echo "$PHASE" | tr '[:lower:]' '[:upper:]')] You've edited source code
```

- [ ] **Step 2: Verify no remaining `${VAR^^}` patterns**

Run: `grep -n '\${.*\^\^}' plugin/scripts/post-tool-navigator.sh`
Expected: No output (exit code 1)

- [ ] **Step 3: Run full test suite**

Run: `bash tests/run-tests.sh`
Expected: All tests pass, no regressions

---

### Task 2: COMMAND Extraction DRY (#5)

Extract duplicated command parsing into a helper function.

**Files:**
- Modify: `plugin/scripts/post-tool-navigator.sh` (add function near line 22, replace lines 218, 241, 308, 470)

- [ ] **Step 1: Add helper function after TOOL_NAME extraction (after line 22)**

Insert after the `TOOL_NAME=` line:

```bash
# Helper: extract bash command from tool input (used by Layer 2/3 checks)
extract_bash_command() {
    echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('command',''))" 2>/dev/null || echo ""
}
```

- [ ] **Step 2: Replace all 4 duplicate extractions**

Line 218 (implement phase, test_run trigger):
```
Old: COMMAND=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('command',''))" 2>/dev/null || echo "")
New: COMMAND=$(extract_bash_command)
```

Line 241 (complete phase, test_run_complete trigger):
```
Old: BASH_CMD=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('command',''))" 2>/dev/null || echo "")
New: BASH_CMD=$(extract_bash_command)
```

Line 308 (Layer 3, generic commit check):
```
Old: COMMAND=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('command',''))" 2>/dev/null || echo "")
New: COMMAND=$(extract_bash_command)
```

Line 470 (Layer 3, verify after code change):
```
Old: BASH_CMD=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('command',''))" 2>/dev/null || echo "")
New: BASH_CMD=$(extract_bash_command)
```

- [ ] **Step 3: Verify extraction count**

Run: `grep -c 'extract_bash_command' plugin/scripts/post-tool-navigator.sh`
Expected: 5 (1 definition + 4 calls)

- [ ] **Step 4: Run full test suite**

Run: `bash tests/run-tests.sh`
Expected: All tests pass

---

### Task 3: WRITE_PATTERN Readability (#6)

Break monolithic regex into named fragments.

**Files:**
- Modify: `plugin/scripts/bash-write-guard.sh` (replace line 33)

- [ ] **Step 1: Replace WRITE_PATTERN with named fragments**

Replace the single `WRITE_PATTERN='...'` line (line 33) with:

```bash
# Write pattern — detects file-writing operations (named fragments for readability)
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

Also remove the old comment block above line 33 (lines 21-32 — the group descriptions) since each fragment is now self-documenting.

- [ ] **Step 2: Verify pattern fragment count**

Run: `grep -cE '_OPS|_EDITORS|_WRITERS|_REDIRECT|HEREDOCS|EXEC_WRAPPERS' plugin/scripts/bash-write-guard.sh`
Expected: 12+ (11 fragment definitions + 1 combined WRITE_PATTERN)

- [ ] **Step 3: Run full test suite**

Run: `bash tests/run-tests.sh`
Expected: All tests pass — same write-guard behavior, just readable code

---

### Task 4: Consolidate jq Calls (#7)

Replace 7 jq process spawns with 1 in statusline.

**Files:**
- Modify: `plugin/statusline/statusline.sh` (replace lines 14-20)

- [ ] **Step 1: Replace 7 jq calls with single consolidated call**

Replace lines 14-20:

```bash
MODEL=$(echo "$DATA" | jq -r '.model.display_name // "?"')
USED_PCT=$(echo "$DATA" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)
USED_TOKENS=$(echo "$DATA" | jq -r '(.context_window.current_usage.input_tokens // 0) + (.context_window.current_usage.cache_creation_input_tokens // 0) + (.context_window.current_usage.cache_read_input_tokens // 0)')
TOTAL_TOKENS=$(echo "$DATA" | jq -r '.context_window.context_window_size // 0')
CWD=$(echo "$DATA" | jq -r '.cwd // ""')
WORKTREE_NAME=$(echo "$DATA" | jq -r '.worktree.name // empty' 2>/dev/null)
WORKTREE_BRANCH=$(echo "$DATA" | jq -r '.worktree.branch // empty' 2>/dev/null)
```

With:

```bash
IFS=$'\t' read -r MODEL USED_PCT USED_TOKENS TOTAL_TOKENS CWD WORKTREE_NAME WORKTREE_BRANCH < <(
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

- [ ] **Step 2: Test statusline renders correctly**

Run:
```bash
echo '{"model":{"display_name":"Opus 4.6"},"context_window":{"used_percentage":42.5,"current_usage":{"input_tokens":50000,"cache_creation_input_tokens":10000,"cache_read_input_tokens":5000},"context_window_size":200000},"cwd":"'$(pwd)'"}' | bash plugin/statusline/statusline.sh 2>&1 | cat -v
```
Expected: Output shows "Opus 4.6", "42%", "(65k/200k)", branch name, and plugin versions

- [ ] **Step 3: Test with worktree fields**

Run:
```bash
echo '{"model":{"display_name":"Test"},"context_window":{"used_percentage":10,"current_usage":{"input_tokens":1000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0},"context_window_size":100000},"cwd":"'$(pwd)'","worktree":{"name":"feature-x","branch":"feat/x"}}' | bash plugin/statusline/statusline.sh 2>&1 | cat -v
```
Expected: Output includes worktree name and branch

- [ ] **Step 4: Test with empty/missing fields**

Run:
```bash
echo '{"model":{},"context_window":{}}' | bash plugin/statusline/statusline.sh 2>&1 | cat -v
```
Expected: Output shows "?" for model, "0%" for context, no crash

- [ ] **Step 5: Verify single jq call**

Run: `grep -c 'echo "\$DATA" | jq' plugin/statusline/statusline.sh`
Expected: 1

---

### Task 5: workflow-cmd.sh Allowlist (#9)

Add function dispatch allowlist to prevent calling private helpers.

**Files:**
- Modify: `plugin/scripts/workflow-cmd.sh` (replace line 25)

- [ ] **Step 1: Replace bare `"$@"` with case allowlist**

Replace line 25 (`"$@"`) with:

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
    save_completion_snapshot|restore_completion_snapshot|has_completion_snapshot|\
    emit_deny)
        "$@"
        ;;
    *)
        echo "ERROR: Unknown command: $1" >&2
        exit 1
        ;;
esac
```

Note: includes `save_completion_snapshot|restore_completion_snapshot|has_completion_snapshot` for Task 9 (loop-back exception).

- [ ] **Step 2: Verify public function still works**

Run: `plugin/scripts/workflow-cmd.sh get_phase`
Expected: Returns current phase (e.g., "implement")

- [ ] **Step 3: Verify private function is blocked**

Run: `plugin/scripts/workflow-cmd.sh _reset_section test 2>&1`
Expected: "ERROR: Unknown command: _reset_section"

- [ ] **Step 4: Run full test suite**

Run: `bash tests/run-tests.sh`
Expected: All tests pass

---

### Task 6: Fix Stale Doc Paths (#12)

Update statusline-guide.md Files table.

**Files:**
- Modify: `docs/guides/statusline-guide.md` (lines 126-129)

- [ ] **Step 1: Update Files table**

Replace lines 126-129:

```markdown
| [`statusline/statusline.sh`](../../statusline/statusline.sh) | The status line script |
| [`statusline/settings.json.example`](../../statusline/settings.json.example) | Example settings.json snippet |
```

With:

```markdown
| [`plugin/statusline/statusline.sh`](../../plugin/statusline/statusline.sh) | The status line script (installed to `~/.claude/statusline.sh` by setup hook) |
```

The `settings.json.example` row is removed — the plugin auto-configures settings.json via setup.sh.

---

### Task 7: Commit Phase 1

Commit all foundation fixes together.

- [ ] **Step 1: Run full test suite before committing**

Run: `bash tests/run-tests.sh`
Expected: All tests pass

- [ ] **Step 2: Commit**

```bash
git add plugin/scripts/post-tool-navigator.sh plugin/scripts/bash-write-guard.sh plugin/statusline/statusline.sh plugin/scripts/workflow-cmd.sh plugin/scripts/setup.sh docs/guides/statusline-guide.md
echo "========== YUBIKEY: TOUCH NOW FOR GIT COMMIT ==========" && git commit -m "$(cat <<'EOF'
refactor: foundation fixes — bash compat, DRY, readability, jq, allowlist, permissions, docs

- Replace 6x ${PHASE^^} with tr for bash 3.2 compat (#4)
- Extract duplicated COMMAND parsing into helper function (#5)
- Break WRITE_PATTERN into named regex fragments (#6)
- Consolidate 7 jq calls to 1 in statusline (#7)
- Add function allowlist to workflow-cmd.sh (#9)
- Auto-configure Read/Agent/Glob/Grep permissions in setup.sh (#15)
- Fix stale paths in statusline-guide.md (#12)

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 8: Tracked Observations Atomic Lifecycle (#13)

Modify complete.md to use atomic replace instead of incremental add/remove.

**Files:**
- Modify: `plugin/commands/complete.md` (Step 7 preamble, Step 8 postamble replacement)

- [ ] **Step 1: Add tracked observations review to Step 7 preamble**

In `plugin/commands/complete.md`, insert before the existing Step 7 content ("Before closing, review the decision record...") at line 237:

```markdown
**First, review tracked observations from prior sessions:**

```bash
WF="${CLAUDE_PLUGIN_ROOT}/scripts/workflow-cmd.sh"
TRACKED=$("$WF" get_tracked_observations)
echo "Tracked observations: ${TRACKED:-none}"
```

If the tracked list is non-empty, fetch them via `get_observations([IDs])` and for each:
- **Resolved this session?** → mark as RESOLVED in the table below (will be removed from tracked list in Step 8)
- **Still open?** → mark as OPEN in the table below (will be kept in tracked list in Step 8)

Build two in-memory lists: `KEEP_IDS` (still-open observation IDs) and `RESOLVED_IDS` (completed this session). These are used by Step 8 — **do not modify tracked_observations here**.

Then proceed with the existing tech debt audit:
```

- [ ] **Step 2: Replace Step 8 tracked observations logic**

Replace the existing `add_tracked_observation` block in Step 8 (lines 284-289):

```markdown
After saving the handover observation, add it to the tracked observations list (which persists in the statusline for future sessions):
```bash
WF="${CLAUDE_PLUGIN_ROOT}/scripts/workflow-cmd.sh" && "$WF" add_tracked_observation "<HANDOVER_OBS_ID>"
```

Also add any tech debt or open issues observations from Step 7 to the tracked list if they were saved as separate observations.
```

With:

```markdown
After saving the handover observation, build the final tracked observations list atomically:

1. Take `KEEP_IDS` from Step 7 (still-open items)
2. Add the handover observation ID
3. Add any new tech debt observation IDs saved during this step
4. Write the complete list in a single call:

```bash
WF="${CLAUDE_PLUGIN_ROOT}/scripts/workflow-cmd.sh" && "$WF" set_tracked_observations "<KEEP_IDS>,<HANDOVER_ID>,<NEW_TECH_DEBT_IDS>"
```

This atomic replace ensures crash safety — if the session dies before this line, the previous tracked list is fully intact.
```

- [ ] **Step 3: Verify complete.md is coherent**

Read the full complete.md and verify Steps 7 and 8 flow logically.

---

### Task 9: COMPLETE Loop-back Exception (#3)

Add snapshot functions and loop-back detection to complete.md.

**Files:**
- Modify: `plugin/scripts/workflow-state.sh` (add 3 functions)
- Modify: `plugin/commands/complete.md` (add snapshot detection at top, fix excursion in Step 3)

- [ ] **Step 1: Add snapshot functions to workflow-state.sh**

Add after the `remove_tracked_observation` function (end of tracked observations section):

```bash
# ---------------------------------------------------------------------------
# Completion snapshot (loop-back exception from COMPLETE → IMPLEMENT → COMPLETE)
# ---------------------------------------------------------------------------

save_completion_snapshot() {
    if [ ! -f "$STATE_FILE" ]; then return; fi
    local ts
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    python3 -c "
import json, sys
ts, filepath = sys.argv[1], sys.argv[2]
with open(filepath, 'r') as f:
    d = json.load(f)
completion = d.get('completion', {})
if completion:
    d['completion_snapshot'] = dict(completion)
d['updated'] = ts
with open(filepath, 'w') as f:
    json.dump(d, f, indent=2)
    f.write('\n')
" "$ts" "$STATE_FILE"
}

restore_completion_snapshot() {
    if [ ! -f "$STATE_FILE" ]; then return; fi
    local ts
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    python3 -c "
import json, sys
ts, filepath = sys.argv[1], sys.argv[2]
with open(filepath, 'r') as f:
    d = json.load(f)
snapshot = d.get('completion_snapshot', {})
if snapshot:
    d['completion'] = dict(snapshot)
    del d['completion_snapshot']
d['updated'] = ts
with open(filepath, 'w') as f:
    json.dump(d, f, indent=2)
    f.write('\n')
" "$ts" "$STATE_FILE"
}

has_completion_snapshot() {
    if [ ! -f "$STATE_FILE" ]; then echo "false"; return; fi
    python3 -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        d = json.load(f)
    print('true' if 'completion_snapshot' in d and d['completion_snapshot'] else 'false')
except Exception:
    print('false')
" "$STATE_FILE" 2>/dev/null
}
```

- [ ] **Step 2: Verify snapshot functions work**

Run:
```bash
source plugin/scripts/workflow-state.sh
set_phase "complete"
reset_completion_status
set_completion_field "plan_validated" "true"
set_completion_field "outcomes_validated" "true"
save_completion_snapshot
echo "Snapshot saved: $(has_completion_snapshot)"
set_phase "implement"
echo "Phase: $(get_phase), snapshot exists: $(has_completion_snapshot)"
set_phase "complete"
restore_completion_snapshot
echo "Restored plan_validated: $(get_completion_field plan_validated)"
echo "Snapshot cleared: $(has_completion_snapshot)"
```

Expected:
```
Snapshot saved: true
Phase: implement, snapshot exists: true
Restored plan_validated: true
Snapshot cleared: false
```

- [ ] **Step 3: Add snapshot detection to top of Completion Pipeline in complete.md**

Insert after the "Then confirm the phase change and execute the completion pipeline below." line and before "Before proceeding:":

```markdown
**Loop-back detection:** Check if returning from an IMPLEMENT excursion:

```bash
WF="${CLAUDE_PLUGIN_ROOT}/scripts/workflow-cmd.sh"
if [ "$("$WF" has_completion_snapshot)" = "true" ]; then
    "$WF" restore_completion_snapshot
    echo "Resuming completion pipeline from IMPLEMENT excursion — milestones restored."
    echo "Re-running validation (Steps 1-3), then resuming from where you left off."
fi
```

If a snapshot was restored, re-run Steps 1-3 (validation) to verify the fix, then skip to the first incomplete milestone in Steps 4-8.
```

- [ ] **Step 4: Add excursion option to Step 3 validation failure path**

In Step 3's "If any validation fails" section, add after the existing options:

```markdown
- If the user chooses `/implement` to fix: save a completion snapshot first:
  ```bash
  WF="${CLAUDE_PLUGIN_ROOT}/scripts/workflow-cmd.sh" && "$WF" save_completion_snapshot
  ```
  Then proceed to `/implement`. When the user returns to `/complete`, the snapshot will be detected and milestones restored.
```

- [ ] **Step 5: Preserve snapshot across phase transitions**

In `workflow-state.sh`'s `set_phase()` function, add `completion_snapshot` to the preserved fields. After the `existing_tracked_observations` line, add:

```bash
    local existing_completion_snapshot=""
```

And in the `if [ -f "$STATE_FILE" ]` block, add:

```bash
        existing_completion_snapshot=$(python3 -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        d = json.load(f)
    snap = d.get('completion_snapshot', {})
    print(json.dumps(snap) if snap else '')
except Exception:
    print('')
" "$STATE_FILE" 2>/dev/null)
```

And in the python3 block that builds the new state, add `sys.argv[10]` for completion_snapshot:

```python
completion_snapshot_json = sys.argv[10]

# ... after the tracked_observations block:
if completion_snapshot_json:
    state['completion_snapshot'] = json.loads(completion_snapshot_json)
```

Pass `"$existing_completion_snapshot"` as the 10th argument.

---

### Task 10: Boundary Testing Agent (#1)

Add boundary tester dispatch to COMPLETE Step 2.

**Files:**
- Modify: `plugin/commands/complete.md` (Step 2, after outcome validator)

- [ ] **Step 1: Add boundary tester dispatch after outcome validator**

In Step 2, after the outcome validator dispatch block and before "If no outcome source found", insert:

```markdown
Also dispatch a **Boundary tester agent** alongside the outcome validator:

Prompt: "You are a boundary tester for the implementation just completed. Read the changed files from `git diff --name-only main...HEAD` and the plan/spec at [PLAN_OR_SPEC_PATH]. Your job is to find edge cases the plan didn't specify. For each changed component:
1. Try different invocation paths (full paths, relative paths, symlinks)
2. Try unusual inputs (empty strings, very long strings, special characters, unicode)
3. Try boundary values (zero, negative, max values, off-by-one)
4. Try unexpected types or missing fields
For each edge case, run the actual test and report PASS/FAIL with evidence. Return a table:

| # | Component | Edge Case | Expected | Actual | Status |
|---|-----------|-----------|----------|--------|--------|"

The boundary tester's results are presented in Step 3 as a **Boundary Tests** table alongside Plan Deliverables and Outcomes.
```

- [ ] **Step 2: Add Boundary Tests table to Step 3 presentation**

In Step 3, after the **Outcomes** table, add:

```markdown
**Boundary Tests:**

| # | Component | Edge Case | Expected | Actual | Status |
|---|-----------|-----------|----------|--------|--------|
| 1 | <component> | <edge case description> | <expected behavior> | <actual behavior> | PASS/FAIL |
```

---

### Task 11: Devil's Advocate Agent (#2)

Add adversarial tester dispatch to COMPLETE Step 2.

**Files:**
- Modify: `plugin/commands/complete.md` (Step 2, after boundary tester)

- [ ] **Step 1: Add devil's advocate dispatch after boundary tester**

In Step 2, after the boundary tester block, insert:

```markdown
Finally, dispatch a **Devil's advocate agent** (runs after boundary tester, reads code not spec):

Prompt: "You are an adversarial tester. Read the actual implementation files that changed (use `git diff main...HEAD` to see the code). Your job is to break this implementation. Generate attacks:
1. Malformed data — corrupt JSON, truncated input, wrong encoding
2. Race conditions — concurrent access to shared state files
3. Path traversal — ../../../etc/passwd in file path fields
4. Injection — shell metacharacters in string fields that get interpolated
5. Missing dependencies — what if python3/jq/git isn't available?
6. Partial state — what if the state file is half-written or empty?
For each attack, attempt it and report the result. Return a table:

| # | Attack Vector | Target | Result | Severity |
|---|--------------|--------|--------|----------|"

The devil's advocate's results are presented in Step 3 as a **Devil's Advocate** table.
```

- [ ] **Step 2: Add Devil's Advocate table to Step 3 presentation**

In Step 3, after the Boundary Tests table, add:

```markdown
**Devil's Advocate:**

| # | Attack Vector | Target | Result | Severity |
|---|--------------|--------|--------|----------|
| 1 | <attack type> | <target component> | <what happened> | Critical/Warning/Info |
```

---

### Task 12: Version Bump Agent (#14)

Add versioning agent dispatch to COMPLETE Step 5.

**Files:**
- Modify: `plugin/commands/complete.md` (Step 5, before commit)

- [ ] **Step 1: Add version bump logic before commit in Step 5**

In Step 5, after "Stage the relevant files" (item 2) and before "Draft a concise conventional commit message" (item 3), insert:

```markdown
2b. **Version bump:** Dispatch a **Versioning agent** to determine the bump type:

Prompt: "Determine the semantic version bump for this release.
1. Read the decision record at [DECISION_RECORD_PATH] for phase history
2. Read `git log --oneline main...HEAD` for commit history
3. Read current version from `.claude-plugin/marketplace.json`
4. Apply these rules:
   - **Major** (X.0.0): Breaking changes to public API — hook contract changes, state schema changes that break existing state files, command interface changes
   - **Minor** (x.Y.0): New features — session went through DEFINE/DISCUSS phases (new capability), new commands added, new state fields
   - **Patch** (x.y.Z): Bug fixes, refactors, tech debt cleanup, doc updates — changes are internal only
5. Return: current version, bump type (major/minor/patch), new version, one-line reasoning"

Apply the version bump to all 3 files:
```bash
WF_ROOT="${CLAUDE_PLUGIN_ROOT}"
# The versioning agent provides NEW_VERSION
python3 -c "
import json, sys
new_version = sys.argv[1]
for path in ['.claude-plugin/marketplace.json', '.claude-plugin/plugin.json', 'plugin/.claude-plugin/plugin.json']:
    with open(path) as f:
        data = json.load(f)
    if 'plugins' in data:
        data['plugins'][0]['version'] = new_version
    else:
        data['version'] = new_version
    with open(path, 'w') as f:
        json.dump(data, f, indent=2)
        f.write('\n')
" "<NEW_VERSION>"
```

Run `scripts/check-version-sync.sh` to validate all 3 files match. Include version files in the commit staging.
```

---

### Task 13: Commit Phase 2 & 3

Commit tracked observations lifecycle and COMPLETE pipeline improvements.

- [ ] **Step 1: Run full test suite**

Run: `bash tests/run-tests.sh`
Expected: All tests pass

- [ ] **Step 2: Commit**

```bash
git add plugin/commands/complete.md plugin/scripts/workflow-state.sh
echo "========== YUBIKEY: TOUCH NOW FOR GIT COMMIT ==========" && git commit -m "$(cat <<'EOF'
feat: tracked observations lifecycle, COMPLETE pipeline improvements

- Atomic replace for tracked observations in Step 7/8 (#13)
- Boundary testing agent in Step 2 (#1)
- Devil's advocate agent in Step 2 (#2)
- Loop-back exception with completion snapshot (#3)
- Version bump agent in Step 5 (#14)

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 14: Tracked Observations Lifecycle Tests

**Files:**
- Modify: `tests/run-tests.sh` (add new test section before RESULTS)

- [ ] **Step 1: Add tracked observations test section**

Insert before the `# RESULTS` section (before line 1935):

```bash
# ============================================================
# TEST SUITE: Tracked Observations Lifecycle
# ============================================================
echo ""
echo "=== Tracked Observations Lifecycle ==="

# Setup clean state
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh"

# Test: add_tracked_observation adds to empty list
set_phase "off"
python3 -c "import json; d=json.load(open('$STATE_FILE')); d.pop('tracked_observations',None); json.dump(d,open('$STATE_FILE','w'),indent=2)"
add_tracked_observation 100
assert_eq "100" "$(get_tracked_observations)" "add_tracked_observation adds to empty list"

# Test: add_tracked_observation appends
add_tracked_observation 200
assert_eq "100,200" "$(get_tracked_observations)" "add_tracked_observation appends to list"

# Test: add_tracked_observation is idempotent
add_tracked_observation 100
assert_eq "100,200" "$(get_tracked_observations)" "add_tracked_observation is idempotent"

# Test: remove_tracked_observation removes single item
remove_tracked_observation 100
assert_eq "200" "$(get_tracked_observations)" "remove_tracked_observation removes single item"

# Test: set_tracked_observations replaces entire list
set_tracked_observations "500,600,700"
assert_eq "500,600,700" "$(get_tracked_observations)" "set_tracked_observations replaces entire list"

# Test: get_tracked_observations returns empty string for no list
python3 -c "import json; d=json.load(open('$STATE_FILE')); d.pop('tracked_observations',None); json.dump(d,open('$STATE_FILE','w'),indent=2)"
assert_eq "" "$(get_tracked_observations)" "get_tracked_observations returns empty for missing field"

# Test: tracked observations preserved across phase transitions
set_tracked_observations "3416"
set_phase "define"
assert_eq "3416" "$(get_tracked_observations)" "tracked observations preserved: off → define"
set_phase "implement"
assert_eq "3416" "$(get_tracked_observations)" "tracked observations preserved: define → implement"
set_phase "off"
assert_eq "3416" "$(get_tracked_observations)" "tracked observations preserved: implement → off"
```

- [ ] **Step 2: Run tests**

Run: `bash tests/run-tests.sh`
Expected: All tests pass including new tracked observations tests

---

### Task 15: COMPLETE Loop-back Tests

**Files:**
- Modify: `tests/run-tests.sh` (add after tracked observations tests)

- [ ] **Step 1: Add loop-back test section**

```bash
# ============================================================
# TEST SUITE: Completion Snapshot (Loop-back Exception)
# ============================================================
echo ""
echo "=== Completion Snapshot ==="

setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh"

# Test: has_completion_snapshot returns false when no snapshot
set_phase "complete"
assert_eq "false" "$(has_completion_snapshot)" "has_completion_snapshot false when no snapshot"

# Test: save/restore cycle
reset_completion_status
set_completion_field "plan_validated" "true"
set_completion_field "outcomes_validated" "true"
save_completion_snapshot
assert_eq "true" "$(has_completion_snapshot)" "has_completion_snapshot true after save"

# Test: snapshot survives phase transition to implement
set_phase "implement"
assert_eq "true" "$(has_completion_snapshot)" "snapshot survives transition to implement"

# Test: restore_completion_snapshot restores milestones
set_phase "complete"
reset_completion_status
assert_eq "false" "$(get_completion_field plan_validated)" "milestones reset before restore"
restore_completion_snapshot
assert_eq "true" "$(get_completion_field plan_validated)" "plan_validated restored from snapshot"
assert_eq "true" "$(get_completion_field outcomes_validated)" "outcomes_validated restored from snapshot"
assert_eq "false" "$(has_completion_snapshot)" "snapshot cleared after restore"
```

- [ ] **Step 2: Run tests**

Run: `bash tests/run-tests.sh`
Expected: All tests pass

---

### Task 16: workflow-cmd.sh Allowlist Tests

**Files:**
- Modify: `tests/run-tests.sh` (add after loop-back tests)

- [ ] **Step 1: Add allowlist test section**

```bash
# ============================================================
# TEST SUITE: workflow-cmd.sh Allowlist
# ============================================================
echo ""
echo "=== workflow-cmd.sh Allowlist ==="

setup_test_project

# Test: public function succeeds
RESULT=$(CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$TEST_DIR/.claude/hooks/workflow-cmd.sh" get_phase 2>&1)
assert_eq "off" "$RESULT" "allowlist: get_phase succeeds"

# Test: private _reset_section blocked
RESULT=$(CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$TEST_DIR/.claude/hooks/workflow-cmd.sh" _reset_section test 2>&1)
assert_contains "$RESULT" "ERROR: Unknown command" "allowlist: _reset_section blocked"

# Test: unknown function blocked
RESULT=$(CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$TEST_DIR/.claude/hooks/workflow-cmd.sh" nonexistent_func 2>&1)
assert_contains "$RESULT" "ERROR: Unknown command" "allowlist: unknown function blocked"
```

- [ ] **Step 2: Run tests**

Run: `bash tests/run-tests.sh`
Expected: All tests pass

---

### Task 17: setup.sh Functional Tests (#8)

**Files:**
- Modify: `tests/run-tests.sh` (add after allowlist tests)

- [ ] **Step 1: Read setup.sh to understand what to test**

Read: `plugin/scripts/setup.sh`

- [ ] **Step 2: Add setup.sh test section**

Tests will depend on what setup.sh actually does. At minimum:
- State directory creation
- `.gitignore` management
- Idempotency (run twice, no duplication)

The exact test code depends on setup.sh's implementation — the implementer should read it and write tests matching its actual behavior.

---

### Task 18: Version Detection Tests (#10)

**Files:**
- Modify: `tests/run-tests.sh` (add after setup.sh tests)

- [ ] **Step 1: Add version detection test section**

```bash
# ============================================================
# TEST SUITE: Statusline Version Detection
# ============================================================
echo ""
echo "=== Statusline Version Detection ==="

# Create mock plugin cache for testing
MOCK_CACHE=$(mktemp -d)

# Test: empty directory returns "?"
MOCK_EMPTY="$MOCK_CACHE/empty-plugin"
mkdir -p "$MOCK_EMPTY"
VERSION=$(ls -1 "$MOCK_EMPTY" 2>/dev/null | sort -V | tail -1)
VERSION="${VERSION:-?}"
assert_eq "?" "$VERSION" "version detection: empty dir returns ?"

# Test: single version detected
MOCK_SINGLE="$MOCK_CACHE/single-plugin"
mkdir -p "$MOCK_SINGLE/1.0.0"
VERSION=$(ls -1 "$MOCK_SINGLE" 2>/dev/null | sort -V | tail -1)
assert_eq "1.0.0" "$VERSION" "version detection: single version detected"

# Test: highest of multiple versions picked
MOCK_MULTI="$MOCK_CACHE/multi-plugin"
mkdir -p "$MOCK_MULTI/1.0.0" "$MOCK_MULTI/1.1.0" "$MOCK_MULTI/2.0.0" "$MOCK_MULTI/1.9.9"
VERSION=$(ls -1 "$MOCK_MULTI" 2>/dev/null | sort -V | tail -1)
assert_eq "2.0.0" "$VERSION" "version detection: highest version picked from multiple"

# Cleanup
rm -rf "$MOCK_CACHE"
```

- [ ] **Step 2: Run tests**

Run: `bash tests/run-tests.sh`
Expected: All tests pass

---

### Task 19: Commit Phase 4 (Tests)

- [ ] **Step 1: Run full test suite**

Run: `bash tests/run-tests.sh`
Expected: All tests pass (322 baseline + new tests)

- [ ] **Step 2: Commit**

```bash
git add tests/run-tests.sh
echo "========== YUBIKEY: TOUCH NOW FOR GIT COMMIT ==========" && git commit -m "$(cat <<'EOF'
test: add tracked observations, loop-back, allowlist, setup, version detection tests

- Tracked observations CRUD + idempotency + phase preservation
- Completion snapshot save/restore/survive-transition cycle
- workflow-cmd.sh allowlist blocks private helpers
- Statusline version detection with mock plugin cache
- setup.sh functional tests

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 20: Fix Hard Gate Bypass Bug (#16)

The `set_phase` function in `workflow-state.sh` has a bug: when a hard gate check fails (e.g., leaving IMPLEMENT with incomplete milestones), it prints the error to stderr but the shell command chain (`&&`) still proceeds — meaning the caller's subsequent commands (like `set_active_skill`) execute as if the phase changed. Observed: `"$WF" set_phase "discuss" && "$WF" set_active_skill "writing-plans"` — the hard gate printed "Cannot leave IMPLEMENT" but the phase was still set to discuss.

**Files:**
- Modify: `plugin/scripts/workflow-state.sh` (`set_phase` function, hard gate section)
- Test: `tests/run-tests.sh` (add hard gate enforcement test)

- [ ] **Step 1: Investigate the bug**

Read the `set_phase` function's hard gate section (around lines 174-197). The `_check_milestones` call returns missing milestones, the error is printed to stderr, and `return 1` should stop execution. But something allows the phase to change anyway.

Check: does the `&&` chain in the caller (`"$WF" set_phase "discuss" && "$WF" set_active_skill`) properly stop on `return 1`? Or does `workflow-cmd.sh` swallow the exit code?

Also check: is there a path through `set_phase` that bypasses the hard gate check (e.g., the `if [ -f "$STATE_FILE" ]` guard being false)?

- [ ] **Step 2: Fix the bug**

The fix depends on the root cause found in Step 1. Likely candidates:
- `workflow-cmd.sh` doesn't propagate the exit code from `"$@"`
- The hard gate `return 1` doesn't prevent subsequent lines in `set_phase` from running
- `set -euo pipefail` in `workflow-cmd.sh` catches the error but continues

- [ ] **Step 3: Add hard gate enforcement test**

```bash
# Test: set_phase refuses to leave IMPLEMENT with incomplete milestones
setup_test_project
source "$TEST_DIR/.claude/hooks/workflow-state.sh"
set_phase "implement"
reset_implement_status
# Don't complete any milestones
RESULT=$(set_phase "discuss" 2>&1)
EXIT_CODE=$?
assert_eq "implement" "$(get_phase)" "hard gate: phase stays implement when milestones incomplete"
assert_eq "1" "$EXIT_CODE" "hard gate: set_phase returns exit code 1"
```

- [ ] **Step 4: Run full test suite**

Run: `bash tests/run-tests.sh`
Expected: All tests pass including new hard gate test

- [ ] **Step 5: Commit**

```bash
git add plugin/scripts/workflow-state.sh tests/run-tests.sh
echo "========== YUBIKEY: TOUCH NOW FOR GIT COMMIT ==========" && git commit -m "$(cat <<'EOF'
fix: hard gate bypass — set_phase now stops execution on milestone failure

The hard gate check printed an error but didn't prevent the phase
from being set. Fixed to properly return before writing state.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 21: Final Verification

- [ ] **Step 1: Run full test suite one final time**

Run: `bash tests/run-tests.sh`
Expected: All tests pass, count is baseline + new tests

- [ ] **Step 2: Verify all spec outcomes**

Run each verification command from the spec's Outcomes section:
```bash
# 1. No ${VAR^^} patterns
grep -c '\${.*\^\^}' plugin/scripts/post-tool-navigator.sh 2>/dev/null || echo "0"
# Expected: 0

# 2. extract_bash_command usage
grep -c 'extract_bash_command' plugin/scripts/post-tool-navigator.sh
# Expected: 5+

# 3. Named pattern fragments
grep -cE '_OPS|_EDITORS|_WRITERS|_REDIRECT|HEREDOCS|EXEC_WRAPPERS' plugin/scripts/bash-write-guard.sh
# Expected: 12+

# 4. Single jq call
grep -c 'echo "\$DATA" | jq' plugin/statusline/statusline.sh
# Expected: 1

# 5. Allowlist blocks private helpers
plugin/scripts/workflow-cmd.sh _reset_section test 2>&1 | grep -c "ERROR"
# Expected: 1

# 6. Version sync
bash scripts/check-version-sync.sh
# Expected: "All versions in sync"
```

- [ ] **Step 3: Verify git log shows clean commit history**

Run: `git log --oneline -5`
Expected: Clean commits (spec, phase 1, phase 2-3, tests, bug fixes)
