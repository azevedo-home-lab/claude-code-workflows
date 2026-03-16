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
2. Add to `keybindings.json`:
   ```json
   {
       "key": "cmd+shift+i",
       "command": "workbench.action.tasks.runTask",
       "args": "Claude Code in iTerm2"
   }
   ```
3. Press `Cmd+Shift+I` in any project

The installer creates this `tasks.json`:
```json
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "Claude Code in iTerm2",
      "type": "shell",
      "command": "~/bin/launch-claude-iterm '${workspaceFolder}'",
      "presentation": {"reveal": "never"},
      "problemMatcher": []
    }
  ]
}
```

### From Zed

1. Run `./install.sh --zed`
2. Add to `keymap.json`:
   ```json
   {
     "context": "Workspace",
     "bindings": {
       "cmd-shift-i": ["task::Spawn", { "task_name": "Claude Code in iTerm" }]
     }
   }
   ```
3. Press `Cmd+Shift+I` in any project

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
