Set the Workflow Manager autonomy level. This controls how much independence Claude has during the workflow.

**Levels:**
- `off` (▶ Supervised): Read-only. Local research only, no file writes, no web access.
- `ask` (▶▶ Semi-Auto): Writes allowed per phase rules. Stops at each phase transition for user approval.
- `auto` (▶▶▶ Unattended): Full autonomy. Auto-transitions between phases, auto-commits. Stops only for user input in DISCUSS/DEFINE and before git push.

## Usage

```
/autonomy off|ask|auto
```

## Execution

Run this to set the level:

```bash
# Normalize legacy numeric values
LEVEL="$ARGUMENTS"
case "$LEVEL" in
    1) LEVEL="off" ;;
    2) LEVEL="ask" ;;
    3) LEVEL="auto" ;;
esac
WF="$CLAUDE_PROJECT_DIR/.claude/hooks/workflow-cmd.sh" && "$WF" set_autonomy_level "$LEVEL" && echo "Autonomy level set to $LEVEL"
```

Then apply the corresponding behavior:

**If level is off:** Enter plan mode by calling the `EnterPlanMode` tool. This blocks all write operations at the Claude Code level. Confirm: "▶ **Supervised** — read-only mode. I can research and explore but cannot modify files. Run `/autonomy ask` to enable writes."

**If level is ask:** If you are currently in plan mode, call `ExitPlanMode`. Confirm: "▶▶ **Semi-Auto** — writes enabled per phase rules. I'll propose phase transitions and wait for your approval."

**If level is auto:** If you are currently in plan mode, call `ExitPlanMode`. Confirm: "▶▶▶ **Unattended** — full autonomy. I'll auto-transition between phases and auto-commit. I'll stop only when I need your input or before git push. Note: ensure your `settings.local.json` includes Bash, WebFetch, WebSearch, and MCP tools in the allow list for fully unattended operation."

**Important:** Only the user can run this command. If you think a different level would be appropriate, suggest it: "This task would benefit from auto — run `/autonomy auto` if you'd like to proceed unattended." Do NOT invoke this command yourself.
