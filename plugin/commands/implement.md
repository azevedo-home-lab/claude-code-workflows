---
description: Execute the approved plan with TDD and code edits enabled
disable-model-invocation: true
---
<!-- Do NOT invoke this command via the Skill tool. Use the native /command path only. -->
!`WARN=$(.claude/hooks/workflow-cmd.sh check_soft_gate "implement"); if [ -n "$WARN" ]; then echo "SOFT_GATE_WARNING: $WARN"; else WF_SKIP_AUTH=1 .claude/hooks/workflow-cmd.sh set_phase "implement" && .claude/hooks/workflow-cmd.sh reset_implement_status && .claude/hooks/workflow-cmd.sh set_active_skill "" && echo "Phase set to IMPLEMENT — code edits are now allowed."; fi`

Present the output to the user.

If the output shows `SOFT_GATE_WARNING`, ask the user: "Proceed anyway? (yes/no)". If yes, run the phase transition manually. If no, stop.

**You are now in IMPLEMENT phase.** Before proceeding:
1. Read `plugin/docs/reference/professional-standards.md` — apply the Universal Standards and IMPLEMENT Phase Standards throughout this phase.

**Skill Resolution:** Follow the process in `plugin/docs/reference/skill-resolution.md` before invoking skills.

**Agent Dispatch:** Follow `plugin/docs/reference/agent-dispatch.md` — read each agent's `.md` file, then dispatch as `general-purpose` with the file content + runtime context as the prompt.

**Autonomy-aware behavior:**
- **auto (▶▶▶):** Use `superpowers:subagent-driven-development` (recommended execution mode) without asking. Make operational decisions (execution approach, model selection, task ordering) autonomously. Only stop for genuine blockers.
- **ask (▶▶):** Ask the user which execution approach they prefer if multiple options exist. Work freely within the phase, committing after each task.
- **off (▶):** Work within phase rules. After completing each plan step, present the change (files modified, key diff summary), and wait for the user's explicit approval before proceeding to the next step. Never batch multiple steps. Never auto-commit — ask before each commit.

Follow this workflow:
1. Read the plan file and mark milestone:
```bash
.claude/hooks/workflow-cmd.sh set_implement_field "plan_read" "true"
```
2. Use `superpowers:executing-plans` or `superpowers:subagent-driven-development` to implement the approved plan
3. Use `superpowers:test-driven-development` — write tests before implementation code
4. When all plan tasks are implemented, mark milestone:
```bash
.claude/hooks/workflow-cmd.sh set_implement_field "all_tasks_complete" "true"
```
4b. **Version bump** (after all tasks complete, before final test run):

Dispatch a **Versioning agent** — read `plugin/agents/versioning-agent.md`, then dispatch as `general-purpose`:

Context: "Decision record: [DECISION_RECORD_PATH]. Determine the semantic version bump for this release."

Apply the version bump to both files:
```bash
python3 -c "
import json, sys
new_version = sys.argv[1]
for path in ['.claude-plugin/marketplace.json', '.claude-plugin/plugin.json']:
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

Run `scripts/check-version-sync.sh` to validate both files match. This is not an IMPLEMENT exit gate — COMPLETE Step 5 will verify it.

5. Run the full test suite and verify all pass:
```bash
bash tests/run-tests.sh   # or equivalent for this project
```
   If tests fail: fix them before proceeding. Do not mark `tests_passing` with failing tests.
   If tests pass:
```bash
.claude/hooks/workflow-cmd.sh set_implement_field "tests_passing" "true"
.claude/hooks/workflow-cmd.sh set_tests_passed_at "$(git rev-parse HEAD)"
```
6. Proceed to `/review` (auto) or wait for the user to run `/review` (off/ask)

**Step expectations — what each step must produce before you move on:**

| Step | What you do | Evidence required before next step | Milestone |
|------|-------------|-------------------------------------|-----------|
| Read plan | Read the plan file | Plan file read in this session | `plan_read=true` |
| Implement | Execute all plan tasks via subagent-driven-development | Every task committed, files exist on disk | `all_tasks_complete=true` |
| Version bump | Dispatch versioning agent | Both plugin.json files updated and in sync | — |
| Tests | Run full test suite | Test output shown — pass count visible | `tests_passing=true` |
| Transition | Call `/review` (auto) or wait | All 3 milestones set | — |

**If tests fail:** fix the code before marking `tests_passing`. Do not proceed to REVIEW with failing tests.

**HARD GATE: You cannot transition to /review without completing all 3 milestones (plan_read, all_tasks_complete, tests_passing). set_phase will refuse.**

**Review transparency:** When spec compliance reviewers or code quality reviewers find issues during implementation, always present a summary to the user: what the reviewer found, what you fixed, and the final verdict. Never silently fix and move on — the user must see what was caught.

**Important:** When you invoke a superpowers skill, update the active skill tracker:
```bash
.claude/hooks/workflow-cmd.sh set_active_skill "SKILL_NAME"
```
Replace SKILL_NAME with the skill being used (e.g., "executing-plans", "test-driven-development").

**Auto-transition:** If autonomy is auto, invoke `/review` now when all plan tasks are complete and tests pass. Do not wait for the user.
