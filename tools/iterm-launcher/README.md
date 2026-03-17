# Claude Code iTerm2 Launcher

Launch Claude Code in a dedicated iTerm2 window with a project-aware badge for visual identification. Works from any IDE or terminal.

## What It Does

- Opens a new iTerm2 window using the "Claude Code" profile
- Sets the iTerm badge to **"Claude \<project-name\>"** (visible as watermark in the terminal)
- `cd`s into the project directory
- Launches `claude`

## Install

```bash
cd tools/iterm-launcher
./install.sh              # Profile + launcher
./install.sh --vscode     # + VSCode task/keybinding setup
./install.sh --zed        # + Zed task/keybinding setup
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

1. Run `./install.sh --vscode`
2. Press `Cmd+Shift+I` in any project

The installer auto-configures both `tasks.json` and `keybindings.json`.

### From Zed

1. Run `./install.sh --zed`
2. Press `Cmd+Shift+I` in any project

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
| `install.sh` | Installer with IDE configuration |
