---
description: Close the workflow and disable phase enforcement
disable-model-invocation: true
---
<!-- Do NOT invoke this command via the Skill tool. Use the native /command path only. -->
!`WF_SKIP_AUTH=1 .claude/hooks/workflow-cmd.sh set_phase "off" && echo "Phase set to OFF — workflow enforcement disabled."`

Confirm to the user that the workflow is closed and enforcement is disabled.
