Transition the workflow to IMPLEMENT phase. First check for soft gate warnings:

```bash
WF_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
WARN=$("$WF_DIR/.claude/hooks/workflow-cmd.sh" check_soft_gate "implement")
if [ -n "$WARN" ]; then
    echo "WARNING: $WARN"
fi
```

If a warning was shown, ask the user: "Proceed anyway? (yes/no)". If they say no, stop. If yes or no warning, continue:

```bash
WF_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}" && "$WF_DIR/.claude/hooks/workflow-cmd.sh" set_phase "implement" && "$WF_DIR/.claude/hooks/workflow-cmd.sh" reset_implement_status && "$WF_DIR/.claude/hooks/workflow-cmd.sh" set_active_skill ""
echo "Phase set to IMPLEMENT — code edits are now allowed."
```

Then confirm to the user that the phase has changed and they can now proceed with implementation.

**You are now in IMPLEMENT phase.** Before proceeding:
1. Read `docs/reference/professional-standards.md` — apply the Universal Standards and IMPLEMENT Phase Standards throughout this phase.

**Autonomy-aware behavior:**
- **Level 3 (▶▶▶):** Use `superpowers:subagent-driven-development` (recommended execution mode) without asking. Make operational decisions (execution approach, model selection, task ordering) autonomously. Only stop for genuine blockers.
- **Level 1-2:** Ask the user which execution approach they prefer if multiple options exist.

Follow this workflow:
1. Read the plan file and mark milestone:
```bash
WF_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}" && "$WF_DIR/.claude/hooks/workflow-cmd.sh" set_implement_field "plan_read" "true"
```
2. Use `superpowers:executing-plans` or `superpowers:subagent-driven-development` to implement the approved plan
3. Use `superpowers:test-driven-development` — write tests before implementation code
4. When all plan tasks are implemented, mark milestone:
```bash
WF_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}" && "$WF_DIR/.claude/hooks/workflow-cmd.sh" set_implement_field "all_tasks_complete" "true"
```
5. Run the full test suite and verify all pass. Then mark milestone:
```bash
WF_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}" && "$WF_DIR/.claude/hooks/workflow-cmd.sh" set_implement_field "tests_passing" "true"
```
6. Proceed to `/review` (Level 3) or wait for the user to run `/review` (Level 1-2)

**HARD GATE: You cannot transition to /review without completing all 3 milestones (plan_read, all_tasks_complete, tests_passing). set_phase will refuse.**

**Review transparency:** When spec compliance reviewers or code quality reviewers find issues during implementation, always present a summary to the user: what the reviewer found, what you fixed, and the final verdict. Never silently fix and move on — the user must see what was caught.

**Important:** When you invoke a superpowers skill, update the active skill tracker:
```bash
WF_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}" && "$WF_DIR/.claude/hooks/workflow-cmd.sh" set_active_skill "SKILL_NAME"
```
Replace SKILL_NAME with the skill being used (e.g., "executing-plans", "test-driven-development").

**Level 3 auto-transition:** If autonomy level is 3, invoke `/review` now when all plan tasks are complete and tests pass. Do not wait for the user.
