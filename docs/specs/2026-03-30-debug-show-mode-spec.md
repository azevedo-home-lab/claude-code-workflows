# Spec: Debug Show Mode — Full WFM Observability

## Overview

Extend debug mode from binary (`off/on`) to three levels (`off/log/show`). In `show` mode, all 10 WFM components emit inline output visible in the conversation via hook stdout/stderr.

## Debug Levels

| Level | Behavior |
|-------|----------|
| `off` | Silent. No debug output. |
| `log` | Write to `/tmp/wfm-<caller>-debug.log` only (current `on` behavior). |
| `show` | Write to log files AND emit to stderr (shown inline in conversation). |

## State Change

`workflow.json` field: `"debug"` changes from `true/false` to `"off"|"log"|"show"`.

Backwards compatibility:
- `true` → treated as `"log"`
- `false` → treated as `"off"`
- Missing → treated as `"off"`

## `/debug` Command Updates

```
/debug           → show current level
/debug off       → set to off
/debug log       → set to log (file only)
/debug show      → set to show (file + inline)
/debug on        → alias for "log" (backwards compat)
```

## Output Format

All inline output uses a consistent prefix format:

```
[WFM <component>] <ACTION> <details>
```

Components and their prefixes:

| Prefix | Source Script |
|--------|-------------|
| `[WFM gate]` | workflow-gate.sh |
| `[WFM bash]` | bash-write-guard.sh |
| `[WFM coach]` | post-tool-navigator.sh |
| `[WFM cmd]` | workflow-cmd.sh |
| `[WFM phase]` | user-set-phase.sh |
| `[WFM state]` | workflow-state.sh |
| `[WFM status]` | statusline.sh |
| `[WFM agent]` | workflow-cmd.sh (dispatch_agent) |
| `[WFM skill]` | workflow-cmd.sh (resolve_skill) |

## Component Instrumentation

### 1. debug-log.sh — Core logging module

Add `debug_show()` function:
- If level=`show`: write to log file AND emit to stderr
- If level=`log`: write to log file only
- If level=`off`: no output
- Add `get_debug_level()` helper that handles backwards compat (`true`→`log`, `false`→`off`)

### 2. workflow-gate.sh (PreToolUse: Write/Edit)

Log on every invocation:
```
[WFM gate] ALLOW Write plugin/coaching/foo.md — path whitelisted (docs/*)
[WFM gate] DENY Edit plugin/scripts/workflow-gate.sh — guard self-protection
[WFM gate] ALLOW Edit src/app.ts — phase=IMPLEMENT allows all writes
[WFM gate] SKIP — phase=OFF, no enforcement
```

### 3. bash-write-guard.sh (PreToolUse: Bash)

Log on every invocation:
```
[WFM bash] ALLOW git commit -m "docs: add spec"
[WFM bash] DENY sed -i 's/foo/bar/' file.ts — inplace editor blocked in DISCUSS
[WFM bash] ALLOW .claude/hooks/workflow-cmd.sh set_discuss_field — workflow command
[WFM bash] DENY git reset --hard — destructive git operation blocked
[WFM bash] SKIP — phase=OFF, no enforcement
```

### 4. post-tool-navigator.sh (PostToolUse: all tools)

Log coaching evaluation:
```
[WFM coach] Tool: Agent (phase=DISCUSS)
[WFM coach] L1: phase entry message — already shown, skipped
[WFM coach] L2: evaluated agent_return_discuss — FIRED (first agent return in phase)
[WFM coach] L2: evaluated plan_write_discuss — skipped (not a plan write tool)
[WFM coach] L3: short_agent_prompt=NO, generic_commit=NO, stalled_auto=NO
[WFM coach] Counters: calls_since_nudge=5, total_calls=12
```

### 5. workflow-cmd.sh (agent state operations)

Log every command invocation:
```
[WFM cmd] set_discuss_field("research_done", "true") — was: unset
[WFM cmd] get_phase() → "discuss"
[WFM cmd] agent_set_phase("implement") — DENIED: approach_selected not set
[WFM cmd] check_soft_gate("implement") → WARN: no plan registered
[WFM cmd] increment_coaching_counter() → 6
```

### 6. user-set-phase.sh (user phase transitions)

Log the full transition:
```
[WFM phase] User transition: DISCUSS → IMPLEMENT
[WFM phase] State rebuilt — preserved: plan_path=docs/plans/foo.md, autonomy=off, debug=show
[WFM phase] Milestones reset: discuss={}, implement={}, review={}, completion={}
```

### 7. workflow-state.sh (state persistence)

Log state mutations (writes only, not reads — reads would be too noisy):
```
[WFM state] SET discuss.research_done = true (was: null)
[WFM state] SET phase = "implement" (was: "discuss")
[WFM state] SET message_shown = false (phase transition reset)
```

### 8. statusline.sh (status line assembly)

Log what was read (once per render):
```
[WFM status] Read: phase=discuss, autonomy=off, debug=show, skill=brainstorming, obs=#5041, tracked=[#5453]
```

### 9. workflow-cmd.sh dispatch_agent (NEW)

New command: `dispatch_agent <agent-name>`

```bash
.claude/hooks/workflow-cmd.sh dispatch_agent "code-quality-reviewer"
```

Output:
```
[WFM agent] Loaded plugin/agents/code-quality-reviewer.md (2.1k chars)
[WFM agent] Dispatching as: general-purpose
```

Returns: the file content to stdout (so Claude can use it in the agent prompt). Debug output goes to stderr.

### 10. workflow-cmd.sh resolve_skill (NEW)

New command: `resolve_skill <operation-name>`

```bash
.claude/hooks/workflow-cmd.sh resolve_skill "tdd"
```

Output:
```
[WFM skill] Lookup: "tdd" in skill-registry.json
[WFM skill] Resolved: superpowers:test-driven-development
```

Returns: the resolved skill name to stdout. Debug output goes to stderr.

## Implementation Order

1. Update `debug-log.sh` — new `debug_show()` + `get_debug_level()` with backwards compat
2. Update `workflow-state.sh` — state mutation logging
3. Update `workflow-cmd.sh` — command logging + two new commands (`dispatch_agent`, `resolve_skill`)
4. Update `workflow-gate.sh` — gate decision logging
5. Update `bash-write-guard.sh` — bash guard logging
6. Update `post-tool-navigator.sh` — coaching evaluation logging
7. Update `user-set-phase.sh` — phase transition logging
8. Update `statusline.sh` — state read logging
9. Update `plugin/commands/debug.md` — new command syntax
10. Update status line `[DEBUG]` badge to show level: `[DEBUG:show]` or `[DEBUG:log]`

## Testing

- `/debug show` then trigger each component — verify inline output appears
- `/debug log` — verify output only in log files, not inline
- `/debug off` — verify silence
- Backwards compat: manually set `"debug": true` in state file, verify treated as `log`
- New commands: `dispatch_agent` with valid/invalid agent name, `resolve_skill` with valid/invalid operation
