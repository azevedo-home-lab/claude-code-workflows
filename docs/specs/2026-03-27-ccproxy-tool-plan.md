# CCProxy Tool Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `ccproxy/` tool to `claude-code-tools` that installs CCProxy, authenticates with Claude and OpenAI Codex (ChatGPT Pro subscription), manages the proxy lifecycle, and provides a `/provider` slash command to switch between providers.

**Architecture:** Follows the existing `yubikey-setup/` and `iterm-launcher/` pattern — a self-contained directory with `install.sh`, runtime scripts, and a slash command file. CCProxy is installed globally via `pipx` and runs as a background process. Provider switching writes the active provider name and port to `~/.config/ccproxy/active-provider` (line 1: provider name, line 2: port) and the proxy PID to `~/.config/ccproxy/ccproxy.pid` — both read by the WFM status line.

**Tech Stack:** bash, pipx, CCProxy (`ccproxy-api[all]==0.2.6`), Claude Code slash commands (`.md` files in `~/.claude/commands/`)

**Repo:** `github.com/azevedo-home-lab/claude-code-tools`

**State file contract** (shared with WFM status line plan):
- `~/.config/ccproxy/active-provider` — line 1: provider name (`claude`|`codex`), line 2: port number
- `~/.config/ccproxy/ccproxy.pid` — PID of running `ccproxy serve` process

---

## File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `ccproxy/install.sh` | Install pipx + ccproxy, run auth flows, install slash command |
| Create | `ccproxy/ccproxy-start.sh` | Start proxy as background process, write active-provider state |
| Create | `ccproxy/ccproxy-stop.sh` | Stop proxy, clear active-provider state |
| Create | `ccproxy/provider.md` | Slash command: `/provider` — switch active provider |
| Create | `ccproxy/README.md` | Setup and usage docs |
| Modify | `tests/run-tests.sh` | Add smoke tests for ccproxy scripts |

---

## Task 1: `ccproxy-start.sh` and `ccproxy-stop.sh`

**Files:**
- Create: `ccproxy/ccproxy-start.sh`
- Create: `ccproxy/ccproxy-stop.sh`

The start script accepts a provider argument (`claude` or `codex`), starts `ccproxy serve` in the background, exports `ANTHROPIC_BASE_URL` when sourced, and writes the state files read by the WFM status line.

**Important:** This script must be *sourced* (not run directly) to export env vars into the calling shell. It uses `return` instead of `exit` when sourced to avoid killing the parent shell on errors.

- [ ] **Step 1: Create `ccproxy/ccproxy-start.sh`**

```bash
#!/bin/bash
# Copyright (C) 2026 azevedo-home-lab
# SPDX-License-Identifier: GPL-3.0-only
#
# Start CCProxy and configure ANTHROPIC_BASE_URL for the current shell.
#
# Usage (must be sourced to export env vars):
#   source ccproxy-start.sh [claude|codex]
#   . ccproxy-start.sh codex
#
# When run directly (not sourced), starts the proxy only — env vars not exported.
#
# NOTE: Do NOT add 'set -e' here. This script is designed to be sourced,
# and 'set -e' in a sourced script exits the parent shell on any error.
# Errors are handled explicitly below.

PROVIDER="${1:-claude}"
PORT="${CCPROXY_PORT:-8000}"
STATE_FILE="$HOME/.config/ccproxy/active-provider"
PID_FILE="$HOME/.config/ccproxy/ccproxy.pid"
LOG_FILE="$HOME/.config/ccproxy/ccproxy.log"

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'
ok()   { echo -e "${GREEN}✓${NC} $1"; }
warn() { echo -e "${YELLOW}!${NC} $1"; }
err()  { echo -e "${RED}✗${NC} $1" >&2; }

# Use 'return' when sourced, 'exit' when run directly
_exit() {
    local code="$1"
    # BASH_SOURCE[0] == $0 means running directly (not sourced)
    if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
        exit "$code"
    else
        return "$code"
    fi
}

# Validate provider
case "$PROVIDER" in
    claude|codex) ;;
    *) err "Unknown provider '$PROVIDER'. Use: claude or codex"; _exit 1; return 2>/dev/null ;;
esac

# Check ccproxy is installed
if ! command -v ccproxy &>/dev/null; then
    err "ccproxy not found. Run ccproxy/install.sh first."
    _exit 1; return 2>/dev/null
fi

mkdir -p "$HOME/.config/ccproxy"

# Stop existing proxy if running
if [ -f "$PID_FILE" ]; then
    OLD_PID=$(tr -d '[:space:]' < "$PID_FILE" 2>/dev/null || true)
    if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
        kill "$OLD_PID" 2>/dev/null || true
        sleep 0.5
    fi
    rm -f "$PID_FILE"
fi

# Start proxy in background — log to ~/.config/ccproxy/ not /tmp (avoid world-writable path)
ccproxy serve --port "$PORT" >"$LOG_FILE" 2>&1 &
PROXY_PID=$!
echo "$PROXY_PID" > "$PID_FILE"

# Wait for proxy to be ready (up to 5s)
READY=false
for i in $(seq 1 10); do
    if curl -sf "http://localhost:${PORT}/health" >/dev/null 2>&1; then
        READY=true
        break
    fi
    sleep 0.5
done

if [ "$READY" = false ]; then
    err "CCProxy failed to start. Check $LOG_FILE"
    rm -f "$PID_FILE"
    _exit 1; return 2>/dev/null
fi

# Write active provider state (read by WFM status line)
# Format: line 1 = provider name, line 2 = port number
printf '%s\n%s\n' "$PROVIDER" "$PORT" > "$STATE_FILE"

ok "CCProxy started (PID $PROXY_PID, port $PORT)"
ok "Active provider: $PROVIDER"

# Export env vars — only effective when sourced
export ANTHROPIC_BASE_URL="http://localhost:${PORT}"
export CCPROXY_ACTIVE_PROVIDER="$PROVIDER"

echo ""
echo "Shell env set:"
echo "  ANTHROPIC_BASE_URL=$ANTHROPIC_BASE_URL"
echo "  CCPROXY_ACTIVE_PROVIDER=$CCPROXY_ACTIVE_PROVIDER"
echo ""
warn "These vars are only active in this shell. New terminals need: source ccproxy-start.sh $PROVIDER"
```

- [ ] **Step 2: `chmod +x ccproxy/ccproxy-start.sh`**

- [ ] **Step 3: Create `ccproxy/ccproxy-stop.sh`**

```bash
#!/bin/bash
# Copyright (C) 2026 azevedo-home-lab
# SPDX-License-Identifier: GPL-3.0-only
#
# Stop CCProxy and clear active provider state.

set -euo pipefail

PID_FILE="$HOME/.config/ccproxy/ccproxy.pid"
STATE_FILE="$HOME/.config/ccproxy/active-provider"
CONFIG_DIR="$HOME/.config/ccproxy"

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'
ok()   { echo -e "${GREEN}✓${NC} $1"; }
warn() { echo -e "${YELLOW}!${NC} $1"; }

if [ ! -f "$PID_FILE" ]; then
    warn "CCProxy does not appear to be running (no PID file)"
    exit 0
fi

PID=$(tr -d '[:space:]' < "$PID_FILE" 2>/dev/null || true)
if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
    kill "$PID"
    ok "CCProxy stopped (PID $PID)"
else
    warn "Process ${PID:-unknown} not found — already stopped"
fi

rm -f "$PID_FILE" "$STATE_FILE"
ok "Active provider state cleared"
```

- [ ] **Step 4: `chmod +x ccproxy/ccproxy-stop.sh`**

- [ ] **Step 5: Verify bash syntax on both scripts**

```bash
bash -n ccproxy/ccproxy-start.sh && echo "start.sh OK"
bash -n ccproxy/ccproxy-stop.sh  && echo "stop.sh OK"
```
Expected: both print OK, exit 0.

- [ ] **Step 6: Commit**

```bash
git add ccproxy/ccproxy-start.sh ccproxy/ccproxy-stop.sh
git commit -m "feat(ccproxy): add start/stop lifecycle scripts"
```

---

## Task 2: `/provider` slash command

**Files:**
- Create: `ccproxy/provider.md`

The slash command is installed into `~/.claude/commands/provider.md` by `install.sh`.

- [ ] **Step 1: Create `ccproxy/provider.md`**

```markdown
Switch the active AI provider for this Claude Code session.

Usage:
  /provider          — show current provider and status
  /provider claude   — switch to Claude (Anthropic, your 5x subscription)
  /provider codex    — switch to OpenAI Codex (ChatGPT Pro subscription)

## What this does

Sources `~/.local/bin/ccproxy-start.sh <provider>` to:
1. (Re)start CCProxy if needed
2. Set ANTHROPIC_BASE_URL to route through the proxy
3. Update the active provider state file read by the WFM status line

## Requirements

CCProxy must be installed. Run once:
  ~/ccproxy-install.sh
  # or from the claude-code-tools repo:
  ./ccproxy/install.sh

## Check current status

```bash
# Active provider:
cat ~/.config/ccproxy/active-provider | head -1

# Proxy health:
curl -s http://localhost:8000/health
```

## Switch providers

```bash
# Switch to Codex (ChatGPT Pro):
source ~/.local/bin/ccproxy-start.sh codex

# Switch back to Claude:
source ~/.local/bin/ccproxy-start.sh claude

# Stop proxy entirely:
~/.local/bin/ccproxy-stop.sh
```

After switching, run `/model` in Claude Code to select an appropriate model:
- Claude: `sonnet`, `opus`, `haiku`
- Codex: select from available Codex models
```

- [ ] **Step 2: Commit**

```bash
git add ccproxy/provider.md
git commit -m "feat(ccproxy): add /provider slash command"
```

---

## Task 3: `install.sh`

**Files:**
- Create: `ccproxy/install.sh`

Follows the same `yubikey-setup/install.sh` pattern: works from local clone or via `curl | bash`, supports `--uninstall`, `fetch_file()` helper, color helpers.

- [ ] **Step 1: Create `ccproxy/install.sh`**

```bash
#!/bin/bash
# Copyright (C) 2026 azevedo-home-lab
# SPDX-License-Identifier: GPL-3.0-only
#
# Install CCProxy — multi-provider AI proxy for Claude Code
#
# curl -fsSL https://raw.githubusercontent.com/azevedo-home-lab/claude-code-tools/main/ccproxy/install.sh | bash
# ./install.sh
# ./install.sh --uninstall

set -euo pipefail

REPO_BASE="https://raw.githubusercontent.com/azevedo-home-lab/claude-code-tools/main/ccproxy"
BIN_DIR="$HOME/.local/bin"
COMMANDS_DIR="$HOME/.claude/commands"
CONFIG_DIR="$HOME/.config/ccproxy"
CCPROXY_VERSION="0.2.6"

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'
ok()   { echo -e "${GREEN}✓${NC} $1"; }
warn() { echo -e "${YELLOW}!${NC} $1"; }
err()  { echo -e "${RED}✗${NC} $1" >&2; }

SCRIPT_DIR=""
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

fetch_file() {
    local filename="$1" dest="$2"
    if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/$filename" ]; then
        cp "$SCRIPT_DIR/$filename" "$dest"
    else
        curl -fsSL "$REPO_BASE/$filename" -o "$dest"
    fi
}

if [ "${1:-}" = "--uninstall" ]; then
    echo "Uninstalling CCProxy..."

    # Stop running proxy first
    if [ -f "$CONFIG_DIR/ccproxy.pid" ]; then
        PID=$(tr -d '[:space:]' < "$CONFIG_DIR/ccproxy.pid" 2>/dev/null || true)
        if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
            kill "$PID" && ok "Stopped running CCProxy (PID $PID)" || warn "Could not stop PID $PID"
        fi
    fi

    pipx uninstall ccproxy-api 2>/dev/null && ok "ccproxy-api removed" || warn "ccproxy-api was not installed via pipx"
    rm -f "$BIN_DIR/ccproxy-start.sh" "$BIN_DIR/ccproxy-stop.sh"
    rm -f "$COMMANDS_DIR/provider.md"
    rm -rf "$CONFIG_DIR"
    ok "Uninstall complete"
    exit 0
fi

echo "Installing CCProxy (v${CCPROXY_VERSION})..."
echo ""

# 1. Check Python 3.11+
if ! python3 -c 'import sys; assert sys.version_info >= (3,11)' 2>/dev/null; then
    err "Python 3.11+ required. Install via: brew install python@3.11"
    exit 1
fi
ok "Python 3.11+ found"

# 2. Install pipx if needed
if ! command -v pipx &>/dev/null; then
    warn "pipx not found — installing..."
    python3 -m pip install --user pipx
    python3 -m pipx ensurepath
    ok "pipx installed"
else
    ok "pipx found"
fi

# 3. Install ccproxy-api (pinned version)
echo ""
echo "Installing ccproxy-api[all]==${CCPROXY_VERSION}..."
pipx install "ccproxy-api[all]==${CCPROXY_VERSION}" --force
ok "ccproxy-api ${CCPROXY_VERSION} installed"

# 4. Install runtime scripts to ~/.local/bin
mkdir -p "$BIN_DIR"
fetch_file "ccproxy-start.sh" "$BIN_DIR/ccproxy-start.sh"
fetch_file "ccproxy-stop.sh"  "$BIN_DIR/ccproxy-stop.sh"
chmod +x "$BIN_DIR/ccproxy-start.sh" "$BIN_DIR/ccproxy-stop.sh"
ok "Runtime scripts installed to $BIN_DIR"

# 5. Install /provider slash command
mkdir -p "$COMMANDS_DIR"
fetch_file "provider.md" "$COMMANDS_DIR/provider.md"
ok "/provider slash command installed to $COMMANDS_DIR"

# 6. Auth flows — skip if already authenticated
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Authentication — browser will open if needed"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Step 1/2: Claude (Anthropic)"
if ccproxy auth validate >/dev/null 2>&1; then
    ok "Claude auth already valid — skipping login"
else
    echo "  Sign in with your Claude Pro/Max/5x account"
    ccproxy auth login
    ok "Claude auth complete"
fi

echo ""
echo "Step 2/2: OpenAI Codex (ChatGPT Pro)"
if ccproxy auth validate --provider openai >/dev/null 2>&1; then
    ok "OpenAI Codex auth already valid — skipping login"
else
    echo "  Sign in with your ChatGPT Pro account"
    ccproxy auth login-openai
    ok "OpenAI Codex auth complete"
fi

# 7. PATH check
if ! echo "$PATH" | tr ':' '\n' | grep -qxF "$BIN_DIR"; then
    warn "$BIN_DIR is not in PATH — add to your shell profile:"
    echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
fi

echo ""
ok "CCProxy installation complete!"
echo ""
echo "Quick start:"
echo "  source ~/.local/bin/ccproxy-start.sh claude    # use your Claude subscription"
echo "  source ~/.local/bin/ccproxy-start.sh codex     # use your ChatGPT Pro subscription"
echo "  ~/.local/bin/ccproxy-stop.sh                   # stop the proxy"
echo ""
echo "Inside Claude Code, use /provider to switch providers."
```

- [ ] **Step 2: `chmod +x ccproxy/install.sh`**

- [ ] **Step 3: Verify bash syntax**

```bash
bash -n ccproxy/install.sh && echo "install.sh OK"
```
Expected: prints OK, exit 0.

- [ ] **Step 4: Commit**

```bash
git add ccproxy/install.sh
git commit -m "feat(ccproxy): add install script with auth flows"
```

---

## Task 4: `README.md`

**Files:**
- Create: `ccproxy/README.md`

- [ ] **Step 1: Create `ccproxy/README.md`**

```markdown
# CCProxy

Routes Claude Code requests through multiple AI providers using your existing subscriptions — no per-token API billing.

## Supported providers

| Provider | Subscription | Models |
|----------|-------------|--------|
| Claude | Anthropic Pro/Max/5x | claude-sonnet, claude-opus, claude-haiku |
| Codex | ChatGPT Pro (via OAuth) | GPT-5.4, GPT-5.3-Codex, GPT-5.3-Codex-Spark |

## Install

```bash
# From clone:
./ccproxy/install.sh

# Or via curl:
curl -fsSL https://raw.githubusercontent.com/azevedo-home-lab/claude-code-tools/main/ccproxy/install.sh | bash
```

Requires Python 3.11+. Install will prompt for browser auth for each provider (skipped if already authenticated).

## Usage

```bash
# Start with Claude (default)
source ~/.local/bin/ccproxy-start.sh claude

# Start with Codex (ChatGPT Pro)
source ~/.local/bin/ccproxy-start.sh codex

# Stop
~/.local/bin/ccproxy-stop.sh
```

Inside Claude Code, use `/provider` to check status and switch.

## How it works

CCProxy runs as a local HTTP server on port 8000. Claude Code points `ANTHROPIC_BASE_URL` at `http://localhost:8000`. CCProxy translates requests to each provider's native API format and routes them using your OAuth tokens — no API keys required.

State files written to `~/.config/ccproxy/`:
- `active-provider` — line 1: provider name, line 2: port (read by WFM status line)
- `ccproxy.pid` — PID of running proxy process
- `ccproxy.log` — proxy server log

## Uninstall

```bash
./ccproxy/install.sh --uninstall
```
```

- [ ] **Step 2: Commit**

```bash
git add ccproxy/README.md
git commit -m "docs(ccproxy): add README"
```

---

## Task 5: Tests

**Files:**
- Modify: `tests/run-tests.sh`

- [ ] **Step 1: Read `tests/run-tests.sh`** to understand the existing test helper pattern (`assert_pass`, `assert_fail`, etc.)

- [ ] **Step 2: Add smoke tests for ccproxy scripts**

Add to `tests/run-tests.sh`:

```bash
# ── CCProxy tests ─────────────────────────────────────────────────────────────

test_ccproxy_start_syntax() {
    bash -n ccproxy/ccproxy-start.sh
    assert_pass "ccproxy-start.sh syntax valid"
}

test_ccproxy_stop_syntax() {
    bash -n ccproxy/ccproxy-stop.sh
    assert_pass "ccproxy-stop.sh syntax valid"
}

test_install_syntax() {
    bash -n ccproxy/install.sh
    assert_pass "ccproxy/install.sh syntax valid"
}

test_ccproxy_start_rejects_unknown_provider() {
    output=$(bash ccproxy/ccproxy-start.sh badprovider 2>&1) || true
    echo "$output" | grep -q "Unknown provider" \
        && assert_pass "rejects unknown provider" \
        || assert_fail "should reject unknown provider, got: $output"
}

test_ccproxy_start_requires_ccproxy_binary() {
    output=$(PATH=/dev/null bash ccproxy/ccproxy-start.sh claude 2>&1) || true
    echo "$output" | grep -q "ccproxy not found" \
        && assert_pass "detects missing ccproxy binary" \
        || assert_fail "should detect missing binary, got: $output"
}

test_ccproxy_stop_handles_missing_pid_file() {
    # Ensure no stale PID file
    rm -f "$HOME/.config/ccproxy/ccproxy.pid"
    output=$(bash ccproxy/ccproxy-stop.sh 2>&1)
    echo "$output" | grep -qi "not.*running\|no pid" \
        && assert_pass "stop gracefully handles missing PID file" \
        || assert_fail "should warn about missing PID file, got: $output"
}
```

- [ ] **Step 3: Run tests**

```bash
bash tests/run-tests.sh
```
Expected: all CCProxy tests PASS.

- [ ] **Step 4: Commit**

```bash
git add tests/run-tests.sh
git commit -m "test(ccproxy): add syntax and error-path smoke tests"
```

---

## Task 6: Update root `README.md`

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Read root `README.md`** to find the tools table

- [ ] **Step 2: Add CCProxy entry**

Add a row alongside the existing tools:

```markdown
| [ccproxy](ccproxy/) | Routes Claude Code through multiple AI providers (Claude, OpenAI Codex) using existing subscriptions — no API billing |
```

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: add ccproxy to tools listing"
```
