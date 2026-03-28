# WFM Provider Status Line Indicator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show the active AI provider (Claude or Codex) in the WFM status line, read from the CCProxy state file written by `ccproxy-start.sh`.

**Architecture:** The status line script (`~/.claude/statusline.sh`) already reads `.claude/state/workflow.json` for WFM state. We add a new section that reads `~/.config/ccproxy/active-provider` (line 1: provider name, line 2: port) and `~/.config/ccproxy/ccproxy.pid`. The indicator only appears when the proxy is running (PID file exists and process is alive). Input is sanitized against backslash injection, matching the existing pattern in the statusline.

**Tech Stack:** bash, existing statusline source in this repo (installed to `~/.claude/statusline.sh` by `plugin/scripts/setup.sh`)

**Dependency:** `claude-code-tools` CCProxy plan must be implemented first — this plan reads state files written by `ccproxy-start.sh`.

**State file contract** (matches CCProxy tool plan):
- `~/.config/ccproxy/active-provider` — line 1: provider name (`claude`|`codex`), line 2: port number
- `~/.config/ccproxy/ccproxy.pid` — PID of running `ccproxy serve` process

---

## File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| Modify | statusline source in plugin (path determined in Task 1) | Add provider indicator block |

Note: `~/.claude/statusline.sh` is the *installed* copy. Edit the *source* in this repo. Run `source plugin/scripts/setup.sh` to reinstall after editing.

---

## Task 1: Locate the statusline source

- [ ] **Step 1: Find the source file**

```bash
grep -n "statusline" plugin/scripts/setup.sh | head -20
```

Look for a line that copies or writes a `statusline.sh` file. It will be something like `cp "$PLUGIN_ROOT/scripts/statusline.sh" ~/.claude/statusline.sh` or similar.

- [ ] **Step 2: Confirm the source path**

```bash
# Compare to the installed copy to confirm they match
diff <(grep -c '') ~/.claude/statusline.sh /dev/stdin < <(grep -c '' <source-path-from-step-1>)
```

Or simply: `wc -l ~/.claude/statusline.sh` and `wc -l <source-path>` — they should have the same line count.

- [ ] **Step 3: Note the exact source path** — all edits in Task 2 go to this file.

---

## Task 2: Add provider indicator to statusline source

**Files:**
- Modify: `<source-path-from-Task-1>`

- [ ] **Step 1: Read the full source file**

Confirm it ends with:
```bash
printf '%b' "$OUTPUT"
```
and that the Claude-Mem block is the last section before that line.

- [ ] **Step 2: Insert the provider indicator block**

Find the exact closing of the Claude-Mem block (the last `fi` before `printf '%b' "$OUTPUT"`). Replace the `printf` line with the new block + `printf` — this is the unambiguous insertion point:

**Find:**
```bash
printf '%b' "$OUTPUT"
```

**Replace with:**
```bash
# CCProxy provider indicator — only shown when proxy is running
CCPROXY_STATE="$HOME/.config/ccproxy/active-provider"
CCPROXY_PID_FILE="$HOME/.config/ccproxy/ccproxy.pid"
if [ -f "$CCPROXY_STATE" ] && [ -f "$CCPROXY_PID_FILE" ]; then
  CCPROXY_PID_VAL=$(tr -d '[:space:]' < "$CCPROXY_PID_FILE" 2>/dev/null || true)
  if [ -n "$CCPROXY_PID_VAL" ] && kill -0 "$CCPROXY_PID_VAL" 2>/dev/null; then
    ACTIVE_PROVIDER=$(head -1 "$CCPROXY_STATE" 2>/dev/null || true)
    CCPROXY_PORT=$(sed -n '2p' "$CCPROXY_STATE" 2>/dev/null || true)
    # Sanitize against printf '%b' backslash injection (matches existing pattern)
    ACTIVE_PROVIDER="${ACTIVE_PROVIDER//\\/\\\\}"
    CCPROXY_PORT="${CCPROXY_PORT//\\/\\\\}"
    case "$ACTIVE_PROVIDER" in
      codex)  PROVIDER_LABEL="Codex"  ; PROVIDER_COLOR="$YELLOW" ;;
      claude) PROVIDER_LABEL="Claude" ; PROVIDER_COLOR="$GREEN"  ;;
      *)      PROVIDER_LABEL="$ACTIVE_PROVIDER" ; PROVIDER_COLOR="$DIM" ;;
    esac
    OUTPUT+="  ${DIM}│${RESET}  ${PROVIDER_COLOR}⇄ ${PROVIDER_LABEL}${RESET}"
    [ -n "$CCPROXY_PORT" ] && OUTPUT+=" ${DIM}:${CCPROXY_PORT}${RESET}"
  fi
fi

printf '%b' "$OUTPUT"
```

- [ ] **Step 3: Verify bash syntax**

```bash
bash -n <source-path> && echo "syntax OK"
```
Expected: prints `syntax OK`, exit 0.

- [ ] **Step 4: Smoke test — no proxy running**

```bash
echo '{"version":"2.0.0","model":{"display_name":"claude-sonnet-4-6"},"context_window":{"used_percentage":15,"current_usage":{"input_tokens":5000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0},"context_window_size":200000},"cwd":"'"$(pwd)"'"}' \
  | bash <source-path>
```
Expected: status line renders without errors. No `⇄` indicator (proxy not running).

- [ ] **Step 5: Smoke test — mock proxy running (Codex)**

```bash
mkdir -p ~/.config/ccproxy
printf 'codex\n8000\n' > ~/.config/ccproxy/active-provider
echo "$$" > ~/.config/ccproxy/ccproxy.pid   # current shell PID — guaranteed alive

echo '{"version":"2.0.0","model":{"display_name":"claude-sonnet-4-6"},"context_window":{"used_percentage":15,"current_usage":{"input_tokens":5000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0},"context_window_size":200000},"cwd":"'"$(pwd)"'"}' \
  | bash <source-path>
```
Expected: `⇄ Codex :8000` appears in status line (yellow).

- [ ] **Step 6: Smoke test — mock proxy running (Claude)**

```bash
printf 'claude\n8000\n' > ~/.config/ccproxy/active-provider

echo '{"version":"2.0.0","model":{"display_name":"claude-sonnet-4-6"},"context_window":{"used_percentage":15,"current_usage":{"input_tokens":5000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0},"context_window_size":200000},"cwd":"'"$(pwd)"'"}' \
  | bash <source-path>
```
Expected: `⇄ Claude :8000` appears in status line (green).

- [ ] **Step 7: Smoke test — dead PID (proxy stopped)**

```bash
printf 'codex\n8000\n' > ~/.config/ccproxy/active-provider
echo "999999999" > ~/.config/ccproxy/ccproxy.pid   # non-existent PID

echo '{"version":"2.0.0","model":{"display_name":"claude-sonnet-4-6"},"context_window":{"used_percentage":15,"current_usage":{"input_tokens":5000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0},"context_window_size":200000},"cwd":"'"$(pwd)"'"}' \
  | bash <source-path>
```
Expected: NO `⇄` indicator (PID not alive = proxy considered stopped).

- [ ] **Step 8: Clean up mock state**

```bash
rm -f ~/.config/ccproxy/active-provider ~/.config/ccproxy/ccproxy.pid
```

- [ ] **Step 9: Commit**

```bash
git add <source-path>
git commit -m "feat(statusline): add CCProxy active provider indicator"
```

---

## Task 3: Reinstall statusline and verify

- [ ] **Step 1: Run setup to install the updated statusline**

```bash
source plugin/scripts/setup.sh
```
Expected: setup completes without errors.

- [ ] **Step 2: Confirm installed copy matches source**

```bash
diff ~/.claude/statusline.sh <source-path>
```
Expected: no diff.

- [ ] **Step 3: Re-run smoke test against installed copy (with mock state)**

```bash
mkdir -p ~/.config/ccproxy
printf 'codex\n8000\n' > ~/.config/ccproxy/active-provider
echo "$$" > ~/.config/ccproxy/ccproxy.pid

echo '{"version":"2.0.0","model":{"display_name":"claude-sonnet-4-6"},"context_window":{"used_percentage":15,"current_usage":{"input_tokens":5000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0},"context_window_size":200000},"cwd":"'"$(pwd)"'"}' \
  | bash ~/.claude/statusline.sh

rm -f ~/.config/ccproxy/active-provider ~/.config/ccproxy/ccproxy.pid
```
Expected: `⇄ Codex :8000` visible in output.

- [ ] **Step 4: Commit if any additional changes were needed**

```bash
git add plugin/scripts/setup.sh
git commit -m "feat(setup): reinstall updated statusline with provider indicator"
```
