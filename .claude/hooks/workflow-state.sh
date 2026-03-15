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
  "updated": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
}
