# Workflow Manager Rework — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rework the ClaudeWorkflows phase model to add COMPLETE phase, rename /approve to /implement, remove /override, add coaching system, consolidate state into single file, and add professional standards.

**Architecture:** Shell-based hook system (PreToolUse/PostToolUse) with markdown command files driving Claude behavior. Single `workflow.json` state file replaces three separate files. Three-layer coaching system in PostToolUse hook.

**Tech Stack:** Bash (hooks/state), Markdown (commands), Python3 (JSON manipulation in hooks), jq (statusline)

**Spec:** `docs/superpowers/specs/2026-03-20-workflow-rework-design.md`

---

## Task 1: Rewrite workflow-state.sh — Single State File + New API

**Files:**
- Modify: `.claude/hooks/workflow-state.sh` (full rewrite)
- Test: `tests/run-tests.sh` (state management tests will be updated in Task 7)

This is the foundation — everything else depends on it.

- [ ] **Step 1: Backup the current file for reference**

```bash
cp .claude/hooks/workflow-state.sh .claude/hooks/workflow-state.sh.bak
```

- [ ] **Step 2: Write the new workflow-state.sh**

Rewrite `.claude/hooks/workflow-state.sh` with:
- `STATE_FILE` points to `workflow.json` (not `phase.json`)
- `RESTRICTED_WRITE_WHITELIST` regex (for DEFINE/DISCUSS): `(\.claude/state/|docs/superpowers/specs/|docs/superpowers/plans/|docs/plans/)`
- `COMPLETE_WRITE_WHITELIST` regex (for COMPLETE): `(\.claude/state/|docs/|^[^/]*\.md$)`
- Note: `.claude/hooks/` is deliberately removed from all whitelists (security fix)
- `get_phase()` — reads from `workflow.json` using grep, returns "off" if file missing
- `set_phase(new_phase)` — validates against: `off|define|discuss|implement|review|complete`. Writes full `workflow.json` with `phase`, `message_shown: false`, preserves `active_skill`, `decision_record`. Cleans up `review` sub-object when leaving review. Resets `coaching` sub-object (new phase = fresh coaching state).
- `get_message_shown()` / `set_message_shown()` — same logic, reads/writes `workflow.json`
- `set_active_skill(name)` / `get_active_skill()` — reads/writes `active_skill` field in `workflow.json`
- `set_decision_record(path)` / `get_decision_record()` — reads/writes `decision_record` field in `workflow.json`
- `check_soft_gate(target_phase)` — checks preconditions for target phase:
  - `implement`: checks if any `*-decisions.md` or plan file exists in `docs/superpowers/plans/` or `docs/plans/`. If not: returns warning.
  - `review`: checks if `git diff --name-only main...HEAD` or `git diff --name-only` returns anything. If not: returns warning.
  - `complete`: checks if `review` sub-object exists in `workflow.json` with `findings_acknowledged=true`. If not: returns warning.
  - All others: returns empty string (no gate).
- `reset_review_status()` — writes `review` sub-object into `workflow.json`. Note: `verification_skipped` field is intentionally dropped per spec (was in old review-status.json but not in new schema). Tests referencing it will be updated in Task 7.
- `get_review_field(field)` / `set_review_field(field, value)` — reads/writes within `review` sub-object of `workflow.json`
- `increment_coaching_counter()` — increments `coaching.tool_calls_since_agent`, creates coaching sub-object if missing
- `reset_coaching_counter()` — resets `coaching.tool_calls_since_agent` to 0
- `add_coaching_fired(trigger_type)` — appends to `coaching.layer2_fired` array
- `has_coaching_fired(trigger_type)` — checks if trigger_type is in `coaching.layer2_fired` array

Keep the copyright header. Keep `set -euo pipefail` out (it's a sourced library, not standalone). Use python3 for JSON manipulation (consistent with current approach).

- [ ] **Step 3: Verify the rewrite loads without syntax errors**

```bash
bash -n .claude/hooks/workflow-state.sh
```
Expected: no output (clean parse)

- [ ] **Step 4: Quick smoke test — set and get phase**

```bash
cd /tmp && mkdir -p test-wf/.claude/state && cd test-wf
export CLAUDE_PROJECT_DIR=/tmp/test-wf
source .claude/hooks/workflow-state.sh  # (copy from project first)
set_phase "discuss"
echo "Phase: $(get_phase)"
echo "Message shown: $(get_message_shown)"
cat .claude/state/workflow.json
```
Expected: Phase is "discuss", message_shown is "false", workflow.json has valid JSON structure with all fields.

- [ ] **Step 5: Smoke test — active skill and decision record**

```bash
set_active_skill "brainstorming"
echo "Skill: $(get_active_skill)"
set_decision_record "docs/plans/2026-03-20-test-decisions.md"
echo "Record: $(get_decision_record)"
cat .claude/state/workflow.json
```
Expected: Both fields present in workflow.json.

- [ ] **Step 6: Smoke test — soft gates**

```bash
# Should warn (no plan file)
WARN=$(check_soft_gate "implement")
echo "Implement gate: '$WARN'"
# Should not warn (no gate for discuss)
WARN=$(check_soft_gate "discuss")
echo "Discuss gate: '$WARN'"
```
Expected: implement gate returns a warning string, discuss gate returns empty.

- [ ] **Step 7: Smoke test — review status in workflow.json**

```bash
set_phase "review"
reset_review_status
get_review_field "verification_complete"
set_review_field "verification_complete" "true"
get_review_field "verification_complete"
cat .claude/state/workflow.json
```
Expected: review sub-object present in workflow.json with fields.

- [ ] **Step 8: Developer migration — create workflow.json from existing state**

If `.claude/state/phase.json` exists in the working tree, migrate it to `workflow.json`:
```bash
if [ -f .claude/state/phase.json ]; then
    CURRENT_PHASE=$(python3 -c "import json; d=json.load(open('.claude/state/phase.json')); print(d.get('phase','off'))")
    CURRENT_SKILL=$(python3 -c "import json; d=json.load(open('.claude/state/active-skill.json')); print(d.get('skill',''))" 2>/dev/null || echo "")
    source .claude/hooks/workflow-state.sh
    set_phase "$CURRENT_PHASE"
    if [ -n "$CURRENT_SKILL" ]; then
        set_active_skill "$CURRENT_SKILL"
    fi
    echo "Migrated to workflow.json (phase=$CURRENT_PHASE, skill=$CURRENT_SKILL)"
fi
```
This ensures the developer's own working tree works with the new code immediately.

- [ ] **Step 9: Clean up backup and temp files**

```bash
rm -f .claude/hooks/workflow-state.sh.bak
rm -rf /tmp/test-wf
```

- [ ] **Step 10: Commit**

```bash
git add .claude/hooks/workflow-state.sh
git commit -m "refactor: rewrite workflow-state.sh for single workflow.json state file

Consolidate phase.json, active-skill.json, and review-status.json into
single workflow.json. Add new API functions: set_active_skill,
set_decision_record, check_soft_gate, coaching counter helpers.
Remove .claude/hooks/ from write whitelists (security fix).
Add COMPLETE_WRITE_WHITELIST for docs-allowed tier.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Update Gate Hooks — COMPLETE Phase + Whitelist Tiers

**Files:**
- Modify: `.claude/hooks/workflow-gate.sh`
- Modify: `.claude/hooks/bash-write-guard.sh`

- [ ] **Step 1: Update workflow-gate.sh**

Changes to `.claude/hooks/workflow-gate.sh`:
1. Update header comment to include COMPLETE phase
2. Update whitelisted-paths comments to mention tiers
3. Replace `$DISCUSS_WRITE_WHITELIST` with `$RESTRICTED_WRITE_WHITELIST` in the whitelist check line
4. Replace the `if [ "$PHASE" != "discuss" ] && [ "$PHASE" != "define" ]` block with a three-way branch:
   - If phase is `implement`, `review`, or `off` → allow (exit 0)
   - If phase is `define` or `discuss` → use `RESTRICTED_WRITE_WHITELIST`
   - If phase is `complete` → use `COMPLETE_WRITE_WHITELIST`
5. Lines 52-56: update deny messages:
   - DEFINE: keep current message but change "/discuss" suggestion to just say "Define the problem first."
   - DISCUSS: change "Use /approve" to "Use /implement"
   - COMPLETE (new): "BLOCKED: Phase is COMPLETE. Code changes are not allowed during completion. Only documentation updates are permitted."

- [ ] **Step 2: Verify workflow-gate.sh parses cleanly**

```bash
bash -n .claude/hooks/workflow-gate.sh
```

- [ ] **Step 3: Update bash-write-guard.sh**

Same pattern of changes as workflow-gate.sh:
1. Update header comments
2. Replace `$DISCUSS_WRITE_WHITELIST` with `$RESTRICTED_WRITE_WHITELIST` and add COMPLETE tier branch
3. Replace the `if [ "$PHASE" != "discuss" ] && [ "$PHASE" != "define" ]` block with three-way branch (same as gate hook)
4. Update deny messages (same as gate hook, add COMPLETE message, change "Use /approve" to "Use /implement")
5. Update the workflow state command whitelist to the complete set: `(workflow-state\.sh|set_phase|get_phase|reset_review_status|[sg]et_review_field|[sg]et_active_skill|[sg]et_decision_record|check_soft_gate|increment_coaching_counter|reset_coaching_counter|add_coaching_fired|has_coaching_fired)`

- [ ] **Step 4: Verify bash-write-guard.sh parses cleanly**

```bash
bash -n .claude/hooks/bash-write-guard.sh
```

- [ ] **Step 5: Commit**

```bash
git add .claude/hooks/workflow-gate.sh .claude/hooks/bash-write-guard.sh
git commit -m "feat: add COMPLETE phase edit-blocking with docs-allowed whitelist tier

workflow-gate.sh and bash-write-guard.sh now handle three edit-blocking
tiers: Restrictive (DEFINE/DISCUSS), Docs-allowed (COMPLETE), and
Open (IMPLEMENT/REVIEW). Update deny messages to reference /implement.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Rewrite post-tool-navigator.sh — Three-Layer Coaching System

**Files:**
- Modify: `.claude/hooks/post-tool-navigator.sh` (major rewrite)

- [ ] **Step 1: Write the new post-tool-navigator.sh**

Rewrite `.claude/hooks/post-tool-navigator.sh` with three layers:

**Layer 1 — Phase entry (fires once when message_shown is false):**
- Same trigger as current: check `get_message_shown`, if "true" skip to Layer 2/3
- IMPLEMENT phase special rule: only fire on Write/Edit/MultiEdit/NotebookEdit/Bash (keep current behavior)
- New messages per phase (from spec Section 5):
  - `define`: "[Workflow Coach — DEFINE] Objective: Frame the problem and define measurable outcomes..."
  - `discuss`: "[Workflow Coach — DISCUSS] Objective: Research solution approaches..."
  - `implement`: "[Workflow Coach — IMPLEMENT] Objective: Build the chosen solution..."
  - `review`: "[Workflow Coach — REVIEW] Objective: Independent multi-agent validation..."
  - `complete`: "[Workflow Coach — COMPLETE] Objective: Verify outcomes were met..."
  - `off`: exit (no coaching)
- Call `set_message_shown` after emitting

**Layer 2 — Professional standards reinforcement (fires periodically):**
- Only runs if `message_shown` is true (Layer 1 already fired)
- Increment `coaching.tool_calls_since_agent` counter via `increment_coaching_counter`
- If tool_name is "Agent", call `reset_coaching_counter`
- Check phase + tool pattern against trigger table (from spec Section 5)
- Before firing, check `has_coaching_fired(trigger_type)` — skip if already fired this phase
- After firing, call `add_coaching_fired(trigger_type)`
- Trigger types: `agent_return`, `no_agent_dispatch`, `plan_write`, `source_edit`, `test_run`, `findings_present`, `decision_record_edit`
- Messages prefixed with `[Workflow Coach — PHASE]`

**Layer 3 — Anti-laziness checks (fires on every match):**
- Short agent prompts: if tool_name is "Agent", extract `prompt` from tool_input, check length < 150
- Generic commit messages: if tool_name is "Bash", check if command contains `git commit -m` with message < 30 chars
- Skipping research: if phase is define/discuss and `coaching.tool_calls_since_agent` > 10
- Options without recommendation: best-effort heuristic — if tool_name is "AskUserQuestion", check if prior tool calls in this phase included Agent returns but no recommendation language. Flag as best-effort in code comments.
- All findings downgraded: if phase is review and tool_name is "Write" or "Edit" targeting the decision record, read the Review Findings section and check if all entries are under "Suggestions" heading with no Critical or Warning entries
- Minimal handover: if phase is complete and tool_name matches claude-mem MCP save_observation, check if observation text < 200 chars
- Messages prefixed with `[Workflow Coach — PHASE]`

**Note:** PostToolUse hooks receive both `tool_name` and `tool_input` fields in stdin JSON, so all Layer 2/3 checks have the data they need.

**Output format:** Same hookSpecificOutput/systemMessage JSON as current.

**Important:** Layer 2 and 3 messages are returned as systemMessage even when Layer 1 has already fired. Multiple layers can fire on the same tool call — combine messages with newlines if needed.

- [ ] **Step 2: Verify it parses cleanly**

```bash
bash -n .claude/hooks/post-tool-navigator.sh
```

- [ ] **Step 3: Commit**

```bash
git add .claude/hooks/post-tool-navigator.sh
git commit -m "feat: implement three-layer coaching system in post-tool-navigator

Layer 1: Phase entry messages with objectives and done criteria.
Layer 2: Professional standards reinforcement on contextual tool patterns.
Layer 3: Anti-laziness checks for short prompts, generic commits, skipped research.
All messages prefixed with [Workflow Coach — PHASE] for user visibility.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Create implement.md + Delete approve.md and override.md

**Files:**
- Create: `.claude/commands/implement.md`
- Delete: `.claude/commands/approve.md`
- Delete: `.claude/commands/override.md`

- [ ] **Step 1: Create implement.md**

Write `.claude/commands/implement.md` — direct phase jump to IMPLEMENT with soft gate.

Content structure:
1. Run soft gate check via bash: `check_soft_gate "implement"`. If warning returned, show it and ask user to confirm.
2. Set phase to implement via `set_phase "implement"` and `set_active_skill ""`
3. Confirm phase changed, code edits now allowed
4. Instructions: read `docs/reference/professional-standards.md` (IMPLEMENT section), use `superpowers:executing-plans` + `superpowers:test-driven-development`
5. Active skill tracker update pattern using `set_active_skill`

All bash calls use the new `workflow.json`-based API (no direct file writes to active-skill.json).

- [ ] **Step 2: Delete approve.md**

```bash
git rm .claude/commands/approve.md
```

- [ ] **Step 3: Delete override.md**

```bash
git rm .claude/commands/override.md
```

- [ ] **Step 4: Commit**

```bash
git add .claude/commands/implement.md
git commit -m "feat: add /implement command, remove /approve and /override

/implement replaces /approve with soft gate (warns if no plan exists).
/override removed — all /phase commands are now direct jumps.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: Rewrite Command Files — define.md, discuss.md, review.md, complete.md

**Files:**
- Modify: `.claude/commands/define.md` (rewrite)
- Modify: `.claude/commands/discuss.md` (rewrite)
- Modify: `.claude/commands/review.md` (update)
- Modify: `.claude/commands/complete.md` (rewrite)

### 5a: Rewrite define.md

- [ ] **Step 1: Rewrite define.md**

New structure for `.claude/commands/define.md`:
1. Bash block: `set_phase "define"`, `set_active_skill ""`. No soft gate (DEFINE has none).
2. Confirm phase changed, code edits blocked.
3. Instruct: "Read `docs/reference/professional-standards.md` (Universal + DEFINE sections) and apply."
4. Use `superpowers:brainstorming` with **problem-discovery context** framing:
   - Focus on: who's affected, what pain, current state, why now
   - This is Diamond 1 (Problem Space) — diverge on understanding, converge on problem statement
5. **Diverge phase:** After 2-3 exchanges when initial framing emerges, dispatch background agents:
   - Domain researcher (WebSearch for problem domain)
   - Context gatherer (claude-mem, git log for prior work)
   - Assumption challenger (counterevidence, edge cases)
   - Dispatch condition: skip if trivial, state explicitly
6. **Converge phase:** After user agrees on framing, dispatch:
   - Outcome structurer (measurable outcomes, verification methods)
   - Scope boundary checker (in/out scope, constraints)
7. Create decision record at `docs/plans/YYYY-MM-DD-<topic>-decisions.md` with Problem section populated
8. Call `set_decision_record(path)` with the created file path
9. Active skill tracker: `set_active_skill "brainstorming"` when invoking skill

- [ ] **Step 2: Verify define.md is well-formed markdown**

Read the file back and check for broken syntax, unclosed code blocks, etc.

### 5b: Rewrite discuss.md

- [ ] **Step 3: Rewrite discuss.md**

New structure for `.claude/commands/discuss.md`:
1. Bash block: `set_phase "discuss"`, `set_active_skill ""`. No soft gate.
2. Confirm phase changed, code edits blocked.
3. Instruct: "Read `docs/reference/professional-standards.md` (Universal + DISCUSS sections) and apply."
4. If no decision record exists yet (check `get_decision_record`), create one and set it. Brainstorming will naturally cover problem discovery.
5. Use `superpowers:brainstorming` with **solution-design context** framing:
   - Focus on: how to solve the defined problem, what approaches exist
   - This is Diamond 2 (Solution Space) — diverge on possibilities, converge through analysis
6. **Diverge phase:** Dispatch background agents:
   - Solution researcher A (web search for approaches)
   - Solution researcher B (case studies, lessons learned)
   - Prior art scanner (claude-mem, codebase)
   - Dispatch condition: skip if obvious, state explicitly
7. **Converge phase:** After narrowing to 2-3 candidates, dispatch:
   - Codebase analyst (architecture fit)
   - Risk assessor (breaking changes, security, tech debt)
8. Enrich decision record: Approaches Considered + Decision sections
9. Use `superpowers:writing-plans` to create implementation plan
10. Active skill tracker updates throughout

- [ ] **Step 4: Verify discuss.md is well-formed**

### 5c: Update review.md

- [ ] **Step 5: Update review.md**

Changes to `.claude/commands/review.md`:
1. Remove the hard gate that blocks from non-implement phases. Replace with: `set_phase "review"` as a direct jump. Add soft gate check: `check_soft_gate "review"` — if warning, show it, ask user to confirm.
2. Update all `set_review_field` calls to use the new API (same function names, they now write to workflow.json internally).
3. Remove references to `$STATE_DIR/active-skill.json` — use `set_active_skill "review-pipeline"` instead.
4. **Add Step 5 enhancement:** After presenting consolidated findings, write them to the decision record's Review Findings section. Read `get_decision_record` for the path. If no decision record exists, skip this step and note it.
5. Remove references to `/approve` — change "Use /approve first" to just explain the soft gate.

- [ ] **Step 6: Verify review.md is well-formed**

### 5d: Rewrite complete.md

- [ ] **Step 7: Rewrite complete.md**

Full rewrite of `.claude/commands/complete.md`:
1. Bash block: `set_phase "complete"`, `set_active_skill "completion-pipeline"`.
2. Soft gate: `check_soft_gate "complete"` — if warning, show "Review hasn't been run. The workflow should be followed for best results. Proceed anyway?" Wait for user.
3. Instruct: "Read `docs/reference/professional-standards.md` (Universal + COMPLETE sections) and apply."
4. Pipeline (from spec Section 3, COMPLETE):
   - Step 1: Plan validator agent — read plan file (from `get_decision_record` to find related plan), verify deliverables. Skip if no plan.
   - Step 2: Outcome validator agent — read decision record Problem section, verify outcomes with behavioral evidence. Skip if no Problem section.
   - Step 3: Present validation results. On failure: specific diagnosis, quantified fix effort, recommended next phase.
   - Step 4: Docs detector agent — scan changes, recommend doc/README updates.
   - Step 5: User approves doc updates, orchestrator applies them.
   - Step 6: Commit & Push — same pattern as current (YubiKey banner, user confirms push).
   - Step 7: Handover writer agent — claude-mem observation.
   - Step 8: Phase transition to OFF via `set_phase "off"`.
5. Remove all references to `review-status.json` direct access — use API functions.
6. Remove references to `define.json` — validators read decision record markdown. No backward compatibility: if a user has `define.json` but no decision record, the validators skip outcome validation (consistent with spec Section 6 "Backward Compatibility: None").
7. Enrich decision record with Outcome Verification section.

- [ ] **Step 8: Verify complete.md is well-formed**

- [ ] **Step 9: Commit all command files**

```bash
git add .claude/commands/define.md .claude/commands/discuss.md .claude/commands/review.md .claude/commands/complete.md
git commit -m "feat: rewrite command files for reworked workflow

define.md: brainstorming skill with problem-discovery context, diverge/converge agents, decision record.
discuss.md: brainstorming skill with solution context, diverge/converge agents, writing-plans.
review.md: direct jump with soft gate, persist findings to decision record.
complete.md: proper COMPLETE phase with soft gate, validation pipeline, docs-allowed edits.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: Create Professional Standards Document

**Files:**
- Create: `docs/reference/professional-standards.md`

- [ ] **Step 1: Write professional-standards.md**

Copy the full professional standards content from spec Section 4 into `docs/reference/professional-standards.md`. This is the source of truth for human reference and orchestrator phase-entry loading.

Include all sections:
- OFF phase note
- Universal Standards (all phases)
- DEFINE Phase Standards
- DISCUSS Phase Standards
- IMPLEMENT Phase Standards
- REVIEW Phase Standards
- COMPLETE Phase Standards

- [ ] **Step 2: Commit**

```bash
git add docs/reference/professional-standards.md
git commit -m "docs: add professional standards for workflow coaching system

Defines behavioral expectations per phase: evidence before assertions,
trade-offs stated explicitly, challenge don't confirm, tech debt visible.
Referenced by command files and distilled into coaching hook messages.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: Update Test Suite

**Files:**
- Modify: `tests/run-tests.sh` (major update)

This task updates the existing 124 tests and adds new ones. Read the full test file first to understand all existing test sections.

- [ ] **Step 1: Read the full current test file**

Read `tests/run-tests.sh` completely to understand all test sections and patterns.

- [ ] **Step 2: Update state file references**

Throughout the test file:
- Replace all references to `phase.json` with `workflow.json`
- Replace all references to `review-status.json` with reading the `review` sub-object from `workflow.json`
- Replace all references to `active-skill.json` with reading `active_skill` from `workflow.json`
- Replace all direct `cat > ... phase.json` test setup with calls to `set_phase` or writing `workflow.json`

- [ ] **Step 3: Rename /approve references to /implement**

- Update test descriptions mentioning `/approve`
- Update any test that checks for "/approve" in deny messages
- Update the deny message assertion for DISCUSS phase: "Use /approve" → "Use /implement"
- Update install.sh test assertions: replace `approve.md` with `implement.md`, remove `override.md` install check
- Update uninstall.sh test assertions similarly
- Remove test for `verification_skipped` field (dropped per spec)

- [ ] **Step 4: Remove /override tests**

Delete test cases that specifically test `/override` behavior. These are no longer needed since every `/phase` command is a direct jump.

- [ ] **Step 5: Add COMPLETE phase to valid phases test**

Update the `set_phase` validation test to include "complete" as a valid phase.

- [ ] **Step 6: Add COMPLETE phase edit-blocking tests**

New test section: "COMPLETE phase edit-blocking"
- Test that Write/Edit to source code is blocked in COMPLETE phase
- Test that Write/Edit to `docs/` paths is allowed in COMPLETE phase
- Test that Write/Edit to root `*.md` files is allowed in COMPLETE phase
- Test that Write/Edit to `.claude/state/` is allowed in COMPLETE phase
- Test that Write/Edit to `.claude/hooks/` is BLOCKED in COMPLETE phase (security fix)
- Test that Write/Edit to root-level `*.md` files (e.g., `README.md`, `CONTRIBUTING.md`) is allowed in COMPLETE phase
- Test Bash write operations follow the same whitelist tiers

- [ ] **Step 7: Add soft gate tests**

New test section: "Soft gate checks"
- Test `check_soft_gate "implement"` returns warning when no plan file exists
- Test `check_soft_gate "implement"` returns empty when plan file exists
- Test `check_soft_gate "review"` returns warning when git diff is clean
- Test `check_soft_gate "complete"` returns warning when review not done
- Test `check_soft_gate "complete"` returns empty when review acknowledged
- Test `check_soft_gate "discuss"` always returns empty

- [ ] **Step 8: Add workflow.json structure tests**

New test section: "workflow.json state management"
- Test `set_phase` creates valid workflow.json with all required fields
- Test `set_active_skill` / `get_active_skill` round-trip
- Test `set_decision_record` / `get_decision_record` round-trip
- Test `set_phase "review"` + `reset_review_status` creates review sub-object
- Test leaving review phase cleans up review sub-object
- Test coaching sub-object resets on phase change

- [ ] **Step 9: Add coaching system tests**

New test section: "Coaching system"

**Layer 1 tests:**
- Test Layer 1: phase entry message fires once (message_shown = false → fires, then true → silent)
- Test Layer 1: COMPLETE phase gets a coaching message with "[Workflow Coach — COMPLETE]" prefix
- Test Layer 1: OFF phase produces no coaching message

**Layer 2 tests (state primitives):**
- Test coaching counter increments on tool calls
- Test coaching counter resets on Agent tool call
- Test `has_coaching_fired` / `add_coaching_fired` track trigger types independently
- Test coaching state resets on phase transition

**Layer 2 tests (integration):**
- Test: Layer 2 fires standards message after Agent tool returns in DEFINE phase (simulate by providing Agent tool_name in stdin JSON while in define phase with message_shown=true)
- Test: Layer 2 does NOT re-fire the same trigger type in the same phase
- Test: Layer 2 fires different trigger types independently in the same phase
- Test: Layer 2 fires standards message after Write/Edit to source code in IMPLEMENT phase

**Layer 3 tests (anti-laziness):**
- Test: Short agent prompt (< 150 chars) triggers a "[Workflow Coach]" warning
- Test: Normal agent prompt (>= 150 chars) does NOT trigger warning
- Test: Generic commit message (< 30 chars) triggers warning
- Test: `tool_calls_since_agent > 10` in DEFINE/DISCUSS phase triggers skipping-research warning

**Note:** Command-file integration with soft gates is not testable in the shell test suite — validated during manual E2E testing in Task 11.

- [ ] **Step 10: Add whitelist security test**

New test: verify `.claude/hooks/` is NOT in any whitelist
- Test that writing to `.claude/hooks/somefile.sh` is blocked in DEFINE phase
- Test that writing to `.claude/hooks/somefile.sh` is blocked in DISCUSS phase
- Test that writing to `.claude/hooks/somefile.sh` is blocked in COMPLETE phase

- [ ] **Step 11: Run the full test suite**

```bash
bash tests/run-tests.sh
```
Expected: All tests pass. Note the new test count.

- [ ] **Step 12: Commit**

```bash
git add tests/run-tests.sh
git commit -m "test: update suite for workflow rework — COMPLETE phase, coaching, soft gates

Update /approve refs to /implement. Remove /override tests.
Add COMPLETE phase edit-blocking tests with docs-allowed tier.
Add soft gate tests. Add workflow.json structure tests.
Add coaching system tests. Add whitelist security tests.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 8: Update Statusline

**Files:**
- Modify: `statusline/statusline.sh`

- [ ] **Step 1: Update state file paths**

In `statusline/statusline.sh`:
- Line 100: change `WM_STATE_FILE` from `phase.json` to `workflow.json`
- Lines 125-134: change `ACTIVE_SKILL_FILE` to read from `workflow.json` instead of `active-skill.json`. Extract `active_skill` field from the same JSON file as the phase.

- [ ] **Step 2: Add COMPLETE phase color**

After the REVIEW elif block (line 116), add:
```bash
elif [ "$WM_PHASE" = "complete" ]; then
    OUTPUT+=" ${MAGENTA}[COMPLETE]${RESET}"
```

- [ ] **Step 3: Verify statusline renders**

```bash
echo '{"model":{"display_name":"Test"},"context_window":{"used_percentage":50,"current_usage":{"input_tokens":500000},"context_window_size":1000000},"cwd":"/tmp"}' | bash statusline/statusline.sh
```
Expected: renders without errors.

- [ ] **Step 4: Commit**

```bash
git add statusline/statusline.sh
git commit -m "feat: add COMPLETE phase to statusline, read from workflow.json

Add magenta [COMPLETE] display. Update state file paths from
phase.json and active-skill.json to consolidated workflow.json.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 9: Update Documentation

**Files:**
- Modify: `README.md`
- Modify: `docs/reference/architecture.md`
- Modify: `docs/reference/hooks.md`
- Modify: `docs/quick-reference/commands.md`
- Modify: `docs/guides/getting-started.md`
- Modify: `CONTRIBUTING.md`
- Modify: `claude.md.template`

- [ ] **Step 1: Update README.md**

- Update the Mermaid diagram to show the happy path as reality (no longer "target state"). Remove the note about `/implement` being planned.
- Update the command table: remove `/approve` and `/override`, add `/implement`. Add COMPLETE phase description.
- Update any phase descriptions to include COMPLETE.
- Update the "Note" about the diagram to: "This is the recommended path. Any `/phase` command can jump directly to any phase. Soft gates warn when skipping recommended steps."

- [ ] **Step 2: Update docs/reference/architecture.md**

- Update phase model diagram: add COMPLETE phase, remove /approve references.
- Update state management section: describe workflow.json (single file).
- Update transition rules: direct jumps, soft gates.
- Add coaching system description.

- [ ] **Step 3: Update docs/reference/hooks.md**

- Update hook descriptions to include coaching system.
- Document the three layers (phase entry, standards reinforcement, anti-laziness).
- Update workflow-gate.sh description to include COMPLETE phase and whitelist tiers.
- Update bash-write-guard.sh description similarly.

- [ ] **Step 4: Update docs/quick-reference/commands.md**

- Replace `/approve` row with `/implement`
- Remove `/override` row
- Add notes about soft gates on applicable commands

- [ ] **Step 5: Update docs/guides/getting-started.md**

- Update workflow walkthrough: `/approve` → `/implement`
- Add COMPLETE phase to the flow description
- Remove `/override` mentions

- [ ] **Step 6: Update CONTRIBUTING.md**

- Update any workflow command references
- Replace `/approve` with `/implement`

- [ ] **Step 7: Update claude.md.template**

- Update phase references and command names
- Replace `/approve` with `/implement`
- Remove `/override` references

- [ ] **Step 8: Commit all docs**

```bash
git add README.md docs/reference/architecture.md docs/reference/hooks.md docs/quick-reference/commands.md docs/guides/getting-started.md CONTRIBUTING.md claude.md.template
git commit -m "docs: update all documentation for workflow rework

Replace /approve with /implement throughout. Remove /override references.
Add COMPLETE phase. Document coaching system. Update Mermaid diagram
to match implementation. Describe soft gates and whitelist tiers.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 10: Update Installer + Uninstaller

**Files:**
- Modify: `install.sh`
- Modify: `uninstall.sh`

- [ ] **Step 1: Update install.sh**

- Update usage message: replace `/approve` with `/implement`, add `/complete` description
- Add `docs/reference/professional-standards.md` to the list of installed files
- Add migration logic: if `phase.json` exists, read old state files, write consolidated `workflow.json`, delete old files
- If `approve.md` exists in target, delete it
- If `override.md` exists in target, delete it
- Update `implement.md` as the file to install (not `approve.md`)

- [ ] **Step 2: Update uninstall.sh**

- Clean up `workflow.json` instead of the three old state files
- Remove `implement.md` (not `approve.md`) from cleanup list
- Remove `override.md` from cleanup list
- Add `professional-standards.md` to cleanup list

- [ ] **Step 3: Verify install.sh syntax**

```bash
bash -n install.sh
```

- [ ] **Step 4: Verify uninstall.sh syntax**

```bash
bash -n uninstall.sh
```

- [ ] **Step 5: Commit**

```bash
git add install.sh uninstall.sh
git commit -m "feat: update installer with migration logic and new file list

Add workflow.json migration from old state files. Install implement.md
and professional-standards.md. Remove approve.md and override.md on
upgrade. Update usage message with new command names.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 11: Final Integration Test + Cleanup

**Files:**
- All modified files (integration test)

- [ ] **Step 1: Run the full test suite**

```bash
bash tests/run-tests.sh
```
Expected: All tests pass. Note the total count (target: 155-170).

- [ ] **Step 2: Verify no stale references to old files/commands**

```bash
# Search for /approve references (should find 0 in code, may find in git history/specs)
grep -r "/approve" .claude/ docs/ tests/ install.sh uninstall.sh statusline/ README.md CONTRIBUTING.md claude.md.template --include="*.sh" --include="*.md" --include="*.json" | grep -v "\.git/" | grep -v "specs/" | grep -v "plans/"

# Search for /override references
grep -r "/override" .claude/ docs/ tests/ install.sh uninstall.sh statusline/ README.md CONTRIBUTING.md claude.md.template --include="*.sh" --include="*.md" --include="*.json" | grep -v "\.git/" | grep -v "specs/" | grep -v "plans/"

# Search for phase.json direct references (should be 0 — everything uses workflow.json)
grep -r "phase\.json" .claude/ tests/ statusline/ install.sh uninstall.sh --include="*.sh" | grep -v "\.git/" | grep -v "\.bak"

# Search for active-skill.json direct references
grep -r "active-skill\.json" .claude/ tests/ statusline/ install.sh uninstall.sh --include="*.sh" | grep -v "\.git/" | grep -v "\.bak"

# Search for review-status.json direct references
grep -r "review-status\.json" .claude/ tests/ statusline/ install.sh uninstall.sh --include="*.sh" | grep -v "\.git/" | grep -v "\.bak"
```
Expected: No matches in active code (specs/plans may reference old names in historical context, that's fine).

- [ ] **Step 3: Verify all files have trailing newlines**

```bash
for f in .claude/hooks/*.sh .claude/commands/*.md statusline/statusline.sh install.sh uninstall.sh; do
    if [ -f "$f" ] && [ -n "$(tail -c1 "$f")" ]; then
        echo "Missing trailing newline: $f"
    fi
done
```
Expected: No output (all files have trailing newlines).

- [ ] **Step 4: Delete old state files if they exist in the working tree**

```bash
rm -f .claude/state/phase.json .claude/state/active-skill.json .claude/state/review-status.json
```

- [ ] **Step 5: Clean up any .bak files**

```bash
find . -name "*.bak" -delete
```

- [ ] **Step 6: Final commit if any cleanup was needed**

Only if steps 2-5 produced changes:
```bash
git add -A
git commit -m "chore: clean up stale references and old state files

Remove remaining references to /approve, /override, phase.json,
active-skill.json, and review-status.json from active code.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Summary

| Task | Description | Dependencies | Estimated Steps |
|------|-------------|-------------|-----------------|
| 1 | Rewrite workflow-state.sh | None | 10 |
| 2 | Update gate hooks | Task 1 | 5 |
| 3 | Rewrite coaching system | Tasks 1, 2 (runtime) | 3 |
| 4 | Create implement.md, delete approve.md/override.md | Task 1 | 4 |
| 5 | Rewrite command files | Tasks 1, 4, 6 | 9 |
| 6 | Create professional standards | None | 2 |
| 7 | Update test suite | Tasks 1-6 | 12 |
| 8 | Update statusline | Task 1 | 4 |
| 9 | Update documentation | Tasks 1-6 | 8 |
| 10 | Update installer | Tasks 1-6 | 5 |
| 11 | Integration test + cleanup | All | 6 |

**Parallelizable:** Tasks 1 and 6 can run in parallel (no shared dependencies). Tasks 2, 4, 8 can run in parallel after Task 1. Task 3 depends on Task 2 at runtime (bash-write-guard whitelist must include coaching functions). Task 5 depends on Task 6 (command files reference professional-standards.md). Tasks 7, 9, 10 should run after all code changes are complete.

**Total steps:** 68
**Total commits:** 11
