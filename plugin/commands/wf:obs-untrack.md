---
description: Stop tracking an observation ID in the workflow status line
---
!`.claude/hooks/workflow-cmd.sh remove_tracked_observation $ARGUMENTS && echo "Stopped tracking observation #$ARGUMENTS"`

Confirm to the user that observation #$ARGUMENTS is no longer tracked.

If the output shows an error, report it. If $ARGUMENTS is empty, say: "Usage: /wf:obs-untrack <observation-id>"
