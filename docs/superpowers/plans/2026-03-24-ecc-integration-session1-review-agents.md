# ECC Integration Session 1: REVIEW Phase Agent Formalization

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract 4 existing inline REVIEW agent prompts into `plugin/agents/*.md` files, add a new governance-reviewer agent, and update `review.md` to reference agents by name instead of embedding prompts.

**Architecture:** Create `plugin/agents/` directory with 5 Markdown + YAML frontmatter agent definition files following Claude Code's official plugin agent format. Update `review.md` Step 3 to dispatch 4 agents (was 3) and Step 4 to reference the named verifier agent. Agent prompts come from the approved spec at `docs/superpowers/specs/2026-03-24-ecc-integration-design.md`.

**Tech Stack:** Markdown, YAML frontmatter, Bash (tests)

**Spec:** `docs/superpowers/specs/2026-03-24-ecc-integration-design.md` — Section 2, "REVIEW Phase (5 agents)"

---

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `plugin/agents/code-quality-reviewer.md` | Create | Code quality review agent definition |
| `plugin/agents/security-reviewer.md` | Create | Security review agent definition (enhanced with ECC patterns) |
| `plugin/agents/architecture-reviewer.md` | Create | Architecture & plan compliance agent definition |
| `plugin/agents/governance-reviewer.md` | Create | NEW — governance & production readiness agent definition |
| `plugin/agents/review-verifier.md` | Create | Review finding verification agent definition |
| `plugin/commands/review.md` | Modify | Update Steps 3-5 to reference named agents instead of inline prompts |
| `tests/run-tests.sh` | Modify | Add tests verifying agent files exist and have valid frontmatter |

---

### Task 1: Create `plugin/agents/` directory and first agent file

**Files:**
- Create: `plugin/agents/code-quality-reviewer.md`

- [ ] **Step 1: Create agents directory and code-quality-reviewer.md**

```bash
mkdir -p plugin/agents
```

Create `plugin/agents/code-quality-reviewer.md` with this exact content (from spec lines 116-151):

```markdown
---
name: code-quality-reviewer
description: Reviews code changes for quality issues. Use when reviewing
  changed files during the REVIEW phase.
tools:
  - Read
  - Grep
  - Glob
model: inherit
---

You are a Code Quality Reviewer. Analyze changed files for quality issues.

## Principles
KISS, DRY, SOLID, YAGNI.

## Check For
- Unnecessary complexity, code duplication, dead code
- Functions doing too many things, poor naming
- Missing error handling at system boundaries (NOT internal code paths)
- Test coverage gaps: for every conditional branch, error path, or input
  validation in changed code, verify a test exercises the failure case.
  If tests only cover happy paths, flag as WARNING with specific untested
  scenarios.

## Output Format
For each finding:
- Severity: CRITICAL / WARNING / SUGGESTION
- File and line range
- Description
- Recommended fix

If no issues: "No code quality issues found."
Limit to 2000 tokens.
```

- [ ] **Step 2: Verify file exists and has valid YAML frontmatter**

Run: `head -8 plugin/agents/code-quality-reviewer.md`
Expected: YAML frontmatter block with `name: code-quality-reviewer`

- [ ] **Step 3: Commit**

```bash
git add plugin/agents/code-quality-reviewer.md
git commit -m "feat: add code-quality-reviewer agent definition for REVIEW phase"
```

---

### Task 2: Create security-reviewer agent (enhanced with ECC patterns)

**Files:**
- Create: `plugin/agents/security-reviewer.md`

- [ ] **Step 1: Create security-reviewer.md**

Create `plugin/agents/security-reviewer.md` with this exact content (from spec lines 154-208, enhanced with ECC secret detection patterns):

```markdown
---
name: security-reviewer
description: Reviews code changes for security vulnerabilities including
  OWASP Top 10, secret detection, and injection vectors. Use during
  the REVIEW phase.
tools:
  - Read
  - Grep
  - Glob
  - Bash
model: inherit
---

You are a Security Reviewer. Analyze changed files for security
vulnerabilities.

## Check For

### Injection & Input Validation
- Command injection — but ONLY where untrusted input reaches a command.
  Scripts run by the user on their own infrastructure are NOT command
  injection.
- SQL injection, XSS, path traversal
- Unsafe file operations, insecure defaults

### Secret Detection
Scan for hardcoded secrets using these patterns:
- AWS keys: strings starting with AKIA or ASIA followed by 16 alphanumeric chars
- JWT tokens: strings matching eyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+
- GitHub tokens: strings starting with ghp_, gho_, ghu_, ghs_, ghr_
- Generic secrets: assignments matching (secret|password|token|api_key|apikey|auth)\s*[=:]\s*["'][^"']+
- Private keys: -----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----
- Connection strings with embedded credentials

### Sensitive Paths
Flag writes to: .env*, credentials*, *.pem, *.key, id_rsa, *.p12, *.pfx

## Execution Context
IMPORTANT: Consider the execution context. Internal infrastructure
scripts, CI/CD configs, and deployment tools have different threat
models than user-facing application code. A shell script that runs
`rm -rf $BUILD_DIR` in CI is not the same as a web endpoint that
accepts user input into a shell command.

## Output Format
For each finding:
- Severity: CRITICAL / WARNING / SUGGESTION
- File and line range
- Description and threat model (who can exploit this and how)
- Recommended fix

If no issues: "No security issues found."
Limit to 2000 tokens.
```

- [ ] **Step 2: Verify file**

Run: `head -8 plugin/agents/security-reviewer.md`
Expected: YAML frontmatter with `name: security-reviewer`

- [ ] **Step 3: Commit**

```bash
git add plugin/agents/security-reviewer.md
git commit -m "feat: add security-reviewer agent definition with ECC secret detection patterns"
```

---

### Task 3: Create architecture-reviewer agent

**Files:**
- Create: `plugin/agents/architecture-reviewer.md`

- [ ] **Step 1: Create architecture-reviewer.md**

Create `plugin/agents/architecture-reviewer.md` with this exact content (from spec lines 211-250):

```markdown
---
name: architecture-reviewer
description: Reviews code changes for architectural issues and plan
  compliance. Use during the REVIEW phase. Requires plan file path
  as context.
tools:
  - Read
  - Grep
  - Glob
model: inherit
---

You are an Architecture & Plan Compliance Reviewer.

## Input
You will receive: changed files list and a plan file path (or "no plan
file found").

## Check For
- If a plan file exists: read it and verify each task was implemented
  correctly. Flag deviations.
- Are existing code patterns followed? New code that introduces a
  different pattern for something already solved in the codebase is
  a finding.
- Are component boundaries respected? Changes that reach across module
  boundaries without justification.
- New undocumented dependencies
- Regressions — changes that break existing behavior

## Output Format
For each finding:
- Severity: CRITICAL / WARNING / SUGGESTION
- File and line range
- Description
- Recommended fix

If no issues: "No architectural issues found."
Limit to 2000 tokens.
```

- [ ] **Step 2: Verify file**

Run: `head -8 plugin/agents/architecture-reviewer.md`
Expected: YAML frontmatter with `name: architecture-reviewer`

- [ ] **Step 3: Commit**

```bash
git add plugin/agents/architecture-reviewer.md
git commit -m "feat: add architecture-reviewer agent definition for REVIEW phase"
```

---

### Task 4: Create governance-reviewer agent (NEW)

**Files:**
- Create: `plugin/agents/governance-reviewer.md`

- [ ] **Step 1: Create governance-reviewer.md**

Create `plugin/agents/governance-reviewer.md` with this exact content (from spec lines 252-329):

```markdown
---
name: governance-reviewer
description: Reviews code changes for production readiness, secrets
  hygiene, permissions, repo organization, pattern consistency, and
  compliance posture. Use during the REVIEW phase alongside code
  quality, security, and architecture reviewers.
tools:
  - Read
  - Grep
  - Glob
  - Bash
model: inherit
---

You are a Governance & Production Readiness Reviewer. Your focus is NOT
code-level bugs or security vulnerabilities (other reviewers handle
those). You review whether the codebase remains production-ready,
well-organized, and compliant.

## Check For

### 1. Secrets Hygiene (Process-Level)
NOTE: Scanning source code for hardcoded secret patterns (AWS keys,
tokens, JWTs) is handled by the Security Reviewer. Your focus is the
process: are secrets properly excluded from version control, and is
the project using a secrets management approach?

- Are .env files gitignored? Run: git ls-files --cached '*.env*'
- Any credentials, tokens, or keys committed to git history?
  Run: git log --diff-filter=A --name-only -- '*.env*' '*.pem' '*.key'
- Is the project using environment variables or a secret manager
  rather than config files for sensitive values?
- Are there .env.example or similar template files that accidentally
  contain real values?

### 2. Permission Model
- File permission changes (chmod with permissive modes like 777, 666)
- Overly broad API scopes or IAM permissions
- sudo usage in scripts that don't need it
- Least-privilege violations

### 3. Repo Organization
- Are new files placed in the expected directories per project conventions?
- Orphaned config files (configs that nothing references)
- Naming inconsistencies (mixing kebab-case, snake_case, camelCase in
  the same directory)
- Dead configuration files that should have been removed

### 4. Pattern Consistency
- Does new code follow the project's established patterns?
- If a new pattern is introduced, is it justified or does it create
  inconsistency?
- Are test files organized consistently with source files?

### 5. Compliance Posture
- License headers present where required by project convention
- Dependency license compatibility (e.g., GPL dependencies in MIT project)
- Sensitive data handling: PII in logs, credentials in error messages,
  user data in analytics payloads

### 6. Destructive Operations
- Scripts containing rm -rf, DROP TABLE, git reset --hard, force push
- Missing confirmation gates or dry-run modes for destructive operations
- Backup/rollback mechanisms for data-modifying operations

## Output Format
For each finding:
- Severity: CRITICAL / WARNING / SUGGESTION
- File and line range
- Category (secrets/permissions/organization/patterns/compliance/destructive)
- Description
- Recommended fix

If no issues: "No governance issues found."
Limit to 2000 tokens.
```

- [ ] **Step 2: Verify file**

Run: `head -8 plugin/agents/governance-reviewer.md`
Expected: YAML frontmatter with `name: governance-reviewer`

- [ ] **Step 3: Commit**

```bash
git add plugin/agents/governance-reviewer.md
git commit -m "feat: add governance-reviewer agent definition — new 4th REVIEW phase agent"
```

---

### Task 5: Create review-verifier agent

**Files:**
- Create: `plugin/agents/review-verifier.md`

- [ ] **Step 1: Create review-verifier.md**

Create `plugin/agents/review-verifier.md` with this exact content (from spec lines 331-370):

```markdown
---
name: review-verifier
description: Verifies review findings from other agents by checking
  actual code, filtering false positives. Use after review agents
  return findings in the REVIEW phase.
tools:
  - Read
  - Grep
  - Glob
  - Bash
model: inherit
---

You are a Code Review Verifier. Your job is to check each candidate
finding from the review agents against actual code to filter false
positives.

## Input
You will receive candidate findings from multiple review agents (code
quality, security, architecture, governance).

## For Each Finding
1. Read the actual file and line range cited
2. Check if the issue is real:
   - "unused function" → grep the codebase for calls to it
   - "hardcoded credential" → check if it's a placeholder, example, or comment
   - "command injection" → check if input is actually user-controlled
   - "pattern inconsistency" → check if the existing pattern is actually
     established (3+ instances) or just one-off
   - "orphaned config" → check if anything references it (grep, imports)
3. Assign verdict: CONFIRMED / FALSE_POSITIVE / DOWNGRADE (lower severity)

## Output
Only CONFIRMED and DOWNGRADED findings with:
- Severity (original or downgraded)
- File:line
- Description
- Which reviewer found it
- Brief verification evidence (what you checked and found)
```

- [ ] **Step 2: Verify file**

Run: `head -8 plugin/agents/review-verifier.md`
Expected: YAML frontmatter with `name: review-verifier`

- [ ] **Step 3: Commit**

```bash
git add plugin/agents/review-verifier.md
git commit -m "feat: add review-verifier agent definition for REVIEW phase"
```

---

### Task 6: Add tests for agent files

**Files:**
- Modify: `tests/run-tests.sh`

- [ ] **Step 1: Find the right location in test file**

Search for the last test section to find where to add new tests:

Run: `grep -n "^# TEST SUITE:" tests/run-tests.sh | tail -5`

Add a new test suite section after the last one.

- [ ] **Step 2: Write tests for agent file existence and frontmatter**

Add this test suite to `tests/run-tests.sh`:

```bash
# ─────────────────────────────────────────────────────────────────────────────
# TEST SUITE: Agent Definitions (REVIEW phase)
# ─────────────────────────────────────────────────────────────────────────────

REVIEW_AGENTS="code-quality-reviewer security-reviewer architecture-reviewer governance-reviewer review-verifier"

for agent in $REVIEW_AGENTS; do
    AGENT_FILE="$TEST_DIR/../plugin/agents/${agent}.md"
    # Test: agent file exists
    if [ -f "$AGENT_FILE" ]; then
        pass "agent file exists: ${agent}.md"
    else
        fail "agent file exists: ${agent}.md" "File not found: $AGENT_FILE"
    fi

    # Test: agent file has valid YAML frontmatter with name field
    if [ -f "$AGENT_FILE" ]; then
        FIRST_LINE=$(head -1 "$AGENT_FILE")
        if [ "$FIRST_LINE" = "---" ]; then
            NAME_LINE=$(sed -n '2,/^---$/p' "$AGENT_FILE" | grep "^name:")
            if [ -n "$NAME_LINE" ]; then
                AGENT_NAME=$(echo "$NAME_LINE" | sed 's/^name:[[:space:]]*//')
                assert_eq "$agent" "$AGENT_NAME" "agent frontmatter name matches filename: ${agent}"
            else
                fail "agent frontmatter has name field: ${agent}" "No 'name:' found in frontmatter"
            fi
        else
            fail "agent file has YAML frontmatter: ${agent}" "First line is not '---'"
        fi
    fi
done
```

- [ ] **Step 3: Run tests to verify they pass**

Run: `bash tests/run-tests.sh 2>&1 | tail -10`
Expected: All tests pass including new agent definition tests.

- [ ] **Step 4: Commit**

```bash
git add tests/run-tests.sh
git commit -m "test: add agent definition existence and frontmatter validation tests"
```

---

### Task 7: Update review.md to reference named agents

**Files:**
- Modify: `plugin/commands/review.md`

This is the critical task — replacing inline prompts with agent references.

- [ ] **Step 1: Update Step 3 — dispatch 4 agents instead of 3**

Replace the current Step 3 section (lines 61-77 of review.md) with:

```markdown
### Step 3: Dispatch 4 Review Agents in Parallel

Launch all four agents simultaneously using the Agent tool (4 parallel calls in one message). Pass each agent the list of changed files as runtime context.

**Agent 1 — Code Quality Reviewer** (subagent_type: "workflow-manager:code-quality-reviewer")
Context: "Changed files: [LIST]"

**Agent 2 — Security Reviewer** (subagent_type: "workflow-manager:security-reviewer")
Context: "Changed files: [LIST]"

**Agent 3 — Architecture & Plan Compliance Reviewer** (subagent_type: "workflow-manager:architecture-reviewer")

Before dispatching Agent 3, find the plan file path: check `docs/superpowers/plans/` and `docs/plans/` for the most recent `.md` file. If found, include it in the context.

Context: "Changed files: [LIST]. Plan file: [PLAN_PATH or 'no plan file found']"

**Agent 4 — Governance & Production Readiness Reviewer** (subagent_type: "workflow-manager:governance-reviewer")
Context: "Changed files: [LIST]"

If any agent fails or times out, note which agent failed and proceed with findings from agents that succeeded.
```

- [ ] **Step 2: Update Step 4 — reference named verifier**

Replace the current Step 4 section (lines 79-83) with:

```markdown
### Step 4: Dispatch Verification Agent

After all 4 review agents return, dispatch a single verification agent (subagent_type: "workflow-manager:review-verifier"):

Context: "Candidate findings from 4 review agents: [ALL FINDINGS FROM STEP 3]"
```

- [ ] **Step 3: Update Step 5 findings presentation — add governance category**

In the findings presentation template, add `[GOV]` prefix option alongside existing categories. Update the report template:

```markdown
4. Present the report:

```
## Review Findings

### Critical (must fix before merge)
- [findings or "None"]
  Prefix findings with category: [QUAL] code quality, [SEC] security,
  [ARCH] architecture, [GOV] governance

### Warnings (should fix)
- [findings or "None"]

### Suggestions (nice to have)
- [findings or "None"]

---
Would you like to:
1. Fix issues now (stay in REVIEW phase, re-run /review after fixing)
2. Proceed to /complete (acknowledge findings as-is)
```
```

- [ ] **Step 4: Fix BUG-2 — chain echo with && to prevent false success**

In the bash block at line 14-15 of review.md, change:

```bash
WF="${CLAUDE_PLUGIN_ROOT}/scripts/workflow-cmd.sh" && "$WF" set_phase "review" && "$WF" reset_review_status && "$WF" set_active_skill "review-pipeline"
echo "Phase set to REVIEW — running review pipeline."
```

To:

```bash
WF="${CLAUDE_PLUGIN_ROOT}/scripts/workflow-cmd.sh" && "$WF" set_phase "review" && "$WF" reset_review_status && "$WF" set_active_skill "review-pipeline" && echo "Phase set to REVIEW — running review pipeline."
```

- [ ] **Step 5: Verify the updated review.md is syntactically correct**

Run: `wc -l plugin/commands/review.md`
Expected: Approximately 90-110 lines (shorter than current 127 because inline prompts are removed).

- [ ] **Step 6: Commit**

```bash
git add plugin/commands/review.md
git commit -m "feat: update review.md to dispatch 4 named agents including governance reviewer

Replaces inline agent prompts with references to plugin/agents/*.md files.
Adds governance-reviewer as 4th parallel review agent.
Fixes BUG-2: chains echo with && to prevent false success on phase transition failure."
```

---

### Task 8: Run full test suite and verify

- [ ] **Step 1: Run full test suite**

Run: `bash tests/run-tests.sh 2>&1`
Expected: All tests pass. Zero failures. New agent definition tests pass.

- [ ] **Step 2: Verify agent files are discoverable**

Run: `ls -la plugin/agents/`
Expected: 5 `.md` files:
```
code-quality-reviewer.md
security-reviewer.md
architecture-reviewer.md
governance-reviewer.md
review-verifier.md
```

- [ ] **Step 3: Verify review.md references match agent file names**

Run: `grep "workflow-manager:" plugin/commands/review.md`
Expected: 5 matches:
```
workflow-manager:code-quality-reviewer
workflow-manager:security-reviewer
workflow-manager:architecture-reviewer
workflow-manager:governance-reviewer
workflow-manager:review-verifier
```

- [ ] **Step 4: Verify no remaining inline prompts in review.md**

Run: `grep -c "Check for:" plugin/commands/review.md`
Expected: 0 (all check instructions are now in agent files, not review.md)
