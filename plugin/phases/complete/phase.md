# COMPLETE Phase — Completion Pipeline

**Execute all steps in order. Missing artifacts cause steps to be skipped gracefully — the pipeline never hard-blocks.**

Before proceeding:
1. Read `plugin/docs/reference/professional-standards.md` — apply the Universal Standards and COMPLETE Phase Standards throughout this phase.

**Skill Resolution:** Follow the process in `plugin/docs/reference/skill-resolution.md` before invoking skills.

**Agent Dispatch:** Follow `plugin/docs/reference/agent-dispatch.md` — read each agent's `.md` file, then dispatch as `general-purpose` with the file content + runtime context as the prompt.

**Phase Transitions:** Slash commands (e.g., `/off`) trigger phase transitions via `user-set-phase.sh` — only the user can run these. All milestone and state commands go through `workflow-cmd.sh`. See the case statement in `workflow-cmd.sh` for the full list of available commands.

## Steps

0. **Pre-validation: Test Evidence Gate** — see `step_0.md`
1. **Plan Validation** — see `step_1.md`
2. **Outcome Validation** — see `step_2.md`
3. **Present Validation Results** — see `step_3.md`
4. **Smart Documentation Detection** — see `step_4.md`
5. **Commit & Push** — see `step_5.md`
6. **Branch Integration & Worktree Cleanup** — see `step_6.md`
7. **Tech Debt Audit** — see `step_7.md`
8. **Handover** — see `step_8.md`
9. **Present Summary and Close** — see `step_9.md`

## Autonomy Behavior

- **auto (▶▶▶):** Make operational decisions autonomously: auto-commit, auto-update docs (yes), auto-select recommended options. Only stop for git push (always requires confirmation) and validation failures that need user judgment.
- **ask (▶▶):** Ask the user at each decision point (doc updates, commit, push, tech debt actions).
- **off (▶):** After each pipeline step (validation, docs, commit, push, tech debt, handover), present the result and wait for explicit approval before proceeding to the next step. Never batch steps.
