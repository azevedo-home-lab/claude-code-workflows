# REVIEW Phase

Before proceeding:
1. Read `plugin/docs/reference/professional-standards.md` — apply the Universal Standards and REVIEW Phase Standards throughout this phase.

**Skill Resolution:** Follow the process in `plugin/docs/reference/skill-resolution.md` before invoking skills.

**Agent Dispatch:** Follow `plugin/docs/reference/agent-dispatch.md` — read each agent's `.md` file, then dispatch as `general-purpose` with the file content + runtime context as the prompt.

**Phase Transitions:** Slash commands (e.g., `/complete`) trigger phase transitions via `user-set-phase.sh` — only the user can run these. In auto autonomy mode, the agent transitions forward using `agent_set_phase` via `workflow-cmd.sh`. All milestone and state commands go through `workflow-cmd.sh`. See the case statement in `workflow-cmd.sh` for the full list of available commands.

## Steps

1. **Verify tests** — see `step_1.md`
2. **Detect changes** — see `step_2.md`
3. **Dispatch 5 review agents** — see `step_3.md`
4. **Dispatch verification agent** — see `step_4.md`
5. **Consolidate and present findings** — see `step_5.md`

## Step Expectations

| Step | What you do | Evidence required before next step | Milestone |
|------|-------------|-------------------------------------|-----------|
| Verify tests | Check `tests_passing` from IMPLEMENT | If not set: run tests now and show output | `verification_complete=true` |
| Detect changes | Run git diff + ls-files | File list visible | — |
| 5 agents | Dispatch all 5 in parallel | All agents returned (or noted if timed out) | `agents_dispatched=true` |
| Verification agent | Dispatch verifier on agent findings | Verifier returned | — |
| Present findings | Show consolidated Critical/Warning/Suggestion table | User sees the full table — never compress to "N issues" | `findings_presented=true` |
| Acknowledge | User chooses fix or proceed | User response received | `findings_acknowledged=true` |

## Autonomy Behavior

- **off (▶):** After each review agent returns, present its findings individually and wait for user review before dispatching the next agent. Do not batch all 5 agents in parallel — dispatch one at a time, presenting results between each.
- **ask (▶▶):** Dispatch all 5 agents in parallel, present consolidated findings, wait for user response.
- **auto (▶▶▶):** Fix ALL findings — critical, warnings, and suggestions. Only stop if there are critical findings or decisions that require user judgment. Do not acknowledge findings without fixing them unless the user has explicitly accepted them. After all findings are fixed, auto-transition to `/complete` via `agent_set_phase`.
