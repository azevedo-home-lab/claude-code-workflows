Transition the workflow to OFF phase. Run this command:

```bash
WF="$(git rev-parse --show-toplevel)/.claude/hooks/workflow-cmd.sh" && "$WF" set_phase "off" && echo "Phase set to OFF — workflow enforcement disabled."
```

Confirm to the user that the workflow is closed and enforcement is disabled.
