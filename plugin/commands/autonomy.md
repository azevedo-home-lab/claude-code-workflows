---
description: Set autonomy level (off, ask, auto) — controls how much Claude decides independently
---
!`WF_SKIP_AUTH=1 .claude/hooks/workflow-cmd.sh set_autonomy_level "$ARGUMENTS" && echo "Autonomy level set to $ARGUMENTS"`

Respond based on the level that was set:

- **off**: Call `EnterPlanMode`. Say: "▶ **Supervised** — read-only mode."
- **ask**: Call `ExitPlanMode` if in plan mode. Say: "▶▶ **Semi-Auto** — writes enabled per phase rules. I'll wait for approval at phase transitions."
- **auto**: Call `ExitPlanMode` if in plan mode. Say: "▶▶▶ **Unattended** — full autonomy. I'll auto-transition and auto-commit. Stopping only for user input or before git push."
