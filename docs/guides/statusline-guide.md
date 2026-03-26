# Claude Code Status Line Setup Guide

A minimal, color-coded status bar for Claude Code that shows model, context usage, git branch, and worktree info at a glance.

## What It Shows

```
Opus  │  ▓▓░░░░░░░░ 25%  │   main  │  ~/Projects/MyApp
```

| Element | Description |
|---------|-------------|
| **Model name** | Active model (Opus, Sonnet, Haiku) in bold |
| **Context bar** | 10-char visual gauge with color coding |
| **Git branch** | Current branch with  icon |
| **Worktree** | Worktree name with ⊟ icon (only when active) |
| **Directory** | Shortened working directory path |

### Context Bar Colors

| Color | Usage Range | Meaning |
|-------|-------------|---------|
| Green | 0–49% | Plenty of room |
| Yellow | 50–79% | Getting full, be aware |
| Red | 80–100% | Near limit, expect compression soon |

### With Worktree Active

```
Sonnet  │  ▓▓▓▓▓▓░░░░ 65%  │   feature/auth  ⊟ auth-worktree  │  ~/Projects/MyApp
```

## Prerequisites

- **jq** — JSON processor (used to parse session data from stdin)
  ```bash
  brew install jq        # macOS
  sudo apt install jq    # Debian/Ubuntu
  ```

## Installation

The status line is bundled with the plugin and installed automatically when you run:
```
/plugin install workflow-manager
```

No manual copying or settings.json configuration needed. The status line appears on the next session.

## Testing

Test the script manually by piping sample JSON:

```bash
echo '{"model":{"display_name":"Opus"},"context_window":{"used_percentage":25},"cwd":"/Users/you/project","worktree":{"name":null,"branch":null}}' | ~/.claude/statusline.sh
```

Test with worktree active:

```bash
echo '{"model":{"display_name":"Sonnet"},"context_window":{"used_percentage":65},"cwd":"/Users/you/project","worktree":{"name":"feature-auth","branch":"feature/auth-refactor"}}' | ~/.claude/statusline.sh
```

## Customization

The script is at `~/.claude/statusline.sh`. Common modifications:

- **Change bar length**: Edit `FILLED=$((USED_PCT / 10))` and `EMPTY=$((10 - FILLED))` — divide by 5 for a 20-char bar
- **Change bar characters**: Replace `▓` and `░` with any characters (e.g., `█` and `─`)
- **Change path truncation**: Adjust the `30` in the length check to show more/less of the path
- **Add more info**: Echo additional lines — each `echo`/`printf` creates a new row in the status bar

## Available Session Data

The script receives JSON via stdin with these fields:

| Field | Description |
|-------|-------------|
| `model.display_name` | Human-readable model name |
| `model.id` | Model identifier |
| `context_window.used_percentage` | Context usage as percentage |
| `context_window.context_window_size` | Max context size |
| `cwd` | Current working directory |
| `worktree.name` | Active worktree name (null if none) |
| `worktree.branch` | Worktree git branch (null if none) |
| `cost.total_cost_usd` | Session cost in USD |
| `cost.total_duration_ms` | Total session time |
| `cost.total_lines_added` | Lines added this session |
| `cost.total_lines_removed` | Lines removed this session |
| `session_id` | Unique session identifier |
| `version` | Claude Code version |

## Claude-Mem Observation ID

When the claude-mem MCP server is in use, the status line shows the ID of the most recently accessed observation:

```
Sonnet  │  ▓▓░░░░░░░░ 22%  │   main  │  ~/Projects/MyApp  │  Claude-Mem ✓ #3007
```

| Condition | Display |
|-----------|---------|
| An observation was saved or retrieved this session | `Claude-Mem ✓ #<id>` |
| No observation accessed yet in this session | Nothing shown |

The ID updates each time an observation is saved (`save_observation`) or fetched (`get_observations`). It reflects the last observation ID returned in the MCP response, captured by the PostToolUse hook and written to workflow state.

This is useful for quickly confirming that memory is being written and for cross-referencing a specific observation when debugging or following up in a later session.

## Workflow Autonomy Symbols

When the Workflow Manager is active, the status line displays a symbol indicating the current autonomy level:

| Symbol | Level | Name | Behavior |
|--------|-------|------|----------|
| `▶` | off | Supervised | All writes blocked regardless of phase. Claude can only read files and research. |
| `▶▶` | ask | Semi-Auto | Writes follow phase rules. Stops at phase transitions for user approval. |
| `▶▶▶` | auto | Unattended | Full autonomy within phase rules. Auto-transitions, auto-commits. |

No symbol is shown when the workflow is OFF or when the autonomy field is absent from state.

Set the level with `/autonomy off`, `/autonomy ask`, or `/autonomy auto`. Only the user can change it.

## Files

| File | Purpose |
|------|---------|
| [`plugin/statusline/statusline.sh`](../../plugin/statusline/statusline.sh) | The status line script (installed to `~/.claude/statusline.sh` by setup hook) |
