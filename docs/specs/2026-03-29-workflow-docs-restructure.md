# Workflow Documentation Restructure — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restructure workflow documentation into two folders (`docs/plans/` for DISCUSS, `docs/specs/` for IMPLEMENT), fix backwards naming, embed ADRs into plans, and update all references across restricted plugin files.

**Architecture:** Migration in three phases — file moves via `git mv`, decision record folding, and a single migration script for restricted file updates. The script handles all `plugin/scripts/` and `plugin/commands/` changes atomically so the user runs it once.

**Tech Stack:** Bash (sed, git mv, jq), Markdown

**Spec:** `docs/superpowers/specs/2026-03-29-workflow-docs-restructure-design.md`

---

### Task 1: Create `docs/specs/` directory and move implementation plan files

**Files:**
- Create: `docs/specs/` directory
- Move: All 30 files from `docs/superpowers/plans/*.md` → `docs/specs/`

- [ ] **Step 1: Create target directory**

```bash
mkdir -p docs/specs
```

- [ ] **Step 2: Move all superpowers plan files to docs/specs/**

These files are task lists (detailed implementation steps) — they are specs by the new naming convention.

```bash
for f in docs/superpowers/plans/*.md; do
  git mv "$f" "docs/specs/$(basename "$f")"
done
```

- [ ] **Step 3: Verify moves**

Run: `ls docs/specs/ | wc -l`
Expected: 31 files (30 existing + this plan file itself)

- [ ] **Step 4: Commit**

```bash
git add -A docs/specs/ docs/superpowers/plans/
git commit -m "refactor: move implementation plans to docs/specs/ (naming fix)"
```

---

### Task 2: Move design docs from `docs/superpowers/specs/` to `docs/plans/`

**Files:**
- Move: All `*-design.md` files from `docs/superpowers/specs/` → `docs/plans/` (drop `-design` suffix)
- Move: Orphan files (no `-design`/`-decision` suffix) → `docs/plans/`
- Handle: `autonomy-levels` collision (two source files → one target)

- [ ] **Step 1: Move design files, dropping the `-design` suffix**

```bash
for f in docs/superpowers/specs/*-design.md; do
  base=$(basename "$f" | sed 's/-design\.md$/.md/')
  git mv "$f" "docs/plans/$base"
done
```

- [ ] **Step 2: Move orphan files (no standard suffix)**

Handle each explicitly. The `autonomy-levels` file collides with the design file moved in step 1 — append its content.

```bash
# These have no collision
git mv docs/superpowers/specs/2026-03-22-claude-mem-integration.md docs/plans/
git mv docs/superpowers/specs/2026-03-25-intent-file-redesign.md docs/plans/
git mv docs/superpowers/specs/2026-03-25-phase-token-security-model.md docs/plans/
git mv docs/superpowers/specs/2026-03-25-phase-transition-security.md docs/plans/
git mv docs/superpowers/specs/2026-03-29-dual-hook-execution-bug.md docs/plans/

# This one (the spec we wrote this session) self-migrates, dropping -design
git mv docs/superpowers/specs/2026-03-29-workflow-docs-restructure-design.md docs/plans/2026-03-29-workflow-docs-restructure.md

# autonomy-levels collision: append orphan content to already-moved design file
cat docs/superpowers/specs/2026-03-22-autonomy-levels.md >> docs/plans/2026-03-22-autonomy-levels.md
git rm docs/superpowers/specs/2026-03-22-autonomy-levels.md
```

- [ ] **Step 3: Verify only decision files remain in superpowers/specs/**

Run: `ls docs/superpowers/specs/`
Expected: Only `*-decision.md` and `*-decisions.md` files (3 files)

- [ ] **Step 4: Commit**

```bash
git add -A docs/plans/ docs/superpowers/specs/
git commit -m "refactor: move design docs to docs/plans/ (naming fix)"
```

---

### Task 3: Fold decision records into plan files

**Files:**
- Fold: 3 files from `docs/superpowers/specs/*-decision*.md` into corresponding `docs/plans/` files
- Fold: 6 files from `docs/plans/*-decisions.md` into corresponding `docs/plans/` files (from old design docs)
- Fold: 1 file from `docs/decisions/` into corresponding `docs/plans/` file
- Rename: 3 standalone decision files (no matching design doc) to plan files
- Keep: 1 file already in `docs/plans/` without `-decisions` suffix

- [ ] **Step 1: Fold decision files that have matching plan files**

Append decision content under a `## Decision Record (Archived)` heading into the matching plan.

```bash
# From docs/superpowers/specs/ (3 files)
echo -e "\n\n## Decision Record (Archived)\n" >> docs/plans/2026-03-23-open-issues-cleanup.md
cat docs/superpowers/specs/2026-03-23-open-issues-cleanup-decision.md >> docs/plans/2026-03-23-open-issues-cleanup.md
git rm docs/superpowers/specs/2026-03-23-open-issues-cleanup-decision.md

echo -e "\n\n## Decision Record (Archived)\n" >> docs/plans/2026-03-23-tech-debt-cleanup.md
cat docs/superpowers/specs/2026-03-23-tech-debt-cleanup-decision.md >> docs/plans/2026-03-23-tech-debt-cleanup.md
git rm docs/superpowers/specs/2026-03-23-tech-debt-cleanup-decision.md

echo -e "\n\n## Decision Record (Archived)\n" >> docs/plans/2026-03-27-v1.12.0-robustness-extraction.md
cat docs/superpowers/specs/2026-03-27-v1.12.0-decisions.md >> docs/plans/2026-03-27-v1.12.0-robustness-extraction.md
git rm docs/superpowers/specs/2026-03-27-v1.12.0-decisions.md

# From docs/plans/ — these have matching plan files that came from superpowers/specs/
echo -e "\n\n## Decision Record (Archived)\n" >> docs/plans/2026-03-26-guard-hardening-step-enforcement.md
cat docs/plans/2026-03-26-guard-hardening-step-enforcement-decisions.md >> docs/plans/2026-03-26-guard-hardening-step-enforcement.md
git rm docs/plans/2026-03-26-guard-hardening-step-enforcement-decisions.md

echo -e "\n\n## Decision Record (Archived)\n" >> docs/plans/2026-03-26-statusline-debug.md
cat docs/plans/2026-03-26-statusline-debug-decisions.md >> docs/plans/2026-03-26-statusline-debug.md
git rm docs/plans/2026-03-26-statusline-debug-decisions.md

echo -e "\n\n## Decision Record (Archived)\n" >> docs/plans/2026-03-27-security-fixes-architecture-cleanup.md
cat docs/plans/2026-03-27-security-fixes-architecture-cleanup-decisions.md >> docs/plans/2026-03-27-security-fixes-architecture-cleanup.md
git rm docs/plans/2026-03-27-security-fixes-architecture-cleanup-decisions.md

# From docs/decisions/ (1 file)
echo -e "\n\n## Decision Record (Archived)\n" >> docs/plans/2026-03-23-remaining-tech-debt.md
cat docs/decisions/2026-03-23-remaining-tech-debt-cleanup.md >> docs/plans/2026-03-23-remaining-tech-debt.md
git rm docs/decisions/2026-03-23-remaining-tech-debt-cleanup.md
```

- [ ] **Step 2: Rename standalone decision files to plan files**

These have no matching design doc — the decision record IS the plan.

```bash
git mv docs/plans/2026-03-26-autonomy-aliases-decisions.md docs/plans/2026-03-26-autonomy-aliases.md
git mv docs/plans/2026-03-26-tech-debt-github-sync-decisions.md docs/plans/2026-03-26-tech-debt-github-sync.md
git mv docs/plans/2026-03-28-wfm-auth-path-separation-decisions.md docs/plans/2026-03-28-wfm-auth-path-separation.md
```

Note: `docs/plans/2026-03-15-workflow-enforcement-hooks.md` already has no `-decisions` suffix — leave it as-is.

- [ ] **Step 3: Clean up empty directories**

```bash
rmdir docs/superpowers/specs/ docs/superpowers/plans/ docs/superpowers/ docs/decisions/ 2>/dev/null || true
```

- [ ] **Step 4: Verify final structure**

Run: `find docs/plans docs/specs -name '*.md' | wc -l`
Expected: All files accounted for (plans + specs)

Run: `ls docs/superpowers/ 2>/dev/null`
Expected: Directory does not exist

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "refactor: fold decision records into plans, clean up superpowers/"
```

---

### Task 4: Create restricted-files migration script

**Files:**
- Create: `scripts/migrate-docs-structure.sh`

This script makes all the changes to protected plugin files. The user runs it once.

- [ ] **Step 1: Write the migration script**

Create `scripts/migrate-docs-structure.sh` with all sed replacements for:

**workflow-gate.sh:**
- Line 12: Update comment — remove `docs/superpowers/specs/, docs/superpowers/plans/,` references

**bash-write-guard.sh:**
- Line 13: Update comment — remove `docs/superpowers/specs/, docs/superpowers/plans/,` references

**workflow-state.sh:**
- Line 62: Update `RESTRICTED_WRITE_WHITELIST` regex — remove `docs/superpowers/specs/|docs/superpowers/plans/|`, result: `'(\.claude/state/|docs/plans/)'`
- Lines 486-499: Rename `decision_record` functions to `plan_path` functions (rename section header, function names, jq field)
- Add new `spec_path` functions after plan_path (same pattern)
- Line 339: Change `preserved_decision=$(get_decision_record)` → `preserved_decision=$(get_plan_path)`
- Line 407: Change `preserved_decision=""` variable name stays (it's a local var, renaming is cosmetic)
- Line 429: Change `--arg decision "$preserved_decision"` stays (local var)
- Line 440: Change `decision_record: $decision` → `plan_path: $decision` in jq template
- Lines 527-534: Update `check_soft_gate` implement case — search `docs/plans` only, check for Decision section with `grep -l "## Decision" "$project_root/docs/plans/"*.md`

**user-set-phase.sh:**
- Line 88: Change `decision_record: $decision` → `plan_path: $decision` in jq template

**workflow-cmd.sh:**
- Line 30: Change `get_decision_record|set_decision_record` → `get_plan_path|set_plan_path|get_spec_path|set_spec_path`

**post-tool-navigator.sh:**
- Lines 212-215: Remove `decision_record_define` trigger block (DEFINE no longer writes a decision record — it writes a plan)
- Lines 224: Change `(docs/superpowers/plans/|docs/plans/)` → `docs/plans/`
- Lines 253-255: Remove `decision_record_edit` trigger block in COMPLETE
- Lines 540: Change `(docs/superpowers/plans/|docs/plans/)` → `docs/plans/`
- Lines 562: Change `decisions\.md` → `docs/specs/` pattern for REVIEW phase spec updates

**setup.sh:**
- Line 50: Change `decision_record: ""` → `plan_path: ""`

**define.md:**
- Replace decision record creation instructions with plan creation at `docs/plans/YYYY-MM-DD-<topic>.md`
- Replace `set_decision_record` → `set_plan_path`
- Update git instructions to reference `docs/plans/`

**discuss.md:**
- Replace `get_decision_record` → `get_plan_path`
- Remove `docs/superpowers/specs/` and `docs/superpowers/plans/` references
- Update git instructions

**implement.md:**
- Line 39: Change `Decision record: [DECISION_RECORD_PATH]` → `Plan: [PLAN_PATH]`
- Add spec creation step before implementation begins (write spec to `docs/specs/`, call `set_spec_path`)

**review.md:**
- Line 68: Change plan lookup paths to `docs/plans/` only
- Line 92: Change `get_decision_record` → `get_plan_path`, update to write deviations to spec file instead of decision record

**complete.md:**
- Lines 62, 65, 81-83: Replace all `decision_record`/`get_decision_record` → `plan_path`/`get_plan_path`
- Replace `docs/superpowers/specs/` → `docs/specs/` (was never `docs/specs/` before — but now spec lookup is there)
- Replace `docs/superpowers/plans/` → `docs/plans/`

```bash
cat > scripts/migrate-docs-structure.sh << 'SCRIPT_EOF'
#!/usr/bin/env bash
# Migration script for workflow documentation restructure.
# Updates all restricted plugin files to use new docs/plans/ and docs/specs/ structure.
# Run once from project root.
set -euo pipefail

PLUGIN_DIR="plugin"

echo "=== Workflow Documentation Structure Migration ==="
echo ""

# --- workflow-state.sh ---
FILE="$PLUGIN_DIR/scripts/workflow-state.sh"
echo "Updating $FILE..."

# Update restricted write whitelist
sed -i '' "s|RESTRICTED_WRITE_WHITELIST='(\\\\\.claude/state/|docs/superpowers/specs/|docs/superpowers/plans/|docs/plans/)'|RESTRICTED_WRITE_WHITELIST='(\\\\.claude/state/|docs/plans/)'|" "$FILE"

# Rename decision_record section header
sed -i '' 's/# Decision record management/# Plan path management/' "$FILE"

# Rename decision_record functions to plan_path
sed -i '' 's/set_decision_record()/set_plan_path()/' "$FILE"
sed -i '' 's/get_decision_record()/get_plan_path()/' "$FILE"
sed -i '' "s/.decision_record = /.plan_path = /" "$FILE"
sed -i '' "s/.decision_record //.plan_path /" "$FILE"

# Rename preserved state reader
sed -i '' 's/preserved_decision=$(get_decision_record)/preserved_decision=$(get_plan_path)/' "$FILE"

# Update jq template field name (agent_set_phase)
sed -i '' 's/decision_record: \$decision/plan_path: \$decision/' "$FILE"

# Update soft gate to search docs/plans only
sed -i '' 's|find "\$project_root/docs/superpowers/plans" "\$project_root/docs/plans"|find "\$project_root/docs/plans"|' "$FILE"

# Add spec_path functions after plan_path functions
sed -i '' '/^get_plan_path()/,/^}/ {
/^}/a\
\
set_spec_path() { if [ ! -f "$STATE_FILE" ]; then return; fi; _update_state '"'"'.spec_path = $v'"'"' --arg v "$1"; }\
\
get_spec_path() {\
    if [ ! -f "$STATE_FILE" ]; then\
        echo ""\
        return\
    fi\
    local val\
    val=$(jq -r '"'"'.spec_path // ""'"'"' "$STATE_FILE" 2>/dev/null) || val=""\
    echo "$val"\
}
}' "$FILE"

echo "  Done."

# --- user-set-phase.sh ---
FILE="$PLUGIN_DIR/scripts/user-set-phase.sh"
echo "Updating $FILE..."
sed -i '' 's/decision_record: \$decision/plan_path: \$decision/' "$FILE"
echo "  Done."

# --- workflow-cmd.sh ---
FILE="$PLUGIN_DIR/scripts/workflow-cmd.sh"
echo "Updating $FILE..."
sed -i '' 's/get_decision_record|set_decision_record/get_plan_path|set_plan_path|get_spec_path|set_spec_path/' "$FILE"
echo "  Done."

# --- post-tool-navigator.sh ---
FILE="$PLUGIN_DIR/scripts/post-tool-navigator.sh"
echo "Updating $FILE..."

# Update DISCUSS plan write path check
sed -i '' "s|(docs/superpowers/plans/|docs/plans/)|docs/plans/|g" "$FILE"

# Remove decision_record_define trigger (DEFINE no longer writes decision records)
# Replace with plan_write_define trigger for plan creation
sed -i '' 's/decisions\\.md/docs\/plans\//; s/decision_record_define/plan_write_define/; s/Challenge vague problem statements. Outcomes must be verifiable, not aspirational./Challenge vague problem statements. Outcomes must be verifiable. Problem and Goals sections must be concrete./' "$FILE"

# Remove decision_record_edit trigger in COMPLETE, replace with project_docs trigger
sed -i '' '/complete)/,/;;/ {
  s/decisions\\.md/docs\//
  s/decision_record_edit/project_docs_edit/
}' "$FILE"

# Update REVIEW phase decisions.md check to docs/specs/
sed -i '' '/review)/,/fi/ {
  s/decisions\\.md/docs\/specs\//
}' "$FILE"

echo "  Done."

# --- workflow-gate.sh ---
FILE="$PLUGIN_DIR/scripts/workflow-gate.sh"
echo "Updating $FILE..."
sed -i '' 's|docs/superpowers/specs/, docs/superpowers/plans/, docs/plans/|docs/plans/|g' "$FILE"
echo "  Done."

# --- bash-write-guard.sh ---
FILE="$PLUGIN_DIR/scripts/bash-write-guard.sh"
echo "Updating $FILE..."
sed -i '' 's|docs/superpowers/specs/, docs/superpowers/plans/, docs/plans/|docs/plans/|g' "$FILE"
echo "  Done."

# --- setup.sh ---
FILE="$PLUGIN_DIR/scripts/setup.sh"
echo "Updating $FILE..."
sed -i '' 's/decision_record: ""/plan_path: "",\
    spec_path: ""/' "$FILE"
echo "  Done."

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
echo "  Done."

# --- discuss.md ---
FILE="$PLUGIN_DIR/commands/discuss.md"
echo "Updating $FILE..."
sed -i '' 's|docs/superpowers/specs/|docs/plans/|g' "$FILE"
sed -i '' 's|docs/superpowers/plans/|docs/specs/|g' "$FILE"
sed -i '' 's/set_decision_record/set_plan_path/g' "$FILE"
sed -i '' 's/get_decision_record/get_plan_path/g' "$FILE"
sed -i '' 's/decision record/plan/g' "$FILE"
sed -i '' 's/Decision record/Plan/g' "$FILE"
echo "  Done."

# --- implement.md ---
FILE="$PLUGIN_DIR/commands/implement.md"
echo "Updating $FILE..."
sed -i '' 's/Decision record: \[DECISION_RECORD_PATH\]/Plan: [PLAN_PATH]/' "$FILE"
sed -i '' 's/get_decision_record/get_plan_path/g' "$FILE"
sed -i '' 's/decision record/plan/g' "$FILE"
echo "  Done."

# --- review.md ---
FILE="$PLUGIN_DIR/commands/review.md"
echo "Updating $FILE..."
sed -i '' 's|docs/superpowers/plans/|docs/plans/|g' "$FILE"
sed -i '' 's|docs/superpowers/specs/|docs/specs/|g' "$FILE"
sed -i '' 's/get_decision_record/get_plan_path/g' "$FILE"
sed -i '' 's/decision record/plan/g' "$FILE"
echo "  Done."

# --- complete.md ---
FILE="$PLUGIN_DIR/commands/complete.md"
echo "Updating $FILE..."
sed -i '' 's|docs/superpowers/plans/|docs/plans/|g' "$FILE"
sed -i '' 's|docs/superpowers/specs/|docs/specs/|g' "$FILE"
sed -i '' 's/get_decision_record/get_plan_path/g' "$FILE"
sed -i '' 's/Decision record/Plan/g' "$FILE"
sed -i '' 's/decision record/plan/g' "$FILE"
echo "  Done."

# --- Update brainstorming skill cache ---
SKILL_CACHE="$HOME/.claude/plugins/cache/superpowers-marketplace/superpowers"
if [ -d "$SKILL_CACHE" ]; then
    echo "Updating brainstorming skill cache..."
    find "$SKILL_CACHE" -name "SKILL.md" -path "*/brainstorming/*" -exec sed -i '' 's|docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md|docs/plans/YYYY-MM-DD-<topic>.md|g' {} \;
    find "$SKILL_CACHE" -name "spec-document-reviewer-prompt.md" -exec sed -i '' 's|docs/superpowers/specs/|docs/plans/|g' {} \;
    echo "  Done."

    echo "Updating writing-plans skill cache..."
    find "$SKILL_CACHE" -name "SKILL.md" -path "*/writing-plans/*" -exec sed -i '' 's|docs/superpowers/plans/YYYY-MM-DD-<feature-name>.md|docs/specs/YYYY-MM-DD-<feature-name>.md|g' {} \;
    find "$SKILL_CACHE" -name "SKILL.md" -path "*/writing-plans/*" -exec sed -i '' 's|docs/superpowers/plans/|docs/specs/|g' {} \;
    echo "  Done."
else
    echo "WARNING: Skill cache not found at $SKILL_CACHE — update brainstorming/writing-plans skills manually."
fi

echo ""
echo "=== Migration complete ==="
echo "Verify with: git diff --stat"
echo "Then commit: git add -A plugin/ && git commit -m 'refactor: update all plugin references for docs restructure'"
SCRIPT_EOF
chmod +x scripts/migrate-docs-structure.sh
```

- [ ] **Step 2: Verify script is executable**

Run: `head -5 scripts/migrate-docs-structure.sh`
Expected: Shebang line visible

- [ ] **Step 3: Commit the script**

```bash
git add scripts/migrate-docs-structure.sh
git commit -m "feat: add migration script for docs restructure"
```

---

### Task 5: Run migration script and verify

**Files:**
- Modify: All files listed in Task 4's sed replacements

- [ ] **Step 1: Run the migration script**

```bash
bash scripts/migrate-docs-structure.sh
```

Expected: Each file prints "Done." with no errors.

- [ ] **Step 2: Verify key changes**

```bash
# Check whitelist is correct
grep "RESTRICTED_WRITE_WHITELIST" plugin/scripts/workflow-state.sh

# Check decision_record is fully gone
grep -r "decision_record" plugin/ || echo "PASS: no decision_record references"

# Check docs/superpowers is fully gone from references
grep -r "docs/superpowers" plugin/ || echo "PASS: no docs/superpowers references"

# Check new functions exist
grep "set_plan_path\|get_plan_path\|set_spec_path\|get_spec_path" plugin/scripts/workflow-state.sh
```

- [ ] **Step 3: Verify workflow.json init template**

```bash
grep "plan_path" plugin/scripts/setup.sh
```

Expected: `plan_path: ""`

- [ ] **Step 4: Commit all plugin changes**

```bash
git add -A plugin/
git commit -m "refactor: update all plugin references for docs restructure"
```

---

### Task 6: Update existing workflow state and run tests

**Files:**
- Modify: `.claude/state/workflow.json` (if it exists and has `decision_record` field)
- Run: Test suite

- [ ] **Step 1: Update existing workflow state file**

```bash
if [ -f .claude/state/workflow.json ]; then
  jq '.plan_path = (.decision_record // "") | del(.decision_record)' .claude/state/workflow.json > /tmp/wf-tmp.json && mv /tmp/wf-tmp.json .claude/state/workflow.json
  echo "Updated workflow.json"
else
  echo "No workflow.json to update"
fi
```

- [ ] **Step 2: Run test suite**

```bash
bash tests/run-tests.sh
```

Expected: All tests pass. If tests reference old paths, fix them.

- [ ] **Step 3: Clean up migration script**

The migration script is a one-time tool. Keep it in the repo for reference or delete it:

```bash
git rm scripts/migrate-docs-structure.sh
git commit -m "chore: remove one-time migration script"
```

- [ ] **Step 4: Final verification**

```bash
# Confirm folder structure
echo "=== docs/plans/ ===" && ls docs/plans/ | wc -l
echo "=== docs/specs/ ===" && ls docs/specs/ | wc -l
echo "=== docs/superpowers/ ===" && ls docs/superpowers/ 2>/dev/null || echo "GONE"
echo "=== docs/decisions/ ===" && ls docs/decisions/ 2>/dev/null || echo "GONE"

# Confirm no stale references
grep -r "docs/superpowers" . --include="*.sh" --include="*.md" -l | grep -v node_modules || echo "PASS"
grep -r "decision_record" . --include="*.sh" --include="*.md" -l | grep -v node_modules || echo "PASS"
```
