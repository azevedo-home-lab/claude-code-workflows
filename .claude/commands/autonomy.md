Set the Workflow Manager autonomy level. This controls how much independence Claude has during the workflow.

**Levels:**
- `1` (▶ Supervised): Read-only. Local research only, no file writes, no web access.
- `2` (▶▶ Semi-Auto): Writes allowed per phase rules. Stops at each phase transition for user approval.
- `3` (▶▶▶ Unattended): Full autonomy. Auto-transitions between phases, auto-commits. Stops only for user input in DISCUSS/DEFINE and before git push.

## Usage

```
/autonomy 1|2|3
```

## Execution

Run this to set the level:

```bash
WF_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}" && "$WF_DIR/.claude/hooks/workflow-cmd.sh" set_autonomy_level "$ARGUMENTS"
echo "Autonomy level set to $ARGUMENTS"
```

Then apply the corresponding behavior:

**If level is 1:** Enter plan mode by calling the `EnterPlanMode` tool. This blocks all write operations at the Claude Code level. Confirm: "▶ **Supervised** — read-only mode. I can research and explore but cannot modify files. Run `/autonomy 2` to enable writes."

**If level is 2:** If you are currently in plan mode, call `ExitPlanMode`. Confirm: "▶▶ **Semi-Auto** — writes enabled per phase rules. I'll propose phase transitions and wait for your approval."

**If level is 3:** If you are currently in plan mode, call `ExitPlanMode`. Confirm: "▶▶▶ **Unattended** — full autonomy. I'll auto-transition between phases and auto-commit. I'll stop only when I need your input or before git push. Note: ensure your `settings.local.json` includes Bash, WebFetch, WebSearch, and MCP tools in the allow list for fully unattended operation."

**Important:** Only the user can run this command. If you think a different level would be appropriate, suggest it: "This task would benefit from Level 3 — run `/autonomy 3` if you'd like to proceed unattended." Do NOT invoke this command yourself.
