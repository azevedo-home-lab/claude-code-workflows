Transition the workflow to REVIEW phase. First check the current phase:

```bash
WF_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}" && source "$WF_DIR/.claude/hooks/workflow-state.sh"
PHASE=$(get_phase)
if [ "$PHASE" != "implement" ] && [ "$PHASE" != "review" ]; then
    echo "ERROR: Cannot run /review from $PHASE phase. Use /approve first to enter IMPLEMENT, then /review."
    exit 1
fi
set_phase "review" && reset_review_status && cat > "$STATE_DIR/active-skill.json" <<'SK'
{"skill": "review-pipeline", "updated": "phase-transition"}
SK
echo "Phase set to REVIEW — running review pipeline."
```

Then confirm the phase change and execute the review pipeline below.

---

## Review Pipeline

**You MUST execute all steps in order. Do not skip any step.**

### Step 1: Run Tests

Look for test commands in the project:
- `tests/run-tests.sh` or similar test scripts in `tests/` directory
- `package.json` with test scripts (`npm test`)
- `pytest`, `make test`, `cargo test`, etc.

If tests found, run them and capture the output.
- If tests **pass**: report the result and continue.
- If tests **fail**: report the failures and ask: "Tests failed. Fix now or continue review?"
- If **no tests found**: report "No tests found — skipping verification" and continue.

Update state after this step:
```bash
WF_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}" && source "$WF_DIR/.claude/hooks/workflow-state.sh"
set_review_field "verification_complete" "true"
# If no tests were found, also set:
# set_review_field "verification_skipped" "true"
```

### Step 2: Detect Changed Files

Run these three commands and combine the results (deduplicate):
```bash
# Committed changes since main
git diff --name-only main...HEAD 2>/dev/null || true
# Unstaged changes
git diff --name-only
# Untracked files
git ls-files --others --exclude-standard
```

If no changes detected, report "No changes to review" and skip to the end. Update state with `agents_dispatched: true`, `findings_presented: true`, `findings_acknowledged: true`.

### Step 3: Dispatch 3 Review Agents in Parallel

Launch all three agents simultaneously using the Agent tool (3 parallel calls in one message). Pass each agent the list of changed files.

**Agent 1 — Code Quality Reviewer** (subagent_type: "code-review")
Prompt: "Review these changed files for code quality issues. Changed files: [LIST]. Project principles: KISS, DRY, SOLID, YAGNI. Check for: unnecessary complexity, code duplication, dead code, functions doing too many things, poor naming, missing error handling at system boundaries. For each finding report: Severity (CRITICAL/WARNING/SUGGESTION), File and line range, Description, Recommended fix. If no issues: 'No code quality issues found.' Keep output concise — findings only, limit to 2000 tokens."

**Agent 2 — Security Reviewer** (subagent_type: "code-review")
Prompt: "Review these changed files for security vulnerabilities. Changed files: [LIST]. Check for: command injection, hardcoded credentials/tokens/API keys, exposed internal IPs, XSS/SQL injection, unsafe file operations, insecure defaults. IMPORTANT: Consider execution context — scripts run by the user on their own infrastructure are NOT command injection. Only flag where untrusted input reaches a command. For each finding report: Severity (CRITICAL/WARNING/SUGGESTION), File and line range, Description and threat model, Recommended fix. If no issues: 'No security issues found.' Keep output concise — findings only, limit to 2000 tokens."

**Agent 3 — Architecture & Plan Compliance Reviewer** (subagent_type: "code-review")
Prompt: "Review these changed files for architectural issues and plan compliance. Changed files: [LIST]. Check for: does implementation match the plan/spec, are existing patterns followed, are component boundaries respected, new undocumented dependencies, regressions. For each finding report: Severity (CRITICAL/WARNING/SUGGESTION), File and line range, Description, Recommended fix. If no issues: 'No architectural issues found.' Keep output concise — findings only, limit to 2000 tokens."

If any agent fails or times out, note which agent failed and proceed with findings from agents that succeeded.

### Step 4: Dispatch Verification Agent

After all 3 review agents return, dispatch a single verification agent (subagent_type: "code-review"):

Prompt: "You are a code review verifier. Check each candidate finding against actual code to filter false positives. Candidate findings: [ALL FINDINGS FROM STEP 3]. For each finding: (1) Read the actual file and line range, (2) Check if issue is real — 'unused function' grep for calls, 'hardcoded credential' check if placeholder/comment, 'command injection' check if input is user-controlled, (3) Verdict: CONFIRMED / FALSE_POSITIVE / DOWNGRADE. Output only CONFIRMED and DOWNGRADED findings with: severity, file:line, description, which reviewer found it, brief verification evidence."

### Step 5: Consolidate and Present Findings

Take the verified findings and present a unified report:

1. Deduplicate: same file+line from multiple agents → merge
2. Rank by severity: 🔴 Critical → 🟡 Warning → 🟢 Suggestion
3. Present the report in this format:

```
## Review Findings

### 🔴 Critical (must fix before merge)
- [findings or "None"]

### 🟡 Warnings (should fix)
- [findings or "None"]

### 🟢 Suggestions (nice to have)
- [findings or "None"]

---
Would you like to:
1. Fix issues now (stay in REVIEW phase, re-run /review after fixing)
2. Proceed to /complete (acknowledge findings as-is)
```

Update state:
```bash
WF_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}" && source "$WF_DIR/.claude/hooks/workflow-state.sh"
set_review_field "agents_dispatched" "true"
set_review_field "findings_presented" "true"
```

Wait for the user's response. If they choose option 2 (acknowledge):
```bash
WF_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}" && source "$WF_DIR/.claude/hooks/workflow-state.sh"
set_review_field "findings_acknowledged" "true"
```
