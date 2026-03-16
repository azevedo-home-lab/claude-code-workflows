#!/bin/bash
# Workflow state utility — read/write phase state
# Used by hooks (read only) and commands (read/write)

STATE_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}/.claude/state"
STATE_FILE="$STATE_DIR/phase.json"

# Shared whitelist: paths allowed for writes during DISCUSS phase
# Used by workflow-gate.sh and bash-write-guard.sh
DISCUSS_WRITE_WHITELIST='(\.claude/state/|docs/superpowers/specs/|docs/superpowers/plans/|docs/plans/)'

get_phase() {
    if [ ! -f "$STATE_FILE" ]; then
        echo "off"
        return
    fi
    local phase
    phase=$(grep -o '"phase"[[:space:]]*:[[:space:]]*"[^"]*"' "$STATE_FILE" | grep -o '"[^"]*"$' | tr -d '"')
    echo "${phase:-off}"
}

set_phase() {
    local new_phase="$1"

    # Validate phase name
    case "$new_phase" in
        off|discuss|implement|review) ;;
        *) echo "ERROR: Invalid phase: $new_phase (valid: off, discuss, implement, review)" >&2; return 1 ;;
    esac

    local current_phase
    current_phase=$(get_phase)

    # Clean up review state when leaving review phase
    if [ "$current_phase" = "review" ] && [ "$new_phase" != "review" ]; then
        rm -f "$STATE_DIR/review-status.json"
    fi

    mkdir -p "$STATE_DIR"
    cat > "$STATE_FILE" <<EOF
{
  "phase": "$new_phase",
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
        local ts
        ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
        python3 -c "
import json, sys
filepath, ts = sys.argv[1], sys.argv[2]
with open(filepath, 'r') as f:
    d = json.load(f)
d['message_shown'] = True
d['updated'] = ts
with open(filepath, 'w') as f:
    json.dump(d, f, indent=2)
    f.write('\n')
" "$STATE_FILE" "$ts"
    fi
}

# Review status helpers
REVIEW_STATUS_FILE="$STATE_DIR/review-status.json"

reset_review_status() {
    mkdir -p "$STATE_DIR"
    cat > "$REVIEW_STATUS_FILE" <<EOF
{
  "verification_complete": false,
  "verification_skipped": false,
  "agents_dispatched": false,
  "findings_presented": false,
  "findings_acknowledged": false,
  "updated": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
}

get_review_field() {
    local field="$1"
    if [ ! -f "$REVIEW_STATUS_FILE" ]; then
        echo ""
        return
    fi
    local value
    value=$(python3 -c "
import json, sys
field = sys.argv[1]
filepath = sys.argv[2]
with open(filepath) as f:
    d = json.load(f)
v = d.get(field, '')
if isinstance(v, bool):
    print(str(v).lower())
else:
    print(v)
" "$field" "$REVIEW_STATUS_FILE" 2>/dev/null || echo "")
    echo "$value"
}

set_review_field() {
    local field="$1"
    local value="$2"
    if [ ! -f "$REVIEW_STATUS_FILE" ]; then
        return
    fi
    local ts
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    python3 -c "
import json, sys
field, value, ts, filepath = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
with open(filepath, 'r') as f:
    d = json.load(f)
if value in ('true', 'false'):
    d[field] = value == 'true'
else:
    d[field] = value
d['updated'] = ts
with open(filepath, 'w') as f:
    json.dump(d, f, indent=2)
    f.write('\n')
" "$field" "$value" "$ts" "$REVIEW_STATUS_FILE"
}
