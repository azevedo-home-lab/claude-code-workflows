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

# Add spec_path functions (idempotent — removes ALL duplicates, inserts exactly 1)
python3 -c "
with open('$FILE') as f:
    lines = f.readlines()

# Remove all lines belonging to spec_path function definitions
# Keep references like preserved_spec=\$(get_spec_path) and jq template lines
out = []
skip = False
for i, line in enumerate(lines):
    stripped = line.strip()
    # Start skipping on set_spec_path definition
    if stripped.startswith('set_spec_path()'):
        skip = True
        # Also remove preceding blank lines and separator comments
        while out and out[-1].strip() in ('', '# ---------------------------------------------------------------------------', '# Spec path management'):
            out.pop()
        continue
    # Skip get_spec_path definition and its body
    if stripped.startswith('get_spec_path()') and skip:
        continue
    if skip and stripped in ('if [ ! -f \"\$STATE_FILE\" ]; then', 'echo \"\"', 'return', 'fi', 'local val', '}'):
        continue
    if skip and '.spec_path' in stripped and 'jq' in stripped:
        continue
    if skip and stripped == 'echo \"\$val\"':
        continue
    # End skip on non-empty, non-blank line that's not part of the function
    if skip and stripped and not stripped.startswith('#'):
        skip = False
    if skip and not stripped:
        continue
    out.append(line)

# Now insert exactly one copy before '# Test results tracking'
insert = '''
# ---------------------------------------------------------------------------
# Spec path management
# ---------------------------------------------------------------------------

set_spec_path() { if [ ! -f \"\$STATE_FILE\" ]; then return; fi; _update_state '.spec_path = \$v' --arg v \"\$1\"; }

get_spec_path() {
    if [ ! -f \"\$STATE_FILE\" ]; then
        echo \"\"
        return
    fi
    local val
    val=\$(jq -r '.spec_path // \"\"' \"\$STATE_FILE\" 2>/dev/null) || val=\"\"
    echo \"\$val\"
}

'''
final = []
for line in out:
    if '# Test results tracking' in line:
        final.append(insert)
    final.append(line)

with open('$FILE', 'w') as f:
    f.writelines(final)
print('  spec_path: cleaned all duplicates, inserted 1 copy')
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
sed -i '' "s#(docs/superpowers/plans/|docs/plans/)#docs/plans/#g" "$FILE"

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
sed -i '' "s#(docs/superpowers/plans/|docs/plans/)#docs/plans/#g" "$FILE"

# Fix REVIEW Layer 2: decisions.md -> docs/specs/ (line 286 area)
sed -i '' "s|grep -qE 'decisions\\\\.md'|grep -qE 'docs/specs/'|g" "$FILE"

# Fix REVIEW Layer 2 comment (line 282)
sed -i '' 's/writing review findings to user (Write\/Edit\/MultiEdit to decision record in review phase)/writing review findings (Write\/Edit\/MultiEdit to spec in review phase)/' "$FILE"

# Fix REVIEW Layer 3 comment (line 344)
sed -i '' 's/All findings downgraded (REVIEW phase, writing to decision record)/All findings downgraded (REVIEW phase, writing to spec)/' "$FILE"

# Fix Layer 1 coaching messages: decision record -> plan/spec
sed -i '' 's/Decision record has a complete Problem section with measurable outcomes/Plan has a complete Problem section with measurable outcomes/' "$FILE"
sed -i '' 's/Decision record has Approaches Considered + Decision sections/Plan has Approaches Considered + Decision sections/' "$FILE"
sed -i '' 's/findings verified and persisted to decision record/findings verified and persisted to spec/' "$FILE"
sed -i '' 's/Validation results in decision record/Validation results in plan/' "$FILE"

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

# --- workflow-state.sh: add spec_path preservation across phase transitions ---
FILE="$PLUGIN_DIR/scripts/workflow-state.sh"
echo "Updating $FILE (spec_path preservation)..."
python3 -c "
with open('$FILE') as f:
    content = f.read()

# Add preserved_spec to _read_preserved_state
if 'preserved_spec=' not in content:
    content = content.replace(
        'preserved_tests_passed=\$(get_tests_passed_at)',
        'preserved_spec=\$(get_spec_path)\n    preserved_tests_passed=\$(get_tests_passed_at)'
    )

# Add local preserved_spec to agent_set_phase
if 'preserved_spec=\"\"' not in content:
    content = content.replace(
        'local preserved_tests_passed=\"\"',
        'local preserved_spec=\"\"\n    local preserved_tests_passed=\"\"'
    )

# Add --arg spec to jq command in agent_set_phase
if '--arg spec ' not in content:
    content = content.replace(
        '--arg tests_passed \"\$preserved_tests_passed\"',
        '--arg spec \"\$preserved_spec\" \\\\\n          --arg tests_passed \"\$preserved_tests_passed\"'
    )

# Add spec_path to jq template output
if 'spec_path: \$spec' not in content:
    content = content.replace(
        'plan_path: \$decision,',
        'plan_path: \$decision,\n              spec_path: \$spec,'
    )

with open('$FILE', 'w') as f:
    f.write(content)
"
echo "  OK"

# --- user-set-phase.sh: add spec_path preservation ---
FILE="$PLUGIN_DIR/scripts/user-set-phase.sh"
echo "Updating $FILE (spec_path preservation)..."
python3 -c "
with open('$FILE') as f:
    content = f.read()

# Add --arg spec and spec_path field (same pattern as agent_set_phase)
if '--arg spec ' not in content:
    content = content.replace(
        '--arg tests_passed \"\$preserved_tests_passed\"',
        '--arg spec \"\$preserved_spec\" \\\\\n      --arg tests_passed \"\$preserved_tests_passed\"'
    )

if 'spec_path: \$spec' not in content:
    content = content.replace(
        'plan_path: \$decision,',
        'plan_path: \$decision,\n          spec_path: \$spec,'
    )

with open('$FILE', 'w') as f:
    f.write(content)
"
echo "  OK"

# --- docs/reference/hooks.md: update stale decision_record references ---
FILE="docs/reference/hooks.md"
if [ -f "$FILE" ]; then
    echo "Updating $FILE..."
    sed -i '' 's/decision record/plan path/g' "$FILE"
    sed -i '' 's/set_decision_record/set_plan_path/g' "$FILE"
    sed -i '' 's/get_decision_record/get_plan_path/g' "$FILE"
    echo "  OK"
fi

# --- workflow-state.sh: fix tests_passing gate for projects without test suites ---
FILE="$PLUGIN_DIR/scripts/workflow-state.sh"
echo "Updating $FILE (tests_passing gate fix)..."
python3 -c "
with open('$FILE') as f:
    content = f.read()

old = '''        missing=\$(_check_milestones \"implement\" \"plan_read\" \"tests_passing\" \"all_tasks_complete\")'''

new = '''        # Check if a test suite exists; skip tests_passing milestone if not
        local project_root
        project_root=\"\${CLAUDE_PROJECT_DIR:-\$(git rev-parse --show-toplevel 2>/dev/null || pwd)}\"
        local has_tests=false
        if find \"\$project_root\" -maxdepth 3 -name 'run-tests.sh' -o -name 'pytest.ini' -o -name 'jest.config.*' -o -name 'vitest.config.*' -o -name 'Cargo.toml' -o -name 'go.mod' 2>/dev/null | grep -q .; then
            has_tests=true
        elif [ -d \"\$project_root/tests\" ] || [ -d \"\$project_root/test\" ] || [ -d \"\$project_root/__tests__\" ]; then
            has_tests=true
        fi

        if [ \"\$has_tests\" = \"true\" ]; then
            missing=\$(_check_milestones \"implement\" \"plan_read\" \"tests_passing\" \"all_tasks_complete\")
        else
            missing=\$(_check_milestones \"implement\" \"plan_read\" \"all_tasks_complete\")
        fi'''

content = content.replace(old, new)
with open('$FILE', 'w') as f:
    f.write(content)
"
echo "  OK"

# --- plugin reference docs ---
FILE="$PLUGIN_DIR/docs/reference/agent-dispatch.md"
echo "Updating $FILE..."
sed -i '' 's|docs/superpowers/specs/2026-03-26-example-design.md|docs/plans/2026-03-26-example.md|' "$FILE"
echo "  OK"

FILE="$PLUGIN_DIR/docs/reference/wfm-architecture.md"
echo "Updating $FILE..."
sed -i '' 's|docs/superpowers/specs/, docs/plans/|docs/plans/|' "$FILE"
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
