# DISCUSS Phase — Diamond 2: Solution Space

Code edits are blocked — design the solution and select the approach.

**Git in DEFINE/DISCUSS:** Spec and plan files (`docs/plans/`, `docs/specs/`) can be committed. Use **single git commands** — run `git add` and `git commit` as separate commands, not chained with `&&`. Chained commands with heredoc-style commit messages may be blocked by the write guard.

Before proceeding:
1. Read `plugin/docs/reference/professional-standards.md` — apply the Universal Standards and DISCUSS Phase Standards throughout this phase.

**Skill Resolution:** Follow the process in `plugin/docs/reference/skill-resolution.md` before invoking skills.

**Agent Dispatch:** Follow `plugin/docs/reference/agent-dispatch.md` — read each agent's `.md` file, then dispatch as `general-purpose` with the file content + runtime context as the prompt.

**Phase Transitions:** Slash commands (e.g., `/implement`) trigger phase transitions via `user-set-phase.sh` — only the user can run these. In auto autonomy mode, the agent transitions forward using `agent_set_phase` via `workflow-cmd.sh`. All milestone and state commands go through `workflow-cmd.sh`. See the case statement in `workflow-cmd.sh` for the full list of available commands.

## Setup

If no plan exists yet, create one and register it:

```bash
EXISTING=$(.claude/hooks/workflow-cmd.sh get_plan_path)
if [ -z "$EXISTING" ]; then
    echo "No plan found — will create one during this phase."
fi
```

If no plan exists, brainstorming will naturally cover problem discovery (lighter than a full DEFINE phase). Create the plan with a Problem section from what you learn, then proceed to solution design.

Once the problem statement is confirmed (from DEFINE's plan or from brainstorming), mark the milestone:
```bash
.claude/hooks/workflow-cmd.sh set_discuss_field "problem_confirmed" "true"
```

## Steps

1. **Diverge** — see `step_1.md`
2. **Converge** — see `step_2.md`

## Step Expectations

| Step | What you do | Evidence required before next step | Milestone |
|------|-------------|-------------------------------------|-----------|
| Problem confirmed | Verify problem statement from DEFINE or brainstorm | User or plan confirms the problem | `problem_confirmed=true` |
| Diverge | Dispatch 3 research agents | Agents returned, findings presented with sources and downsides | `research_done=true` |
| Converge | User narrows to approach, dispatch 2 agents | User selected approach, spec enriched with decision record | `approach_selected=true` |

## Autonomy Behavior

- **off (▶):** After each design decision or research finding, present the result and wait for explicit user approval before proceeding. Never batch diverge/converge phases. Present the plan section by section, waiting for approval after each.
- **ask (▶▶):** When the spec is approved, they will run `/implement` to proceed.
- **auto (▶▶▶):** Auto-transition to `/implement` via `agent_set_phase` after the spec passes review. Only stop if user input is needed during converge (approach selection).

**Review transparency:** When the spec review loop finds issues, always present a summary to the user: what the reviewer found, what you fixed, and the final verdict. Never silently fix and move on — the user must see what was caught.
