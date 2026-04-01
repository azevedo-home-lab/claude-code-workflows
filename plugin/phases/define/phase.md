# DEFINE Phase — Diamond 1: Problem Space

Code edits are blocked — define the problem and outcomes first.

**Git in DEFINE/DISCUSS:** Spec and plan files (`docs/plans/`, `docs/specs/`) can be committed. Use **single git commands** — run `git add` and `git commit` as separate commands, not chained with `&&`. Chained commands with heredoc-style commit messages may be blocked by the write guard.

Before proceeding:
1. Read `plugin/docs/reference/professional-standards.md` — apply the Universal Standards and DEFINE Phase Standards throughout this phase.

**Skill Resolution:** Follow the process in `plugin/docs/reference/skill-resolution.md` before invoking skills.

**Agent Dispatch:** Follow `plugin/docs/reference/agent-dispatch.md` — read each agent's `.md` file, then dispatch as `general-purpose` with the file content + runtime context as the prompt.

**Phase Transitions:** Slash commands (e.g., `/implement`) trigger phase transitions via `user-set-phase.sh` — only the user can run these. In auto autonomy mode, the agent transitions forward using `agent_set_phase` via `workflow-cmd.sh`. All milestone and state commands go through `workflow-cmd.sh`. See the case statement in `workflow-cmd.sh` for the full list of available commands.

## Steps

1. **Diverge** — see `step_1.md`
2. **Converge** — see `step_2.md`
3. **Output** — see `step_3.md`

## Step Expectations

| Step | What you do | Evidence required before next step |
|------|-------------|-------------------------------------|
| Diverge | Ask discovery questions, dispatch 3 agents | Agents returned, findings synthesized |
| Converge | Agree on problem statement with user | User confirmed: "yes, that's the right problem" |
| Outcomes | Structure measurable outcomes | Each outcome has description, type, verification method, acceptance criteria |
| Plan | Write to `docs/plans/` | File exists on disk, `set_plan_path` called |
| Transition | Ask user to run `/discuss` or wait | Plan path registered in state |

## Autonomy Behavior

- **auto (▶▶▶):** Auto-transition to `/discuss` via `agent_set_phase` after problem is defined.
- **ask (▶▶):** Present the plan and wait for the user to run `/discuss`.
- **off (▶):** After each problem discovery exchange, summarize what was learned and wait for the user's direction before proceeding. Present the plan and wait for explicit approval before any transition.
