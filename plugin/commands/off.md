Transition the workflow to OFF phase. Run this command:

```bash
WF="${CLAUDE_PLUGIN_ROOT}/scripts/workflow-cmd.sh" && "$WF" set_phase "off" && echo "Phase set to OFF — workflow enforcement disabled."
```

Confirm to the user that the workflow is closed and enforcement is disabled.
