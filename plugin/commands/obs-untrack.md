---
description: Stop tracking an observation ID in the workflow status line
---
!`.claude/hooks/workflow-cmd.sh remove_tracked_observation "$ARGUMENTS" && echo "Stopped tracking observation #$ARGUMENTS"`

Present the output to the user.

Confirm to the user that observation #$ARGUMENTS is no longer tracked.

If the output shows an error, report it. If $ARGUMENTS is empty, say: "Usage: /obs-untrack <observation-id>"
