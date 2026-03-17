# Claude Code iTerm2 Launcher

Launch Claude Code in a dedicated iTerm2 window with a project-aware badge for visual identification. Works from any IDE or terminal.

## What It Does

- Opens a new iTerm2 window using the "Claude Code" profile
- Sets the iTerm badge to **"Claude \<project-name\>"** (visible as watermark in the terminal)
- `cd`s into the project directory
- Launches `claude`

## Quick Install

One-liner from GitHub — no clone needed:

```bash
# Profile + launcher only
curl -fsSL https://raw.githubusercontent.com/azevedo-home-lab/claude-code-workflows/main/tools/iterm-launcher/install.sh | bash

# With VSCode integration
curl -fsSL https://raw.githubusercontent.com/azevedo-home-lab/claude-code-workflows/main/tools/iterm-launcher/install.sh | bash -s -- --vscode

# With Zed integration
curl -fsSL https://raw.githubusercontent.com/azevedo-home-lab/claude-code-workflows/main/tools/iterm-launcher/install.sh | bash -s -- --zed
```

Or from a local clone:

```bash
cd tools/iterm-launcher
./install.sh              # Profile + launcher
./install.sh --vscode     # + VSCode task and keybinding
./install.sh --zed        # + Zed task and keybinding
./install.sh --uninstall  # Remove everything
```

This installs:
- iTerm2 dynamic profile at `~/Library/Application Support/iTerm2/DynamicProfiles/claude-code.json`
- Launcher script at `~/bin/launch-claude-iterm`

## Usage

### From terminal

```bash
launch-claude-iterm /path/to/project
launch-claude-iterm                     # uses current directory
```

### From VSCode / Cursor

Run `./install.sh --vscode` (or the curl one-liner with `--vscode`), then press `Cmd+Shift+I` in any project.

The installer auto-configures both `tasks.json` and `keybindings.json`.

### From Zed

Run `./install.sh --zed` (or the curl one-liner with `--zed`), then press `Cmd+Shift+I` in any project.

The installer auto-configures both `tasks.json` and `keymap.json`.

### From any other IDE

Call the launcher from your IDE's task/command system:
```
~/bin/launch-claude-iterm "$PROJECT_ROOT"
```

## Configuration

### Custom Claude binary path

```bash
CLAUDE_BIN=/path/to/claude launch-claude-iterm /path/to/project
```

Default: `~/.local/bin/claude`

### iTerm profile customization

Edit the installed profile at:
```
~/Library/Application Support/iTerm2/DynamicProfiles/claude-code.json
```

Changes take effect immediately — iTerm2 watches the DynamicProfiles directory.

## Prerequisites

- macOS (uses AppleScript + iTerm2 APIs)
- [iTerm2](https://iterm2.com/)
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code/overview)

## Files

| File | Purpose |
|------|---------|
| `launch-claude-iterm.sh` | Launcher script (installed to `~/bin/`) |
| `claude-code-profile.json` | iTerm2 dynamic profile |
| `install.sh` | Installer with IDE configuration (works from curl or local clone) |
