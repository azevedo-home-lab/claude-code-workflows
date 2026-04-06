# Fix: Remove Stale Hook Registrations from Settings Files

**Date:** 2026-04-06
**Status:** Planned
**Priority:** Critical — causes hook errors in every non-ClaudeWorkflows project

## Problem

Every Claude Code session in every project shows `PreToolUse:Bash hook error` and `PostToolUse:Bash hook error` on every tool use. The errors come from stale hook registrations in `~/.claude/settings.json` (user-level) and individual project `.claude/settings.json` files.

### How the errors manifest

In projects other than ClaudeWorkflows (e.g., homelab-infra):
1. `~/.claude/settings.json` defines hooks pointing to `$CLAUDE_PROJECT_DIR/.claude/hooks/<script>.sh`
2. The `.claude/hooks/` directory contains **old copies** of hook scripts from a previous plugin version
3. These old scripts lack the defensive guard (`[ -z "${CLAUDE_PLUGIN_ROOT:-}" ] && [ ! -d "$_self_dir/infrastructure" ] && exit 0`) added in v2.2.0
4. The old scripts try to `source "$SCRIPT_DIR/infrastructure/hook-preamble.sh"` which doesn't exist in the project context
5. The scripts crash, producing "hook error" messages

In the ClaudeWorkflows project specifically:
- `.claude/hooks/` has current copies (matching plugin cache) with the defensive guard
- The guard makes them exit silently, so no visible errors
- But each hook fires **twice** per tool use: once from `settings.json` (exits silently), once from `hooks.json` (does real work)

### How the stale hooks got there

**Old setup.sh (pre-v2.2.0) section D** registered hooks in `$PROJECT_DIR/.claude/settings.json` using jq:
```bash
jq '.hooks.PreToolUse = [
  {"matcher": "Write|Edit|MultiEdit|NotebookEdit", "hooks": [{"type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/pre-tool-write-gate.sh"}]},
  {"matcher": "Bash", "hooks": [{"type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/pre-tool-bash-guard.sh"}]}
]' "$PROJECT_SETTINGS"
```
This code was removed in commit `de02b93` when hooks.json became the deployment mechanism. But it only ever wrote to **project** settings.

**The user-level hooks** (`~/.claude/settings.json`) were NOT written by setup.sh (confirmed: git history shows setup.sh never wrote hooks to `$GLOBAL_SETTINGS`). They were likely written by a Claude session that was asked to fix hook issues and edited the wrong file, or by manual troubleshooting. The exact origin is unclear, but they exist and cause errors globally.

### Why previous fixes failed

| Session | What it did | Why it didn't stick |
|---------|-------------|---------------------|
| Apr 5, #6138 (6:26 PM) | Claimed "cleared hooks from user settings.json" | Observation's `files_modified` is empty — the edit may not have actually happened |
| Apr 5, #6150 (6:30 PM) | Removed hooks from **project** settings.json | Correct for project, but didn't address user-level settings |
| Apr 5, #6158 (6:37 PM) | Concluded Claude Code "materializes" hooks from hooks.json into settings.json at session start | **This was wrong.** See debunked hypothesis below |
| Apr 5, setup.sh A2 comment | Removed cleanup code, added comment saying "duplicate invocation is harmless" | Based on #6158's incorrect conclusion |

### Debunked hypothesis: "Claude Code re-materializes hooks"

Observation #6158 claimed Claude Code copies hooks from `hooks.json` into `settings.json` and `.claude/hooks/` at every session start. This was used to justify abandoning cleanup ("if the platform re-creates them, why bother?").

**Evidence that disproves this:**

1. **homelab-infra hooks are stale.** MD5 hash `5bd2dc3...` differs from current plugin cache `d46810f...`. If Claude Code re-materialized from hooks.json, they'd match.
2. **homelab-infra hooks lack the v2.2.0 defensive guard.** They have the old `SCRIPT_DIR="${CLAUDE_PROJECT_DIR}/plugin/scripts"` pattern. Current hooks.json-deployed scripts use `CLAUDE_PLUGIN_ROOT`.
3. **The paths don't match.** `hooks.json` uses `${CLAUDE_PLUGIN_ROOT}/scripts/...` paths. `settings.json` uses `$CLAUDE_PROJECT_DIR/.claude/hooks/...` paths. If one were derived from the other, the paths would correspond.
4. **homelab-infra settings.json was last modified Apr 5 11:14.** If Claude Code re-wrote it at session start today (Apr 6 08:18), the mtime would be today.

The timestamp coincidence that led to this hypothesis (`.claude/hooks/` files showing today's date) is likely caused by Google Drive sync metadata updates or setup.sh's cache sync touching related files.

## Root Cause

Two independent hook registration systems are active simultaneously:

1. **`hooks.json`** (correct) — plugin hooks with `${CLAUDE_PLUGIN_ROOT}` paths, auto-wired by Claude Code, working correctly
2. **`settings.json`** (stale) — legacy hooks with `$CLAUDE_PROJECT_DIR/.claude/hooks/` paths, written by old setup.sh and/or manual edits, causing errors

The stale system was never fully cleaned because:
- The cleanup code in setup.sh was removed based on the incorrect "re-materialization" hypothesis
- Previous cleanup sessions fixed project settings but missed user settings (or the edit didn't persist)
- The defensive guard in v2.2.0 scripts masked the problem in ClaudeWorkflows but doesn't help other projects with older copies

## Fix

### Step 1: Remove stale hooks from user-level settings

Edit `~/.claude/settings.json` — delete the entire `hooks` key (lines 28-58).

**Verification:** `jq 'has("hooks")' ~/.claude/settings.json` should return `false`.

### Step 2: Remove stale hooks from ClaudeWorkflows project settings

Edit `/Users/pedroazevedo/Documents/GDrive/Projects/ClaudeWorkflows/.claude/settings.json` — delete the entire `hooks` key.

**Verification:** `jq 'has("hooks")' .claude/settings.json` should return `false`.

### Step 3: Remove stale hooks from homelab-infra project settings

Edit `/Users/pedroazevedo/Documents/GDrive/Projects/homelab-infra/.claude/settings.json` — delete the entire `hooks` key.

Also delete the stale `.claude/hooks/` directory in homelab-infra (it contains old script copies without the defensive guard).

**Verification:** No `.claude/hooks/` directory. `jq 'has("hooks")' .claude/settings.json` should return `false`.

### Step 4: Add migration cleanup to setup.sh

Restore active cleanup code in setup.sh section A2. The code should:

1. Remove `hooks` key from `~/.claude/settings.json` (user-level) if it contains `$CLAUDE_PROJECT_DIR/.claude/hooks/` paths
2. Remove `hooks` key from `$PROJECT_DIR/.claude/settings.json` (project-level) if it contains `.claude/hooks/` paths
3. Remove `$PROJECT_DIR/.claude/hooks/` directory if it exists and contains only WFM scripts (preserve user's own hooks)
4. Replace the "harmless duplicate" comment with documentation explaining the cleanup and why re-materialization is a debunked hypothesis

The cleanup must be **targeted** — only remove hooks that match the known stale pattern (`$CLAUDE_PROJECT_DIR/.claude/hooks/`). Do not blindly `del(.hooks)` as users may have their own legitimate hooks in settings.json.

```bash
# Pattern to match: hooks referencing .claude/hooks/ directory (our stale copies)
# Safe: only removes WFM-originated hooks, preserves user hooks
_STALE_HOOK_PATTERN='.claude/hooks/(pre-tool-write-gate|pre-tool-bash-guard|post-tool-coaching)\.sh'

for _settings_file in "$HOME/.claude/settings.json" "$PROJECT_SETTINGS" "$PROJECT_DIR/.claude/settings.local.json"; do
  [ -f "$_settings_file" ] || continue
  if grep -qE "$_STALE_HOOK_PATTERN" "$_settings_file" 2>/dev/null; then
    # Remove only hook entries that reference our stale scripts
    # If no hooks remain after removal, delete the hooks key entirely
    jq '
      def remove_stale:
        if type == "array" then
          [.[] | select(.hooks // [] | all(.command | test("\\.claude/hooks/(pre-tool-write-gate|pre-tool-bash-guard|post-tool-coaching)\\.sh") | not))]
        else . end;
      if .hooks then
        .hooks |= with_entries(
          .value |= remove_stale | select(.value | length > 0)
        ) |
        if (.hooks | length) == 0 then del(.hooks) else . end
      else . end
    ' "$_settings_file" > "$_settings_file.tmp" && mv "$_settings_file.tmp" "$_settings_file"
  fi
done

# Remove stale .claude/hooks/ copies (only WFM scripts, not user hooks)
_HOOKS_DIR="$PROJECT_DIR/.claude/hooks"
if [ -d "$_HOOKS_DIR" ]; then
  for _hook in pre-tool-write-gate.sh pre-tool-bash-guard.sh post-tool-coaching.sh; do
    rm -f "$_HOOKS_DIR/$_hook"
  done
  # Remove directory only if empty (preserves user's own hooks)
  rmdir "$_HOOKS_DIR" 2>/dev/null || true
fi
```

### Step 5: Update setup.sh comments

Replace the "harmless duplicate" rationale in section A2 (lines 135-139) with:

```bash
# Migration: remove stale hook registrations left by pre-2.2.0 setup.sh.
# Old versions copied scripts to .claude/hooks/ and registered them in
# settings.json with $CLAUDE_PROJECT_DIR paths. These stale entries cause
# errors in projects where the scripts don't exist or are outdated.
# The correct mechanism is hooks.json with ${CLAUDE_PLUGIN_ROOT} (set by
# Claude Code only for plugin hooks, not project hooks).
# NOTE: A previous hypothesis claimed Claude Code "re-materializes" hooks
# from hooks.json into settings.json, making cleanup futile. This was
# debunked — see docs/plans/2026-04-06-stale-hook-cleanup.md.
```

### Step 6: Keep defensive guards in hook scripts

The `exit 0` guards in the three hook scripts remain as a safety net. They handle any future edge case where a stale copy exists but infrastructure/ doesn't.

### Step 7: Verify docs are consistent

`docs/reference/hooks.md` and `docs/reference/architecture.md` already document the correct architecture. No changes needed.

## Verification Checklist

After applying the fix, verify in a **new session** (not the current one):

- [ ] `jq 'has("hooks")' ~/.claude/settings.json` returns `false`
- [ ] `jq 'has("hooks")' /path/to/project/.claude/settings.json` returns `false` (for each project)
- [ ] No `.claude/hooks/` directory in homelab-infra (or only user-owned hooks)
- [ ] Start a Claude session in homelab-infra — no hook errors
- [ ] Start a Claude session in ClaudeWorkflows — no hook errors
- [ ] Hooks still function (WFM enforcement works: try editing a file in DEFINE phase)
- [ ] Start a Claude session in a **brand new project** — no hook errors
- [ ] After verification, start another session — confirm hooks don't reappear in settings.json (final confirmation that re-materialization doesn't happen)

## Why This Fix Is Permanent

1. **The old setup.sh code that wrote hooks to settings.json was removed in commit `de02b93`.** No current code path writes hooks to settings files.
2. **The new cleanup in setup.sh actively removes stale entries** on every session start, so even if a stale copy somehow appears, it gets cleaned up immediately.
3. **The cleanup is targeted** — it only removes hooks matching the known stale pattern, not user-created hooks.
4. **The debunked re-materialization hypothesis is documented** — future sessions won't repeat the mistake of abandoning cleanup based on a false assumption.
5. **The defensive guards remain as a belt-and-suspenders safety net** — even if a stale copy somehow survives cleanup, it exits silently instead of erroring.
