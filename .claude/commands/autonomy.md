---
description: Set autonomy level (off, ask, auto) — controls how much Claude decides independently
disable-model-invocation: true
---
<!-- Do NOT invoke this command via the Skill tool. Use the native /command path only. -->
!`"${CLAUDE_PLUGIN_ROOT:-$(git rev-parse --show-toplevel)/plugin}"/scripts/workflow-cmd.sh set_autonomy_level "$ARGUMENTS" && echo "Autonomy level set to $ARGUMENTS"`

Respond based on the level that was set:

- **off**: Say: "▶ **Supervised** — step-by-step mode. I'll work within phase rules and pause after each plan step for your review."
- **ask**: Call `ExitPlanMode` if in plan mode. Say: "▶▶ **Semi-Auto** — writes enabled per phase rules. I'll wait for approval at phase transitions."
- **auto**: Call `ExitPlanMode` if in plan mode. Say: "▶▶▶ **Unattended** — full autonomy. I'll auto-transition and auto-commit. Stopping only for user input or before git push." Then check current phase milestones via Bash tool (`"$(git rev-parse --show-toplevel)/plugin/scripts/workflow-cmd.sh" get_<phase>_field`). If all milestones for the current phase are met, auto-transition via Bash tool (`"$(git rev-parse --show-toplevel)/plugin/scripts/workflow-cmd.sh" agent_set_phase "<next_phase>"`). If milestones are incomplete, resume the current phase's work where it left off. Do not wait for user input unless genuinely blocked or you have legitimate questions.
