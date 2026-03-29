#!/usr/bin/env bash
# Migration script for workflow documentation restructure.
# Updates all restricted plugin files to use new docs/plans/ and docs/specs/ structure.
# Run once from project root.
set -euo pipefail

PLUGIN_DIR="plugin"

echo "=== Workflow Documentation Structure Migration ==="
echo ""

# --- workflow-gate.sh ---
FILE="$PLUGIN_DIR/scripts/workflow-gate.sh"
echo "Updating $FILE..."
sed -i '' 's|docs/superpowers/specs/, docs/superpowers/plans/, docs/plans/|docs/plans/|' "$FILE"
grep -q 'docs/superpowers' "$FILE" && echo "  WARNING: stale superpowers reference remains" || echo "  OK"

# --- bash-write-guard.sh ---
FILE="$PLUGIN_DIR/scripts/bash-write-guard.sh"
echo "Updating $FILE..."
sed -i '' 's|docs/superpowers/specs/, docs/superpowers/plans/, docs/plans/|docs/plans/|' "$FILE"
grep -q 'docs/superpowers' "$FILE" && echo "  WARNING: stale superpowers reference remains" || echo "  OK"

# --- workflow-state.sh ---
FILE="$PLUGIN_DIR/scripts/workflow-state.sh"
echo "Updating $FILE..."

# Update restricted write whitelist
sed -i '' "s|docs/superpowers/specs/\|docs/superpowers/plans/\|docs/plans/|docs/plans/|" "$FILE"
grep "RESTRICTED_WRITE_WHITELIST" "$FILE"

# Rename section header
sed -i '' 's/# Decision record management/# Plan path management/' "$FILE"

# Rename functions
sed -i '' 's/set_decision_record()/set_plan_path()/' "$FILE"
sed -i '' 's/get_decision_record()/get_plan_path()/' "$FILE"

# Rename jq field references
sed -i '' 's/\.decision_record = /\.plan_path = /' "$FILE"
sed -i '' 's/\.decision_record \/\//\.plan_path \/\//' "$FILE"

# Rename preserved state reader
sed -i '' 's/preserved_decision=$(get_decision_record)/preserved_decision=$(get_plan_path)/' "$FILE"

# Update jq template field name in agent_set_phase
sed -i '' 's/decision_record: \$decision/plan_path: \$decision/' "$FILE"

# Update soft gate to search docs/plans only
sed -i '' 's|find "\$project_root/docs/superpowers/plans" "\$project_root/docs/plans"|find "\$project_root/docs/plans"|' "$FILE"

# Add spec_path functions after the plan_path get function
# Find the closing brace of get_plan_path and add after it
python3 -c "
import re
with open('$FILE') as f:
    content = f.read()

spec_funcs = '''

set_spec_path() { if [ ! -f \"\$STATE_FILE\" ]; then return; fi; _update_state '.spec_path = \$v' --arg v \"\$1\"; }

get_spec_path() {
    if [ ! -f \"\$STATE_FILE\" ]; then
        echo \"\"
        return
    fi
    local val
    val=\$(jq -r '.spec_path // \"\"' \"\$STATE_FILE\" 2>/dev/null) || val=\"\"
    echo \"\$val\"
}'''

# Insert after get_plan_path function (find the section boundary)
marker = '# Test results tracking'
content = content.replace(marker, spec_funcs + '\n\n' + marker)
with open('$FILE', 'w') as f:
    f.write(content)
"

echo "  OK"

# --- user-set-phase.sh ---
FILE="$PLUGIN_DIR/scripts/user-set-phase.sh"
echo "Updating $FILE..."
sed -i '' 's/decision_record: \$decision/plan_path: \$decision/' "$FILE"
echo "  OK"

# --- workflow-cmd.sh ---
FILE="$PLUGIN_DIR/scripts/workflow-cmd.sh"
echo "Updating $FILE..."
sed -i '' 's/get_decision_record|set_decision_record/get_plan_path|set_plan_path|get_spec_path|set_spec_path/' "$FILE"
echo "  OK"

# --- post-tool-navigator.sh ---
FILE="$PLUGIN_DIR/scripts/post-tool-navigator.sh"
echo "Updating $FILE..."

# Update DEFINE phase: decision_record_define -> plan_write_define, decisions.md -> docs/plans/
sed -i '' '/define)/,/;;/ {
  s|decisions\\.md|docs/plans/|
  s/decision_record_define/plan_write_define/
  s/Challenge vague problem statements\. Outcomes must be verifiable, not aspirational\./Challenge vague problem statements. Outcomes must be verifiable. Problem and Goals sections must be concrete./
}' "$FILE"

# Update DISCUSS phase: remove superpowers paths
sed -i '' 's|(docs/superpowers/plans/|docs/plans/)|docs/plans/|g' "$FILE"

# Update COMPLETE phase: decision_record_edit -> project_docs_edit
sed -i '' '/complete)/,/;;/ {
  s|decisions\\.md|docs/|
  s/decision_record_edit/project_docs_edit/
}' "$FILE"

# Update REVIEW Layer 3: decisions.md -> docs/specs/
sed -i '' '/review)/,/fi/ {
  /Layer 3/,/fi/ {
    s|decisions\\.md|docs/specs/|
  }
}' "$FILE"

# Update DISCUSS Layer 3: remove superpowers paths
sed -i '' 's|(docs/superpowers/plans/|docs/plans/)|docs/plans/|g' "$FILE"

echo "  OK"

# --- setup.sh ---
FILE="$PLUGIN_DIR/scripts/setup.sh"
echo "Updating $FILE..."
sed -i '' 's/decision_record: ""/plan_path: "",\
    spec_path: ""/' "$FILE"
echo "  OK"

# --- define.md ---
FILE="$PLUGIN_DIR/commands/define.md"
echo "Updating $FILE..."
sed -i '' 's|docs/superpowers/specs/|docs/plans/|g' "$FILE"
sed -i '' 's|docs/superpowers/plans/|docs/specs/|g' "$FILE"
sed -i '' 's|docs/plans/YYYY-MM-DD-<topic>-decisions.md|docs/plans/YYYY-MM-DD-<topic>.md|g' "$FILE"
sed -i '' 's/set_decision_record/set_plan_path/g' "$FILE"
sed -i '' 's/get_decision_record/get_plan_path/g' "$FILE"
sed -i '' 's/decision record/plan/g' "$FILE"
sed -i '' 's/Decision record/Plan/g' "$FILE"
echo "  OK"

# --- discuss.md ---
FILE="$PLUGIN_DIR/commands/discuss.md"
echo "Updating $FILE..."
sed -i '' 's|docs/superpowers/specs/|docs/plans/|g' "$FILE"
sed -i '' 's|docs/superpowers/plans/|docs/specs/|g' "$FILE"
sed -i '' 's/set_decision_record/set_plan_path/g' "$FILE"
sed -i '' 's/get_decision_record/get_plan_path/g' "$FILE"
sed -i '' 's/decision record/plan/g' "$FILE"
sed -i '' 's/Decision record/Plan/g' "$FILE"
echo "  OK"

# --- implement.md ---
FILE="$PLUGIN_DIR/commands/implement.md"
echo "Updating $FILE..."
sed -i '' 's/Decision record: \[DECISION_RECORD_PATH\]/Plan: [PLAN_PATH]/' "$FILE"
sed -i '' 's/get_decision_record/get_plan_path/g' "$FILE"
sed -i '' 's/decision record/plan/g' "$FILE"
echo "  OK"

# --- review.md ---
FILE="$PLUGIN_DIR/commands/review.md"
echo "Updating $FILE..."
sed -i '' 's|docs/superpowers/plans/|docs/plans/|g' "$FILE"
sed -i '' 's|docs/superpowers/specs/|docs/specs/|g' "$FILE"
sed -i '' 's/get_decision_record/get_plan_path/g' "$FILE"
sed -i '' 's/decision record/plan/g' "$FILE"
echo "  OK"

# --- complete.md ---
FILE="$PLUGIN_DIR/commands/complete.md"
echo "Updating $FILE..."
sed -i '' 's|docs/superpowers/plans/|docs/plans/|g' "$FILE"
sed -i '' 's|docs/superpowers/specs/|docs/specs/|g' "$FILE"
sed -i '' 's/get_decision_record/get_plan_path/g' "$FILE"
sed -i '' 's/Decision record/Plan/g' "$FILE"
sed -i '' 's/decision record/plan/g' "$FILE"
echo "  OK"

# --- Update brainstorming skill cache ---
SKILL_CACHE="$HOME/.claude/plugins/cache/superpowers-marketplace/superpowers"
if [ -d "$SKILL_CACHE" ]; then
    echo "Updating brainstorming skill cache..."
    find "$SKILL_CACHE" -name "SKILL.md" -path "*/brainstorming/*" -exec sed -i '' 's|docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md|docs/plans/YYYY-MM-DD-<topic>.md|g' {} \;
    find "$SKILL_CACHE" -name "spec-document-reviewer-prompt.md" -exec sed -i '' 's|docs/superpowers/specs/|docs/plans/|g' {} \;
    echo "  OK"

    echo "Updating writing-plans skill cache..."
    find "$SKILL_CACHE" -name "SKILL.md" -path "*/writing-plans/*" -exec sed -i '' 's|docs/superpowers/plans/YYYY-MM-DD-<feature-name>.md|docs/specs/YYYY-MM-DD-<feature-name>.md|g' {} \;
    find "$SKILL_CACHE" -name "SKILL.md" -path "*/writing-plans/*" -exec sed -i '' 's|docs/superpowers/plans/|docs/specs/|g' {} \;
    echo "  OK"
else
    echo "WARNING: Skill cache not found at $SKILL_CACHE — update brainstorming/writing-plans skills manually."
fi

echo ""
echo "=== Migration complete ==="
echo ""
echo "Verify with:"
echo "  grep -r 'docs/superpowers' plugin/ || echo 'PASS: no stale superpowers refs'"
echo "  grep -r 'decision_record' plugin/ || echo 'PASS: no stale decision_record refs'"
echo ""
echo "Then commit:"
echo "  git add -A plugin/"
echo "  git commit -m 'refactor: update all plugin references for docs restructure'"
