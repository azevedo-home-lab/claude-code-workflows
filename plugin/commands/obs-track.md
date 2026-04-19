---
description: Track an observation ID in the workflow status line
---
!`"${CLAUDE_SKILL_DIR}/../scripts/workflow-cmd.sh" add_tracked_observation "$ARGUMENTS" && echo "Now tracking observation #$ARGUMENTS"`

Confirm to the user that observation #$ARGUMENTS is now tracked and will appear in the status line.

If the output shows an error, report it. If $ARGUMENTS is empty, say: "Usage: /obs-track <observation-id>"
