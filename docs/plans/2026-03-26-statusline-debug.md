# Status Line Improvements & Debug Command — Design Spec

**Date:** 2026-03-26
**Issues:** #4194.4 (version display), #4194.5 (color thresholds), #4234 (debug command)
**Version target:** 1.8.0

## Problem

Three usability gaps in the current workflow system:

1. **No CC version in status line.** Users can't see which Claude Code version they're running without typing `claude --version`. The session JSON provides a `version` field that isn't used.

2. **Yellow context bar unreadable on white backgrounds.** The mid-range color (50-80% usage) is yellow, which has poor contrast on light terminal themes.

3. **Hook messages invisible to users.** All PostToolUse coaching (3 layers) uses `systemMessage` — visible to Claude but not the user. PreToolUse allow decisions are also invisible. Users have no way to see what the hooks are doing, making the system opaque and hard to debug.

## Design

### Feature 1: CC Version Display

**Source:** `version` field from CC session JSON (top-level string, e.g. `"1.0.80"`).

**Display:** `CC X.Y.Z` as the first element in the status bar, before the model name.

**Implementation:**
- Add `.version` to the existing jq parse call in `statusline.sh` (line 14-24)
- Display with bold formatting: `${BOLD}CC ${CC_VERSION}${RESET}`
- Separator before model: `${DIM}│${RESET}`

**Result:** `CC 2.1.83  │  Opus 4.6 (1M context)  │  ▓▓▓░░░░░░░ 28%  │  ...`

### Feature 2: Context Bar Colors

**Change:** Replace the yellow mid-range with blue. Adjust thresholds downward for earlier warning.

| Range | Current | New |
|-------|---------|-----|
| Low usage | Blue (<50%) | Green (<30%) |
| Mid usage | Yellow (50-80%) | Blue (30-60%) |
| High usage | Red (≥80%) | Red (≥60%) |

**Implementation:** Modify the color selection block in `statusline.sh` (lines 38-44). Change threshold values and color variables. No new dependencies.

### Feature 3: `/wf:debug` Command

#### State

New `debug` boolean field in `workflow.json`. Default: `false`. Preserved across phase transitions.

#### State helpers (`workflow-state.sh`)

```bash
get_debug()  # Returns "true" or "false"
set_debug()  # Sets the debug flag (no intent authorization — developer tool)
```

The `debug` field is added to `_read_preserved_state()` and the `set_phase()` jq template so it persists across phase transitions. Cleared when phase goes to `off` (same lifecycle as autonomy_level).

#### Command file (`plugin/commands/wf:debug.md`)

Accepts `on` or `off` argument. Calls `set_debug` via `workflow-cmd.sh`. Reports current state if no argument given.

No intent authorization required — debug is a developer tool, not a security-sensitive state change. Unlike phase and autonomy changes, debug doesn't affect enforcement behavior.

#### Hook changes — output mechanism

**Key constraint:** CC's PostToolUse hook protocol only supports `systemMessage` in the JSON response. There is no `userMessage` field.

**Mechanism:** When `debug=true`, hooks write debug output to **stderr**, which CC displays to the user as hook output. The existing `systemMessage` JSON continues to work for Claude. This gives dual visibility:
- Claude sees the coaching via `systemMessage` (unchanged)
- User sees the debug output via stderr (new)

**Format:** All debug lines prefixed with `[WFM DEBUG]` for easy identification.

#### `post-tool-navigator.sh` changes

When debug=true:
- **Layer 1** (phase entry): Echo the phase entry message to stderr
- **Layer 2** (standards reinforcement): Echo the trigger type and coaching message to stderr
- **Layer 3** (anti-laziness): Echo the check that fired and the message to stderr
- **No-fire cases**: Echo `[WFM DEBUG] PostToolUse: <tool_name> — no coaching triggered` to stderr

**Implementation:** Read debug flag once near the top (after STATE_FILE check). At each message output point, conditionally `echo >&2`.

#### `workflow-gate.sh` changes

When debug=true:
- **Allow decisions**: Echo `[WFM DEBUG] PreToolUse ALLOW: <tool_name> on <file_path> — phase <phase>, path whitelisted` to stderr
- **Deny decisions**: Already visible to user (they block the tool). Add debug echo for consistency.

**Implementation:** Read debug flag after sourcing workflow-state.sh. Add stderr echo at each exit point.

#### `bash-write-guard.sh` changes

When debug=true:
- **Allow decisions**: Echo `[WFM DEBUG] Bash ALLOW: <reason>` to stderr (e.g., "read-only command", "git commit", "whitelisted path", "implement/review phase")
- **Deny decisions**: Already visible. Add debug echo for consistency.

**Implementation:** Same pattern as workflow-gate.sh.

#### Status line indicator

When debug=true and phase is not OFF, show `[DEBUG]` after the phase badge in the status line:

`Workflow Manager 1.7.0 ✓ ▶▶ [DISCUSS] [DEBUG]`

Color: bold yellow (acceptable here since it's a short label on the green WM background, not a full bar).

#### `setup.sh` — no changes needed

Section E already auto-installs all `*.md` files from `plugin/commands/` via a glob loop. Creating `wf:debug.md` in `plugin/commands/` is sufficient.

#### Test coverage

- State helpers: `get_debug` returns false by default, `set_debug` toggles, preserved across phase transitions, cleared on OFF
- Command: `/wf:debug on` enables, `/wf:debug off` disables, `/wf:debug` (no arg) reports status
- Status line: DEBUG indicator shown when flag is true
- Hook stderr output: Verify debug output appears on stderr when flag is true (integration test)

## Files Modified

| File | Change |
|------|--------|
| `plugin/statusline/statusline.sh` | Add CC version, change colors, add DEBUG indicator |
| `plugin/scripts/workflow-state.sh` | Add `get_debug`, `set_debug`, preserve across transitions |
| `plugin/scripts/workflow-cmd.sh` | Add `get_debug` and `set_debug` command handlers |
| `plugin/scripts/post-tool-navigator.sh` | Add debug stderr output |
| `plugin/scripts/workflow-gate.sh` | Add debug stderr output |
| `plugin/scripts/bash-write-guard.sh` | Add debug stderr output |
| `plugin/commands/wf:debug.md` | New command file |
| `tests/run-tests.sh` | New tests for all three features |

## Scope boundaries

**In scope:** The three features described above.
**Out of scope:** Rate limit display, cost display, session ID, transcript path, or any other new status line elements from the session JSON. These can be considered in future work.

## Trade-offs

- **Debug stderr output adds ~1 jq read per hook invocation** when debug is on. Negligible performance impact since it reads a field from an already-loaded JSON file.
- **Debug flag cleared on OFF** means users must re-enable it each workflow cycle. This is intentional — debug is for active troubleshooting, not permanent state.
- **No granularity in debug output** (e.g., "only coaching" vs "only gates"). Keeps the feature simple. If granularity is needed later, the single boolean can be expanded to a bitmask or enum.


## Decision Record (Archived)

# Decision Record — Status Line Improvements & Debug Command

**Date:** 2026-03-26
**Issues:** #4194.4, #4194.5, #4234
**Spec:** `docs/superpowers/specs/2026-03-26-statusline-debug-design.md`

## Problem

Three usability gaps:
1. No CC version visible in status line — users can't see their Claude Code version at a glance.
2. Yellow context bar unreadable on white terminal backgrounds.
3. Hook coaching messages invisible to users — system is opaque and undebuggable.

### Outcomes
- CC version displayed as first status bar element
- Context bar readable on both light and dark terminals
- Users can toggle visibility of all hook messages via `/wf:debug on|off`

## Approaches Considered (DISCUSS phase — diverge)

### Feature 1: CC Version
Single approach — read `version` from CC session JSON. No alternatives needed.

### Feature 2: Context Bar Colors
Single approach — replace yellow with blue, adjust thresholds. User specified: green <30%, blue 30-60%, red >=60%.

### Feature 3: Debug Command

#### Approach A: PostToolUse dual output via stderr (chosen)
- Hook scripts echo debug messages to stderr (visible to user) alongside existing systemMessage JSON (visible to Claude)
- Debug state stored as boolean in workflow.json
- **Pros:** Output appears in the conversation where the user is looking. Simple implementation.
- **Cons:** Every hook reads one extra JSON field when debug is on (negligible).

#### Approach B: Separate debug log file
- Write all decisions to `~/.claude/state/wfm-debug.log`, user reads via `tail -f`
- **Pros:** No risk of interfering with hook JSON protocol.
- **Cons:** Requires second terminal. User misses real-time context. File rotation complexity.

## Decision (DISCUSS phase — converge)

- **Chosen approach:** Approach A for debug, direct implementation for version and colors
- **Rationale:** All three features are small, well-scoped, and independent. Debug via stderr keeps output where the user is looking.
- **Trade-offs accepted:** Debug flag cleared on OFF (users re-enable per cycle). No debug granularity (all-or-nothing).
- **Risks identified:** stderr behavior in CC hooks needs verification — if CC doesn't show hook stderr, we pivot to Approach B.
- **Constraints applied:** CC session JSON schema provides version field. Terminal color codes must work on both light and dark themes.
- **Tech debt acknowledged:** None introduced.

## Review Findings (REVIEW phase)

**5 review agents dispatched, 4 false positives filtered, 11 unique confirmed findings.**

### Fixed (this session)
- [QUAL] Redundant `if [ -f STATE_FILE ]` guard in workflow-gate.sh and bash-write-guard.sh — removed
- [QUAL] Vestigial `get_phase` call in wf:debug.md Step 1 — removed
- [QUAL] `get_debug` called before OFF-phase exit — moved after exit for efficiency
- [ARCH/GOV] Missing temp dir cleanup in debug indicator tests — added `rm -rf`

### Pre-existing tech debt (not introduced by this change)
- [SEC] `_update_state` jq filter interpolation is fragile against future callers (workflow-state.sh:47-56)
- [HYG] `pushed` completion field written but never checked by exit gate (complete.md:257)
- [HYG] `_plugin_version` function duplicated in test suite (tests/run-tests.sh:2372-2384)

### Dismissed as false positive
- SEC: `WF_SKIP_AUTH=1` is a production mechanism (used by 8 command files), not a test backdoor
- GOV: `allowed-tools: Bash` in wf:debug.md is intentionally different from other commands
- CQ: Missing tests for error paths is a coverage suggestion, not a code defect
- ARCH: Version bump without plan step is an informational process note
