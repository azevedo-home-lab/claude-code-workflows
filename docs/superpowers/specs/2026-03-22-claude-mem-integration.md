# Claude-Mem Integration Improvements

## Problem

Claude-mem observations are not consistently scoped to the current project. Commands that search or save observations don't always pass the `project` parameter, causing results from different projects to mix. Additionally, the status line shows only whether claude-mem is available (✓/✗) but not which observation was last used, making it hard to track what context is being referenced.

## Outcomes

1. All claude-mem calls (search, save, get, timeline) enforce the GitHub repo name as the `project` parameter
2. The repo name is derived from `git remote get-url origin`, not hardcoded
3. Layer 3 coaching fires when `save_observation` is called without a `project` field
4. Status line shows the last observation ID read or written (e.g., `Claude-Mem ✓ #3007`)
5. The observation ID is tracked in `workflow.json` and updated by the PostToolUse hook
