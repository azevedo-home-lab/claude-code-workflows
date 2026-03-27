---
description: Set autonomy level (off, ask, auto) — controls how much Claude decides independently
disable-model-invocation: true
---
<!-- Do NOT invoke this command via the Skill tool. Use the native /command path only. -->
!`WF_SKIP_AUTH=1 .claude/hooks/workflow-cmd.sh set_autonomy_level "$ARGUMENTS" && echo "Autonomy level set to $ARGUMENTS"`

Present the output to the user.

Respond based on the level that was set:

- **off**: Say: "▶ **Supervised** — step-by-step mode. I'll work within phase rules and pause after each plan step for your review."
- **ask**: Call `ExitPlanMode` if in plan mode. Say: "▶▶ **Semi-Auto** — writes enabled per phase rules. I'll wait for approval at phase transitions."
- **auto**: Call `ExitPlanMode` if in plan mode. Say: "▶▶▶ **Unattended** — full autonomy. I'll auto-transition and auto-commit. Stopping only for user input or before git push."
