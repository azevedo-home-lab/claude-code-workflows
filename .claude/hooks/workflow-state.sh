#!/bin/bash
# Workflow state utility — read/write phase state
# Used by hooks (read only) and commands (read/write)

STATE_DIR="${CLAUDE_PROJECT_DIR:-.}/.claude/state"
STATE_FILE="$STATE_DIR/phase.json"

get_phase() {
    if [ ! -f "$STATE_FILE" ]; then
        echo "discuss"
        return
    fi
    local phase
    phase=$(grep -o '"phase"[[:space:]]*:[[:space:]]*"[^"]*"' "$STATE_FILE" | grep -o '"[^"]*"$' | tr -d '"')
    echo "${phase:-discuss}"
}

set_phase() {
    local phase="$1"
    mkdir -p "$STATE_DIR"
    cat > "$STATE_FILE" <<EOF
{
  "phase": "$phase",
  "message_shown": false,
  "updated": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
}

get_message_shown() {
    if [ ! -f "$STATE_FILE" ]; then
        echo "false"
        return
    fi
    local shown
    shown=$(grep -o '"message_shown"[[:space:]]*:[[:space:]]*[a-z]*' "$STATE_FILE" | grep -o '[a-z]*$')
    echo "${shown:-false}"
}

set_message_shown() {
    if [ -f "$STATE_FILE" ]; then
        local phase
        phase=$(get_phase)
        cat > "$STATE_FILE" <<EOF
{
  "phase": "$phase",
  "message_shown": true,
  "updated": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
    fi
}
