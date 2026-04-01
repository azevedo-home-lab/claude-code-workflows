---
description: Toggle debug mode — control WFM observability level
allowed-tools: Bash
---

Toggle WFM debug mode. Three levels control how much hook activity is visible.

## Usage

- `/debug` — show current debug level
- `/debug off` — disable all debug output
- `/debug on` — enable file-only logging (alias for `log`)
- `/debug log` — enable file-only logging (writes to /tmp/wfm-*-debug.log)
- `/debug show` — enable full observability (file logging + inline stderr output)

## Execution

1. If no argument (`$ARGUMENTS` is empty), report current state:

```bash
"${CLAUDE_PLUGIN_ROOT:-$(git rev-parse --show-toplevel)/plugin}"/scripts/workflow-cmd.sh get_debug
```

Report the result:
- "off" — "Debug mode is **off**."
- "log" — "Debug mode is **log** (file only). Logs at `/tmp/wfm-*-debug.log`."
- "show" — "Debug mode is **show** (file + stderr). All WFM decisions appear inline."

2. If argument is `off`:

```bash
"${CLAUDE_PLUGIN_ROOT:-$(git rev-parse --show-toplevel)/plugin}"/scripts/workflow-cmd.sh set_debug "off"
```

Report: "Debug mode **disabled**."

3. If argument is `on` or `log`:

```bash
"${CLAUDE_PLUGIN_ROOT:-$(git rev-parse --show-toplevel)/plugin}"/scripts/workflow-cmd.sh set_debug "log"
```

Report: "Debug mode set to **log**. Hook activity logged to `/tmp/wfm-*-debug.log`."

4. If argument is `show`:

```bash
"${CLAUDE_PLUGIN_ROOT:-$(git rev-parse --show-toplevel)/plugin}"/scripts/workflow-cmd.sh set_debug "show"
```

Report: "Debug mode set to **show**. All WFM gate/coach/phase decisions will appear inline in the conversation."

5. If argument is anything else, report: "Invalid argument. Use `off`, `on`, `log`, `show`, or no argument to check status."
