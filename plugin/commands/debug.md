---
description: Toggle debug mode — show/hide hook messages to user
allowed-tools: Bash
---

Toggle WFM debug mode. When enabled, all hook coaching messages and gate decisions are shown to the user (not just to Claude).

## Usage

- `/debug on` — enable debug output
- `/debug off` — disable debug output
- `/debug` — show current debug state

## Execution

1. If no argument (`$ARGUMENTS` is empty), report current state:

```bash
.claude/hooks/workflow-cmd.sh get_debug
```

Report: "Debug mode is **on/off**."

2. If argument is `on`:

```bash
.claude/hooks/workflow-cmd.sh set_debug "true"
```

Report: "Debug mode **enabled**. Hook messages will now be visible to you."

3. If argument is `off`:

```bash
.claude/hooks/workflow-cmd.sh set_debug "false"
```

Report: "Debug mode **disabled**. Hook messages are now Claude-only."

4. If argument is anything else, report: "Invalid argument. Use `on`, `off`, or no argument to check status."
