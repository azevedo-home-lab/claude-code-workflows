---
description: Read an observation by ID from claude-mem
---
Read observation #$ARGUMENTS from claude-mem and display it.

Use the `get_observations` MCP tool with IDs: [$ARGUMENTS]. Present the observation's title, type, date, and narrative to the user in a readable format.

If $ARGUMENTS is empty, say: "Usage: /obs-read <observation-id>"
