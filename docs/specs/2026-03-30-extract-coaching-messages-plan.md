# Extract Coaching Messages Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract all inline coaching messages from `post-tool-navigator.sh` into individual `.md` files under `plugin/coaching/`, loaded at runtime via a `load_message` helper.

**Architecture:** Create a `plugin/coaching/` directory tree mirroring the three-layer coaching system (objectives, nudges, checks, auto-transition). Add a `load_message()` function to the script that reads files by path and substitutes `{{PHASE}}`. Replace every inline message string with a `load_message` call. Normalize inconsistent trigger names to always include phase suffixes.

**Tech Stack:** Bash, `cat`, `sed` for template substitution. No new dependencies.

**Spec:** `docs/plans/2026-03-30-extract-coaching-messages.md`

---

## File Structure

### New files (45 `.md` message files)

```
plugin/coaching/
├── objectives/           # Layer 1: phase entry (6 files)
│   ├── define.md
│   ├── discuss.md
│   ├── implement.md
│   ├── review.md
│   ├── complete.md
│   └── error.md
├── nudges/               # Layer 2: contextual reminders (11 files)
│   ├── agent_return_define.md
│   ├── plan_write_define.md
│   ├── agent_return_discuss.md
│   ├── plan_write_discuss.md
│   ├── source_edit_implement.md
│   ├── test_run_implement.md
│   ├── agent_return_review.md
│   ├── findings_present_review.md
│   ├── agent_return_complete.md
│   ├── project_docs_edit_complete.md
│   └── test_run_complete.md
├── checks/               # Layer 3: anti-laziness (8 + 3 + 13 = 24 files)
│   ├── short_agent_prompt.md
│   ├── generic_commit.md
│   ├── all_findings_downgraded.md
│   ├── minimal_handover.md
│   ├── missing_project_field.md
│   ├── skipping_research.md
│   ├── options_without_recommendation.md
│   ├── no_verify_after_edits.md
│   ├── stalled_auto_transition/
│   │   ├── implement.md
│   │   ├── discuss.md
│   │   └── review.md
│   └── step_ordering/
│       ├── complete_commit_before_validation.md
│       ├── complete_commit_before_docs.md
│       ├── complete_push_before_commit.md
│       ├── complete_handover_before_audit.md
│       ├── complete_pipeline_incomplete.md
│       ├── discuss_plan_before_research.md
│       ├── discuss_plan_before_approach.md
│       ├── implement_code_before_plan.md
│       ├── implement_code_before_plan_read.md
│       ├── implement_pipeline_incomplete.md
│       ├── review_findings_before_agents.md
│       ├── review_ack_before_findings.md
│       └── review_pipeline_incomplete.md
└── auto-transition/      # Layer 1 appendages (4 files)
    ├── implement.md
    ├── review.md
    ├── complete.md
    └── default.md
```

### Modified files

- `plugin/scripts/post-tool-navigator.sh` — add `load_message()`, replace all inline strings
- `docs/reference/architecture.md:78-100` — add `plugin/coaching/` to file organization tree

---

## Task 1: Create directory structure and `load_message` helper

**Files:**
- Create: `plugin/coaching/` (directory tree — empty initially)
- Modify: `plugin/scripts/post-tool-navigator.sh:17-18` (add COACHING_DIR and load_message after SCRIPT_DIR)

- [ ] **Step 1: Create the directory structure**

```bash
mkdir -p plugin/coaching/{objectives,nudges,checks/stalled_auto_transition,checks/step_ordering,auto-transition}
```

- [ ] **Step 2: Add `COACHING_DIR` and `load_message()` to post-tool-navigator.sh**

Insert after line 18 (`source "$SCRIPT_DIR/workflow-state.sh"`), before line 20 (`INPUT=$(cat)`):

```bash
# Coaching message directory — resolved from project root, not SCRIPT_DIR.
# SCRIPT_DIR resolves to .claude/hooks/ (symlink directory), not plugin/scripts/.
COACHING_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}/plugin/coaching"

# Load a coaching message from file. Returns 1 if file missing (message skipped).
# $1: relative path under COACHING_DIR (e.g., "objectives/define.md")
# $2: optional PHASE value to substitute for {{PHASE}}
load_message() {
    local file="$COACHING_DIR/$1"
    if [ ! -f "$file" ]; then
        return 1
    fi
    local msg
    msg=$(cat "$file")
    if [ -n "${2:-}" ]; then
        msg=$(echo "$msg" | sed "s/{{PHASE}}/$2/g")
    fi
    echo "$msg"
}
```

- [ ] **Step 3: Verify the function loads correctly**

```bash
# Create a test message file
echo "Hello from {{PHASE}} phase" > plugin/coaching/objectives/define.md

# Test load_message via sourcing
bash -c '
COACHING_DIR="plugin/coaching"
source plugin/scripts/post-tool-navigator.sh <<< "{}" 2>/dev/null &
# Simpler: just test the function in isolation
COACHING_DIR="'"$(pwd)"'/plugin/coaching"
load_message() {
    local file="$COACHING_DIR/$1"
    [ ! -f "$file" ] && return 1
    local msg; msg=$(cat "$file")
    [ -n "${2:-}" ] && msg=$(echo "$msg" | sed "s/{{PHASE}}/$2/g")
    echo "$msg"
}
result=$(load_message "objectives/define.md" "DEFINE")
echo "Result: $result"
[ "$result" = "Hello from DEFINE phase" ] && echo "PASS" || echo "FAIL"
'
```

Expected: `Result: Hello from DEFINE phase` and `PASS`

- [ ] **Step 4: Test missing file returns empty**

```bash
bash -c '
COACHING_DIR="'"$(pwd)"'/plugin/coaching"
load_message() {
    local file="$COACHING_DIR/$1"
    [ ! -f "$file" ] && return 1
    local msg; msg=$(cat "$file")
    [ -n "${2:-}" ] && msg=$(echo "$msg" | sed "s/{{PHASE}}/$2/g")
    echo "$msg"
}
result=$(load_message "objectives/nonexistent.md" "DEFINE")
status=$?
echo "Status: $status, Output: \"$result\""
[ "$status" -eq 1 ] && [ -z "$result" ] && echo "PASS" || echo "FAIL"
'
```

Expected: `Status: 1, Output: ""` and `PASS`

- [ ] **Step 5: Remove test file and commit**

```bash
rm plugin/coaching/objectives/define.md
git add plugin/coaching/ plugin/scripts/post-tool-navigator.sh
git commit -m "feat: add coaching directory structure and load_message helper"
```

---

## Task 2: Extract Layer 1 objective messages (6 files)

**Files:**
- Create: `plugin/coaching/objectives/{define,discuss,implement,review,complete,error}.md`
- Modify: `plugin/scripts/post-tool-navigator.sh:85-121` (replace case body with load_message calls)

Each `.md` file contains the message text WITHOUT the `[Workflow Coach — PHASE]` prefix — that prefix stays in the script.

- [ ] **Step 1: Create the 6 objective message files**

`plugin/coaching/objectives/define.md`:
```
Objective: Frame the problem and define measurable outcomes.
You are in Diamond 1 (Problem Space). Diverge on understanding, converge on a clear problem statement.
Done when: Plan has a complete Problem section with measurable outcomes, approved by user.
```

`plugin/coaching/objectives/discuss.md`:
```
Objective: Research solution approaches, choose one with documented rationale.
You are in Diamond 2 (Solution Space). Diverge on approaches, converge on a decision with documented trade-offs.
Done when: Spec has Approaches Considered + Decision sections. Spec committed. User approved.
```

`plugin/coaching/objectives/implement.md`:
```
Objective: Write the implementation plan, then build the solution with TDD discipline.
First: write the plan with writing-plans skill. Then: follow it. Flag deviations. Write tests before code. Do not stop after code — run tests and version bump.
Done when: Plan written, all steps implemented, tests passing, ready for review.
```

`plugin/coaching/objectives/review.md`:
```
Objective: Independent multi-agent validation of implementation quality.
Report findings accurately. Don't downgrade severity. You MUST present findings to the user — do not stop after dispatching agents.
Done when: All agents dispatched, findings verified and persisted to spec, user has responded.
```

`plugin/coaching/objectives/complete.md`:
```
Objective: Verify outcomes were met, update documentation, hand over for future sessions.
ALL 9 STEPS ARE MANDATORY. Do not stop after push. Tech debt audit, handover, and summary must complete before prompting /off.
Done when: Validation results in plan, README checked, claude-mem observation saved, phase OFF.
```

`plugin/coaching/objectives/error.md`:
```
Workflow state is corrupted. All writes are blocked for safety.
To recover: run /off to reset the workflow, or manually delete .claude/state/workflow.json
```

- [ ] **Step 2: Replace inline messages with load_message calls in the script**

Replace lines 85-121 (the `case "$PHASE" in` body) with:

```bash
        case "$PHASE" in
            error)
                MESSAGES="[Workflow Coach — ERROR]
$(load_message "objectives/error.md")"
                ;;
            *)
                OBJ_MSG=$(load_message "objectives/$PHASE.md")
                if [ -n "$OBJ_MSG" ]; then
                    MESSAGES="[Workflow Coach — $(echo "$PHASE" | tr '[:lower:]' '[:upper:]')]
$OBJ_MSG"
                fi
                ;;
        esac
```

- [ ] **Step 3: Verify objectives load correctly**

Set phase to discuss temporarily and invoke the hook:

```bash
# Save and modify state
cp .claude/state/workflow.json /tmp/workflow-backup.json
jq '.phase = "discuss" | .message_shown = false' .claude/state/workflow.json > /tmp/wf-test.json && cp /tmp/wf-test.json .claude/state/workflow.json

# Run hook with a Read tool (triggers Layer 1 for non-implement phases)
echo '{"tool_name":"Read","tool_input":{"file_path":"foo"}}' | .claude/hooks/post-tool-navigator.sh 2>/dev/null

# Restore
cp /tmp/workflow-backup.json .claude/state/workflow.json
```

Expected: JSON output containing `[Workflow Coach — DISCUSS]` followed by the discuss objective text.

- [ ] **Step 4: Commit**

```bash
git add plugin/coaching/objectives/ plugin/scripts/post-tool-navigator.sh
git commit -m "refactor: extract Layer 1 objective messages to markdown files"
```

---

## Task 3: Extract Layer 1 auto-transition messages (4 files)

**Files:**
- Create: `plugin/coaching/auto-transition/{implement,review,complete,default}.md`
- Modify: `plugin/scripts/post-tool-navigator.sh:125-148` (replace auto-transition case body)

- [ ] **Step 1: Create the 4 auto-transition message files**

`plugin/coaching/auto-transition/implement.md`:
```
▶▶▶ Unattended (auto) — when all milestones are complete (plan_read, tests_passing, all_tasks_complete), auto-transition: run these commands now:
  .claude/hooks/workflow-cmd.sh agent_set_phase "review"
  .claude/hooks/workflow-cmd.sh reset_review_status
Then read plugin/commands/review.md for phase instructions. Do NOT commit, push, or do other work after milestones are done.
```

`plugin/coaching/auto-transition/review.md`:
```
▶▶▶ Unattended (auto) — when all review milestones are complete, auto-transition: run these commands now:
  .claude/hooks/workflow-cmd.sh agent_set_phase "complete"
  .claude/hooks/workflow-cmd.sh reset_completion_status
Then read plugin/commands/complete.md for phase instructions. Do NOT wait for user.
```

`plugin/coaching/auto-transition/complete.md`:
```
▶▶▶ Unattended (auto) — run the full completion pipeline. Stop only before git push (always requires confirmation).
```

`plugin/coaching/auto-transition/default.md`:
```
▶▶▶ Unattended (auto) — when this phase's work is complete, proceed to the next phase without waiting for user confirmation.
```

- [ ] **Step 2: Replace inline auto-transition messages in the script**

Replace the auto-transition case (lines 125-148) with:

```bash
        AUTONOMY_LEVEL=$(get_autonomy_level)
        if [ "$AUTONOMY_LEVEL" = "auto" ] && [ -n "$MESSAGES" ]; then
            AUTO_MSG=$(load_message "auto-transition/$PHASE.md")
            if [ -z "$AUTO_MSG" ]; then
                AUTO_MSG=$(load_message "auto-transition/default.md")
            fi
            if [ -n "$AUTO_MSG" ]; then
                MESSAGES="$MESSAGES
$AUTO_MSG"
            fi
        fi
```

- [ ] **Step 3: Verify auto-transition loads with fallback**

```bash
cp .claude/state/workflow.json /tmp/workflow-backup.json
jq '.phase = "define" | .message_shown = false | .autonomy_level = "auto"' .claude/state/workflow.json > /tmp/wf-test.json && cp /tmp/wf-test.json .claude/state/workflow.json

echo '{"tool_name":"Read","tool_input":{"file_path":"foo"}}' | .claude/hooks/post-tool-navigator.sh 2>/dev/null

cp /tmp/workflow-backup.json .claude/state/workflow.json
```

Expected: Output includes both the define objective AND the default auto-transition message (`▶▶▶ Unattended (auto) — when this phase's work is complete...`).

- [ ] **Step 4: Commit**

```bash
git add plugin/coaching/auto-transition/ plugin/scripts/post-tool-navigator.sh
git commit -m "refactor: extract Layer 1 auto-transition messages to markdown files"
```

---

## Task 4: Extract Layer 2 nudge messages (11 files) and normalize trigger names

**Files:**
- Create: `plugin/coaching/nudges/*.md` (11 files)
- Modify: `plugin/scripts/post-tool-navigator.sh:207-302` (replace L2_MSG assignments, rename triggers)

This task also normalizes the 5 inconsistent trigger names per the spec's Scope Clarification.

- [ ] **Step 1: Create the 11 nudge message files**

Each file contains ONLY the message text after the `[Workflow Coach — PHASE]` prefix.

`plugin/coaching/nudges/agent_return_define.md`:
```
Challenge the first framing. Separate facts from interpretations. Are these findings changing the problem statement?
```

`plugin/coaching/nudges/plan_write_define.md`:
```
Challenge vague problem statements. Outcomes must be verifiable. Problem and Goals sections must be concrete. 'Better UX' is aspirational; 'checkout completes in under 3 clicks' is verifiable.
```

`plugin/coaching/nudges/agent_return_discuss.md`:
```
Every approach must have stated downsides. Unsourced claims are opinions. Does this trace back to the problem statement?
```

`plugin/coaching/nudges/plan_write_discuss.md`:
```
Does the spec document the problem clearly? Are approaches compared with trade-offs? Did you document why this approach over alternatives?
```

`plugin/coaching/nudges/source_edit_implement.md`:
```
Does this follow the plan? Would you be proud to have this reviewed? Tests written first?
```

`plugin/coaching/nudges/test_run_implement.md`:
```
If tests fail, diagnose the root cause. Don't patch the test to make it pass. Don't skip tests for small changes.
```

`plugin/coaching/nudges/agent_return_review.md`:
```
Don't downgrade findings. Verify before reporting. Flag systemic issues, not just instances.
```

`plugin/coaching/nudges/findings_present_review.md`:
```
Quantify the cost of not fixing. Don't soften with 'but this is minor.' State facts, let user decide.
```

`plugin/coaching/nudges/agent_return_complete.md`:
```
Be specific about failures. Quantify fix effort. Recommend a next phase, don't just list options.
```

`plugin/coaching/nudges/project_docs_edit_complete.md`:
```
Does the handover make sense to a stranger? Is tech debt visible? Does README match reality?
```

`plugin/coaching/nudges/test_run_complete.md`:
```
Be specific about validation failures. If a test fails, diagnose with quantified fix effort. Don't let failures be acknowledged without understanding consequences.
```

- [ ] **Step 2: Replace Layer 2 inline messages with load_message calls and normalize triggers**

In the `case "$PHASE"` block (lines 207-266), replace each `TRIGGER="..."; L2_MSG="..."` pair. The pattern for each is:

```bash
TRIGGER="<normalized_name>"
L2_MSG_BODY=$(load_message "nudges/<normalized_name>.md")
if [ -n "$L2_MSG_BODY" ]; then
    L2_MSG="[Workflow Coach — $(echo "$PHASE" | tr '[:lower:]' '[:upper:]')] $L2_MSG_BODY"
fi
```

Trigger name changes (normalization):
- Line 226: `plan_write` → `plan_write_discuss`
- Line 233: `source_edit` → `source_edit_implement`
- Line 238: `test_run` → `test_run_implement`
- Line 255: `project_docs_edit` → `project_docs_edit_complete`

Also replace the separate findings_present block (lines 282-302):
- Line 288: `findings_present` → `findings_present_review`
- Replace `FINDINGS_MSG` inline string with load_message call

- [ ] **Step 3: Verify a nudge loads correctly**

```bash
cp .claude/state/workflow.json /tmp/workflow-backup.json
jq '.phase = "implement" | .message_shown = true | .coaching.layer2_fired = []' .claude/state/workflow.json > /tmp/wf-test.json && cp /tmp/wf-test.json .claude/state/workflow.json

echo '{"tool_name":"Edit","tool_input":{"file_path":"src/foo.py"}}' | .claude/hooks/post-tool-navigator.sh 2>/dev/null

cp /tmp/workflow-backup.json .claude/state/workflow.json
```

Expected: JSON with `[Workflow Coach — IMPLEMENT] Does this follow the plan?...`

- [ ] **Step 4: Commit**

```bash
git add plugin/coaching/nudges/ plugin/scripts/post-tool-navigator.sh
git commit -m "refactor: extract Layer 2 nudge messages and normalize trigger names"
```

---

## Task 5: Extract Layer 3 check messages — simple checks (8 files)

**Files:**
- Create: `plugin/coaching/checks/{short_agent_prompt,generic_commit,all_findings_downgraded,minimal_handover,missing_project_field,skipping_research,options_without_recommendation,no_verify_after_edits}.md`
- Modify: `plugin/scripts/post-tool-navigator.sh:305-461`

These checks use `{{PHASE}}` for dynamic phase names. The `no_verify_after_edits` check keeps its `$VERIFY_COUNT` interpolation inline.

- [ ] **Step 1: Create the 8 check message files**

`plugin/coaching/checks/short_agent_prompt.md`:
```
Agent prompts must be detailed enough for autonomous work. Include: context, specific task, expected output format, constraints. Short prompts produce shallow results.
```

`plugin/coaching/checks/generic_commit.md`:
```
Commit messages must explain why, not what. The diff shows what changed. Include context and reasoning.
```

`plugin/coaching/checks/all_findings_downgraded.md`:
```
All findings were rated as suggestions. Review severity assessments. Are you downgrading to avoid friction?
```

`plugin/coaching/checks/minimal_handover.md`:
```
The handover must be useful to someone who knows nothing about this session. Include: what was built, why these choices, gotchas, what's left.
```

`plugin/coaching/checks/missing_project_field.md`:
```
save_observation called without project parameter. Always pass project to scope observations to this repo. Derive repo name: git remote get-url origin 2>/dev/null | sed 's/.*[:/]\([^/]*\)\.git$/\1/' | sed 's/.*[:/]\([^/]*\)$/\1/'
```

`plugin/coaching/checks/skipping_research.md`:
```
You're in a research phase but haven't dispatched background agents. Is this trivial enough to skip? State explicitly.
```

`plugin/coaching/checks/options_without_recommendation.md`:
```
Don't just list options. State which you recommend and why. The user needs your professional judgment, not a menu.
```

`plugin/coaching/checks/no_verify_after_edits.md`:
```
You've edited source code without running tests or verification. Verify your changes before continuing.
```

Note: `no_verify_after_edits.md` contains the static portion. The script prepends `[Workflow Coach — PHASE]` and inserts `$VERIFY_COUNT times` before "without running tests" inline.

- [ ] **Step 2: Replace inline L3 messages with load_message calls**

For each check, the pattern is:

```bash
PHASE_UPPER=$(echo "$PHASE" | tr '[:lower:]' '[:upper:]')
CHECK_MSG=$(load_message "checks/<name>.md" "$PHASE_UPPER")
if [ -n "$CHECK_MSG" ]; then
    L3_MSG="[Workflow Coach — $PHASE_UPPER] $CHECK_MSG"
fi
```

For `no_verify_after_edits` (Check 7), keep the count inline:

```bash
VERIFY_MSG_BODY=$(load_message "checks/no_verify_after_edits.md" "$PHASE_UPPER")
if [ -n "$VERIFY_MSG_BODY" ]; then
    VERIFY_MSG="[Workflow Coach — $PHASE_UPPER] You've edited source code $VERIFY_COUNT times but haven't run tests or verification. Verify your changes before continuing."
fi
```

Note: The `.md` file contains the generic text, but the script constructs the message with `$VERIFY_COUNT` baked in. The file serves as a reference for the message content — the actual runtime message includes the count. This is the one exception to pure file-loading.

- [ ] **Step 3: Verify a check fires with {{PHASE}} substitution**

```bash
cp .claude/state/workflow.json /tmp/workflow-backup.json
jq '.phase = "discuss" | .message_shown = true | .coaching.tool_calls_since_agent = 15' .claude/state/workflow.json > /tmp/wf-test.json && cp /tmp/wf-test.json .claude/state/workflow.json

echo '{"tool_name":"Edit","tool_input":{"file_path":"src/foo.py"}}' | .claude/hooks/post-tool-navigator.sh 2>/dev/null

cp /tmp/workflow-backup.json .claude/state/workflow.json
```

Expected: Output includes `[Workflow Coach — DISCUSS] You're in a research phase...`

- [ ] **Step 4: Commit**

```bash
git add plugin/coaching/checks/*.md plugin/scripts/post-tool-navigator.sh
git commit -m "refactor: extract Layer 3 simple check messages to markdown files"
```

---

## Task 6: Extract Layer 3 stalled auto-transition messages (3 files)

**Files:**
- Create: `plugin/coaching/checks/stalled_auto_transition/{implement,discuss,review}.md`
- Modify: `plugin/scripts/post-tool-navigator.sh:463-510`

- [ ] **Step 1: Create the 3 stalled auto-transition message files**

`plugin/coaching/checks/stalled_auto_transition/implement.md`:
```
⚠ ALL MILESTONES COMPLETE. Auto-transition: run these commands now:
  .claude/hooks/workflow-cmd.sh agent_set_phase "review"
  .claude/hooks/workflow-cmd.sh reset_review_status
Then read plugin/commands/review.md for phase instructions. Do not commit, push, or do other work. Auto autonomy requires completing the full pipeline: IMPLEMENT → REVIEW → COMPLETE.
```

`plugin/coaching/checks/stalled_auto_transition/discuss.md`:
```
⚠ ALL MILESTONES COMPLETE. Auto-transition: run these commands now:
  .claude/hooks/workflow-cmd.sh agent_set_phase "implement"
  .claude/hooks/workflow-cmd.sh reset_implement_status
Then read plugin/commands/implement.md for phase instructions. Auto autonomy requires completing the full pipeline: DISCUSS → IMPLEMENT.
```

`plugin/coaching/checks/stalled_auto_transition/review.md`:
```
⚠ ALL REVIEW MILESTONES COMPLETE. Auto-transition: run these commands now:
  .claude/hooks/workflow-cmd.sh agent_set_phase "complete"
  .claude/hooks/workflow-cmd.sh reset_completion_status
Then read plugin/commands/complete.md for phase instructions. Auto autonomy requires completing the full pipeline: REVIEW → COMPLETE.
```

- [ ] **Step 2: Replace inline stall messages with load_message calls**

Replace each `STALL_MSG="[Workflow Coach — PHASE] ..."` block with:

```bash
STALL_BODY=$(load_message "checks/stalled_auto_transition/$PHASE.md")
if [ -n "$STALL_BODY" ]; then
    STALL_MSG="[Workflow Coach — $(echo "$PHASE" | tr '[:lower:]' '[:upper:]')] $STALL_BODY"
fi
```

- [ ] **Step 3: Commit**

```bash
git add plugin/coaching/checks/stalled_auto_transition/ plugin/scripts/post-tool-navigator.sh
git commit -m "refactor: extract stalled auto-transition messages to markdown files"
```

---

## Task 7: Extract Layer 3 step ordering messages (13 files)

**Files:**
- Create: `plugin/coaching/checks/step_ordering/*.md` (13 files)
- Modify: `plugin/scripts/post-tool-navigator.sh:512-599`

- [ ] **Step 1: Create the 13 step ordering message files**

`plugin/coaching/checks/step_ordering/complete_commit_before_validation.md`:
```
Committing before validation is complete. Run Steps 1-3 (plan validation, outcome validation, present results) first.
```

`plugin/coaching/checks/step_ordering/complete_commit_before_docs.md`:
```
Committing before documentation check. Run Step 4 first.
```

`plugin/coaching/checks/step_ordering/complete_push_before_commit.md`:
```
Pushing before committing. Run Step 5 first.
```

`plugin/coaching/checks/step_ordering/complete_handover_before_audit.md`:
```
Writing handover before tech debt audit. Run Step 7 first.
```

`plugin/coaching/checks/step_ordering/complete_pipeline_incomplete.md`:
```
Pipeline incomplete. You pushed but Steps 7-9 (tech debt, handover, summary) still need to run. Do not stop here.
```

`plugin/coaching/checks/step_ordering/discuss_plan_before_research.md`:
```
Writing spec before research is complete. Complete the diverge phase first.
```

`plugin/coaching/checks/step_ordering/discuss_plan_before_approach.md`:
```
Writing spec before approach is selected. Complete the converge phase first.
```

`plugin/coaching/checks/step_ordering/implement_code_before_plan.md`:
```
Writing code before the implementation plan is written. Write the plan first with superpowers:writing-plans.
```

`plugin/coaching/checks/step_ordering/implement_code_before_plan_read.md`:
```
Writing code before reading the plan. Read the plan first and mark plan_read milestone.
```

`plugin/coaching/checks/step_ordering/implement_pipeline_incomplete.md`:
```
All tasks complete but tests not run. Run the test suite and version bump before transitioning to review.
```

`plugin/coaching/checks/step_ordering/review_findings_before_agents.md`:
```
Writing findings before all agents have run. Dispatch review agents first.
```

`plugin/coaching/checks/step_ordering/review_ack_before_findings.md`:
```
Asking for acknowledgment before presenting findings. Present findings first.
```

`plugin/coaching/checks/step_ordering/review_pipeline_incomplete.md`:
```
Review agents returned but findings not presented. Consolidate and present findings to the user.
```

- [ ] **Step 2: Replace inline step ordering messages with load_message calls**

Replace each `STEP_MSG="[Workflow Coach — PHASE] ..."` with:

```bash
STEP_BODY=$(load_message "checks/step_ordering/<key>.md")
if [ -n "$STEP_BODY" ]; then
    STEP_MSG="[Workflow Coach — $(echo "$PHASE" | tr '[:lower:]' '[:upper:]')] $STEP_BODY"
fi
```

Where `<key>` matches the file name for each check condition.

- [ ] **Step 3: Verify a step ordering check fires**

```bash
cp .claude/state/workflow.json /tmp/workflow-backup.json
jq '.phase = "implement" | .message_shown = true | .implement = {plan_written: false, plan_read: false, tests_passing: false, all_tasks_complete: false}' .claude/state/workflow.json > /tmp/wf-test.json && cp /tmp/wf-test.json .claude/state/workflow.json

echo '{"tool_name":"Edit","tool_input":{"file_path":"src/foo.py"}}' | .claude/hooks/post-tool-navigator.sh 2>/dev/null

cp /tmp/workflow-backup.json .claude/state/workflow.json
```

Expected: Output includes `[Workflow Coach — IMPLEMENT] Writing code before the implementation plan is written...`

- [ ] **Step 4: Commit**

```bash
git add plugin/coaching/checks/step_ordering/ plugin/scripts/post-tool-navigator.sh
git commit -m "refactor: extract step ordering messages to markdown files"
```

---

## Task 8: Update architecture documentation

**Files:**
- Modify: `docs/reference/architecture.md:78-100`

- [ ] **Step 1: Add `plugin/coaching/` to the file organization tree**

In the file organization section, add the coaching directory under the project tree. After the `├── docs/` section and before `├── CLAUDE.md`:

```
├── plugin/
│   ├── coaching/                        # Coaching messages (editable prose)
│   │   ├── objectives/                  # Phase entry messages
│   │   ├── nudges/                      # Contextual reminders
│   │   ├── checks/                      # Anti-laziness checks
│   │   └── auto-transition/             # Autonomy=auto appendages
│   ├── scripts/                         # Hook scripts
│   └── commands/                        # Phase commands
```

- [ ] **Step 2: Commit**

```bash
git add docs/reference/architecture.md
git commit -m "docs: add plugin/coaching/ to architecture file organization"
```

---

## Task 9: End-to-end verification

Run the full hook through all layers to verify no regressions.

- [ ] **Step 1: Test Layer 1 + Layer 2 + Layer 3 together**

```bash
cp .claude/state/workflow.json /tmp/workflow-backup.json

# Set up state: implement phase, message already shown, no agent calls, no plan written
jq '.phase = "implement" | .message_shown = true | .coaching = {tool_calls_since_agent: 0, layer2_fired: []} | .implement = {plan_written: false, plan_read: false, tests_passing: false, all_tasks_complete: false}' .claude/state/workflow.json > /tmp/wf-test.json && cp /tmp/wf-test.json .claude/state/workflow.json

# This should trigger: L2 source_edit_implement nudge + L3 step_ordering implement_code_before_plan
echo '{"tool_name":"Edit","tool_input":{"file_path":"src/foo.py"}}' | .claude/hooks/post-tool-navigator.sh 2>/dev/null

cp /tmp/workflow-backup.json .claude/state/workflow.json
```

Expected: JSON output containing both a nudge message and a step ordering message.

- [ ] **Step 2: Test OFF phase produces no output**

```bash
echo '{"tool_name":"Edit","tool_input":{"file_path":"src/foo.py"}}' | .claude/hooks/post-tool-navigator.sh 2>/dev/null
```

Expected: No output (phase is OFF).

- [ ] **Step 3: Test missing message file is silently skipped**

```bash
cp .claude/state/workflow.json /tmp/workflow-backup.json
jq '.phase = "discuss" | .message_shown = false' .claude/state/workflow.json > /tmp/wf-test.json && cp /tmp/wf-test.json .claude/state/workflow.json

# Temporarily rename the discuss objective to test graceful degradation
mv plugin/coaching/objectives/discuss.md plugin/coaching/objectives/discuss.md.bak

echo '{"tool_name":"Read","tool_input":{"file_path":"foo"}}' | .claude/hooks/post-tool-navigator.sh 2>/dev/null

# Restore
mv plugin/coaching/objectives/discuss.md.bak plugin/coaching/objectives/discuss.md
cp /tmp/workflow-backup.json .claude/state/workflow.json
```

Expected: No output (missing file = no message, no error).

- [ ] **Step 4: Verify line count reduction**

```bash
wc -l plugin/scripts/post-tool-navigator.sh
```

Expected: approximately 540 lines (down from 626).

- [ ] **Step 5: Final commit if any verification fixes were needed**

Only if changes were made during verification:

```bash
git add -A
git commit -m "fix: address issues found during end-to-end verification"
```
