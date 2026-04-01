# IMPLEMENT Phase

Before proceeding:
1. Read `plugin/docs/reference/professional-standards.md` — apply the Universal Standards and IMPLEMENT Phase Standards throughout this phase.

**Skill Resolution:** Follow the process in `plugin/docs/reference/skill-resolution.md` before invoking skills.

**Agent Dispatch:** Follow `plugin/docs/reference/agent-dispatch.md` — read each agent's `.md` file, then dispatch as `general-purpose` with the file content + runtime context as the prompt.

**Phase Transitions:** Slash commands (e.g., `/review`) trigger phase transitions via `user-set-phase.sh` — only the user can run these. In auto autonomy mode, the agent transitions forward using `agent_set_phase` via `workflow-cmd.sh`. All milestone and state commands go through `workflow-cmd.sh`. See the case statement in `workflow-cmd.sh` for the full list of available commands.

## Steps

1. **Write plan** — see `step_1.md`
2. **Read plan** — see `step_2.md`
3. **Implement** — see `step_3.md`
4. **Version bump** — see `step_4.md`
5. **Tests** — see `step_5.md`

## Step Expectations

| Step | What you do | Evidence required before next step | Milestone |
|------|-------------|-------------------------------------|-----------|
| Write plan | Write implementation plan with `superpowers:writing-plans` | Plan file exists on disk, reviewer passed | `plan_written=true` |
| Read plan | Read the plan file | Plan file read in this session | `plan_read=true` |
| Implement | Execute all plan tasks via subagent-driven-development | Every task committed, files exist on disk | `all_tasks_complete=true` |
| Version bump | Dispatch versioning agent | Both plugin.json files updated and in sync | — (COMPLETE verifies) |
| Tests | Run full test suite | Test output shown — pass count visible | `tests_passing=true` |
| Transition | Ask user to run `/review` or wait | All 4 milestones set | — |

**HARD GATE: You cannot transition to /review without completing all 4 milestones (plan_written, plan_read, all_tasks_complete, tests_passing). agent_set_phase will refuse.**

## Autonomy Behavior

- **auto (▶▶▶):** Use `superpowers:subagent-driven-development` (recommended execution mode) without asking. Make operational decisions (execution approach, model selection, task ordering) autonomously. Only stop for genuine blockers. Auto-transition to `/review` via `agent_set_phase` when all milestones are set.
- **ask (▶▶):** Ask the user which execution approach they prefer if multiple options exist. Work freely within the phase, committing after each task.
- **off (▶):** Work within phase rules. After completing each plan step, present the change (files modified, key diff summary), and wait for the user's explicit approval before proceeding to the next step. Never batch multiple steps. Never auto-commit — ask before each commit.

**Review transparency:** When spec compliance reviewers or code quality reviewers find issues during implementation, always present a summary to the user: what the reviewer found, what you fixed, and the final verdict. Never silently fix and move on — the user must see what was caught.

**Important:** When you invoke a superpowers skill, update the active skill tracker:
```bash
.claude/hooks/workflow-cmd.sh set_active_skill "SKILL_NAME"
```
