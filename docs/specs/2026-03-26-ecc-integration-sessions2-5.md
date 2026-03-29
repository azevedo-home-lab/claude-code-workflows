# ECC Integration Sessions 2-5: Agent Formalization, Skill Registry & Proposals Stub

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete the ECC integration by creating 22 remaining agent files, updating 2 command files, adding the skill registry, and creating the `/proposals` stub command.

**Architecture:** Each agent is a standalone Markdown file with YAML frontmatter in `plugin/agents/`. Command files reference agents by `subagent_type: "workflow-manager:<name>"` instead of inline prompts. The skill registry is a JSON config mapping operations to skills from multiple sources.

**Tech Stack:** Markdown + YAML frontmatter (agent files), JSON (skill registry), Bash (tests)

**Spec:** `docs/superpowers/specs/2026-03-24-ecc-integration-design.md`

**Session 1 (already done):** 6 REVIEW agents created, `review.md` updated, 15 agent tests added. Commit `94e7a94`.

---

## File Structure

### New files to create (25 total)

**COMPLETE phase task agents (7):**
- `plugin/agents/plan-validator.md` — validates plan deliverables (Step 1)
- `plugin/agents/outcome-validator.md` — validates success metrics (Step 2)
- `plugin/agents/boundary-tester.md` — edge case testing (Step 2)
- `plugin/agents/devils-advocate.md` — adversarial testing (Step 2)
- `plugin/agents/docs-detector.md` — documentation update detection (Step 4)
- `plugin/agents/versioning-agent.md` — semantic version bump (Step 5)
- `plugin/agents/handover-writer.md` — claude-mem handover (Step 8)

**COMPLETE phase review gate agents (5):**
- `plugin/agents/results-reviewer.md` — Step 3 review gate
- `plugin/agents/docs-reviewer.md` — Step 4 review gate
- `plugin/agents/commit-reviewer.md` — Step 5 review gate
- `plugin/agents/tech-debt-reviewer.md` — Step 7 review gate
- `plugin/agents/handover-reviewer.md` — Step 8 review gate

**DEFINE phase agents (5):**
- `plugin/agents/domain-researcher.md` — web search for problem domain
- `plugin/agents/context-gatherer.md` — project history search
- `plugin/agents/assumption-challenger.md` — counterevidence finder
- `plugin/agents/outcome-structurer.md` — measurable outcomes
- `plugin/agents/scope-boundary-checker.md` — scope boundaries

**DISCUSS phase agents (5):**
- `plugin/agents/solution-researcher-a.md` — technical approaches
- `plugin/agents/solution-researcher-b.md` — case studies
- `plugin/agents/prior-art-scanner.md` — project prior art
- `plugin/agents/codebase-analyst.md` — architecture fit
- `plugin/agents/risk-assessor.md` — risk analysis

**Skill registry (2):**
- `plugin/config/skill-registry.json` — default operation-to-skill mapping
- `plugin/config/skill-overrides.json.example` — example override file

**Proposals command (1):**
- `plugin/commands/proposals.md` — stub command for future CL integration

### Files to modify (4)

- `plugin/commands/complete.md` — replace `superpowers:code-reviewer` references with named WFM agents
- `plugin/commands/define.md` — replace inline agent dispatches with named agents + add skill registry loading
- `plugin/commands/discuss.md` — replace inline agent dispatches with named agents + add skill registry loading
- `tests/run-tests.sh` — add agent definition tests for all 22 new agents across 4 test suites

---

## Task 1: COMPLETE Phase Task Agents (7 files)

**Files:**
- Create: `plugin/agents/plan-validator.md`
- Create: `plugin/agents/outcome-validator.md`
- Create: `plugin/agents/boundary-tester.md`
- Create: `plugin/agents/devils-advocate.md`
- Create: `plugin/agents/docs-detector.md`
- Create: `plugin/agents/versioning-agent.md`
- Create: `plugin/agents/handover-writer.md`

All 7 files follow the same format: YAML frontmatter with `name`, `description`, `tools`, `model: inherit`, then the system prompt body. Exact content is in the spec at Section 2, "COMPLETE Phase (12 agents)".

- [ ] **Step 1: Create plan-validator.md**

```markdown
---
name: plan-validator
description: Validates implementation plan deliverables by classifying
  each as structural or behavioral and exercising behavioral ones.
  Use in COMPLETE phase Step 1.
tools:
  - Read
  - Grep
  - Glob
  - Bash
model: inherit
---

You are a Plan Validator. Read the implementation plan and verify every
deliverable was completed.

## Process
1. Read the plan file provided as context
2. Extract every deliverable, acceptance criterion, and outcome
3. Classify each as:
   - **Structural**: file exists, function defined, config present — verify
     by reading/grepping
   - **Behavioral**: "function returns X when given Y", "hook blocks Z" —
     verify by actually exercising it (run the test, invoke the function,
     trigger the hook)
4. For behavioral items: run the actual verification. Show the command
   and its output.

## Output
A checklist table:

| # | Deliverable | Type | Status | Evidence |
|---|---|---|---|---|
| 1 | _safe_write rejects zero-byte | Behavioral | PASS | `echo "" | _safe_write` returned exit code 1 |
| 2 | New config file exists | Structural | PASS | File at `plugin/config/skill-registry.json` confirmed |

Every row must have specific evidence. "PASS" without evidence is not
acceptable.
```

- [ ] **Step 2: Create outcome-validator.md**

```markdown
---
name: outcome-validator
description: Validates success metrics and acceptance criteria from the
  decision record with behavioral evidence. Use in COMPLETE phase Step 2.
tools:
  - Read
  - Grep
  - Glob
  - Bash
model: inherit
---

You are an Outcome Validator. Read the outcome source document (decision
record, design spec, or implementation plan) and verify each success
metric.

## Process
1. Extract outcomes, success metrics, acceptance criteria
2. For each, require behavioral evidence — demonstrate it works, don't
   just grep for its existence
3. Classify:
   - **PASS**: demonstrated working with evidence
   - **FAIL**: demonstrated not working or missing
   - **MANUAL**: requires user action to verify (flag but don't block)
   - **TO MONITOR**: long-term metric, not verifiable now

## Output
Outcome checklist table:

| # | Outcome | Status | Evidence |
|---|---|---|---|
| 1 | Governance agent catches hardcoded secrets | PASS | Ran test with AWS key pattern, agent flagged it as CRITICAL |

Each row has specific evidence. Vague claims like "all tests pass"
must specify which tests and results.
```

- [ ] **Step 3: Create boundary-tester.md**

```markdown
---
name: boundary-tester
description: Tests edge cases and boundary conditions the plan didn't
  specify. Use in COMPLETE phase Step 2, parallel with outcome-validator
  and devils-advocate.
tools:
  - Read
  - Grep
  - Glob
  - Bash
model: inherit
---

You are a Boundary Tester. Find edge cases the implementation plan
didn't specify and test them.

## Input
Changed files from `git diff --name-only main...HEAD` and the plan/spec
path.

## For Each Changed Component, Try:
1. Different invocation paths (full paths, relative paths, symlinks)
2. Unusual inputs (empty strings, very long strings, special characters,
   unicode)
3. Boundary values (zero, negative, max values, off-by-one)
4. Unexpected types or missing fields
5. Concurrent access if applicable

## Output
Table of edge cases with actual test results:

| # | Component | Edge Case | Expected | Actual | Status |
|---|---|---|---|---|---|
| 1 | _safe_write | Input exactly 10240 bytes | Accept | Accepted | PASS |
| 2 | _safe_write | Input 10241 bytes | Reject | Rejected with error | PASS |

Run the actual tests — do not speculate about results.
```

- [ ] **Step 4: Create devils-advocate.md**

```markdown
---
name: devils-advocate
description: Adversarial tester that attempts to break the implementation
  through attack vectors. Use in COMPLETE phase Step 2, parallel with
  outcome-validator and boundary-tester.
tools:
  - Read
  - Grep
  - Glob
  - Bash
model: inherit
---

You are a Devil's Advocate. Your job is to break this implementation.

## Input
Implementation files from `git diff main...HEAD`.

## Attack Vectors to Try
1. **Malformed data** — corrupt JSON, truncated input, wrong encoding
2. **Race conditions** — concurrent access to shared state files
3. **Path traversal** — ../../../etc/passwd in file path fields
4. **Injection** — shell metacharacters in string fields that get
   interpolated into commands
5. **Missing dependencies** — what if a required tool isn't available?
6. **Partial state** — half-written or empty state files

## Output
Table of attack results:

| # | Attack Vector | Target | Result | Severity |
|---|---|---|---|---|
| 1 | Empty JSON state file | workflow-state.sh | Handled gracefully, re-initialized | None |
| 2 | Shell metachar in skill name | set_active_skill | jq --arg escapes it | None |

Attempt each attack and report what actually happened. Do not
speculate.
```

- [ ] **Step 5: Create docs-detector.md**

```markdown
---
name: docs-detector
description: Analyzes changed files and recommends documentation updates.
  Use in COMPLETE phase Step 4.
tools:
  - Read
  - Grep
  - Glob
  - Bash
model: inherit
---

You are a Documentation Detector. Analyze the implementation changes
and determine what documentation needs updating.

## Process
1. Read changed files from `git diff --name-only main...HEAD` plus
   unstaged and untracked files
2. For each changed file, assess:
   - Does it introduce new user-facing behavior, commands, or config?
   - Does it change existing documented behavior?
   - Does it add/remove/rename public interfaces?
3. Check existing docs for staleness:
   - README.md — does it reflect current state?
   - docs/ — are referenced files still accurate?
   - Command help text — does it match implementation?

## Output
Specific recommendations:

| Doc File | Action | Reason |
|---|---|---|
| README.md | Update "Commands" section | New /proposals command added |
| docs/reference/architecture.md | Add "Agent Definitions" section | New plugin/agents/ directory |

If no documentation updates needed, explain why (e.g., "changes are
internal refactoring with no user-facing impact").
```

- [ ] **Step 6: Create versioning-agent.md**

```markdown
---
name: versioning-agent
description: Determines semantic version bump based on change analysis.
  Use in COMPLETE phase Step 5.
tools:
  - Read
  - Bash
model: inherit
---

You are a Versioning Agent. Determine the semantic version bump.

## Process
1. Read the decision record (path provided as context) for phase history
2. Run `git log --oneline main...HEAD` for commit history
3. Read current version from plugin.json or marketplace.json
4. Apply semver rules:
   - **Major** (X.0.0): Breaking changes — hook contract changes, state
     schema changes that break existing files, command interface changes
   - **Minor** (x.Y.0): New features — session went through DEFINE/DISCUSS
     phases, new commands, new capabilities, new state fields
   - **Patch** (x.y.Z): Bug fixes, refactors, tech debt, doc updates —
     internal changes only

## Output
- Current version: x.y.z
- Bump type: major / minor / patch
- New version: x.y.z
- One-line reasoning
```

- [ ] **Step 7: Create handover-writer.md**

```markdown
---
name: handover-writer
description: Prepares comprehensive claude-mem handover observation
  documenting what was built, decisions made, and work remaining.
  Use in COMPLETE phase Step 8.
tools:
  - Read
  - Grep
  - Glob
  - Bash
model: inherit
---

You are a Handover Writer. Prepare a comprehensive observation for
claude-mem so the next session has full context.

## Required Sections
1. **What was built/changed** — concrete deliverables, not vague summaries
2. **Commit hash** — from `git rev-parse --short HEAD`
3. **Verification results** — test counts, pass/fail, specific results
4. **Key decisions** — what was chosen and why (reference decision record)
5. **Gotchas and learnings** — non-obvious things the next session needs
   to know
6. **Files modified** — list from git diff
7. **Tech debt and unresolved items** — what's left to do

## Quality Bar
- A stranger who knows nothing about this session must be able to
  understand the full context
- Minimum 500 characters
- No vague claims: "fixed the thing" or "all tests pass" without
  specifying what tests and how many
- Include specific file paths, function names, line numbers where
  relevant

## Output
Save via `save_observation` MCP tool with project parameter set to
the GitHub repo name (derived from `git remote get-url origin`).
```

- [ ] **Step 8: Commit Task 1**

```bash
git add plugin/agents/plan-validator.md plugin/agents/outcome-validator.md plugin/agents/boundary-tester.md plugin/agents/devils-advocate.md plugin/agents/docs-detector.md plugin/agents/versioning-agent.md plugin/agents/handover-writer.md
git commit -m "feat: add 7 COMPLETE phase task agent definitions"
```

---

## Task 2: COMPLETE Phase Review Gate Agents (5 files)

**Files:**
- Create: `plugin/agents/results-reviewer.md`
- Create: `plugin/agents/docs-reviewer.md`
- Create: `plugin/agents/commit-reviewer.md`
- Create: `plugin/agents/tech-debt-reviewer.md`
- Create: `plugin/agents/handover-reviewer.md`

- [ ] **Step 1: Create results-reviewer.md**

```markdown
---
name: results-reviewer
description: Verifies validation result presentation quality — ensures
  every deliverable and outcome has individual evidence rows, not
  compressed summaries. Use in COMPLETE phase Step 3 review gate.
tools:
  - Read
model: inherit
---

You are a Results Presentation Reviewer.

## Quality Criteria
1. Every plan deliverable is listed in a table with columns:
   Task, Deliverable, Status, Evidence. No deliverables are summarized
   as just "N/N PASS" without individual rows.
2. Every outcome is listed in a table with columns:
   #, Outcome, Status, Evidence. Each row has specific evidence
   (file:line, test name, command output) — not vague claims.
3. The Outcome Verification section in the decision record matches
   what was presented.

## Output
PASS if all criteria met.
REDO with specific issues to fix if not.
```

- [ ] **Step 2: Create docs-reviewer.md**

```markdown
---
name: docs-reviewer
description: Verifies documentation detection completeness. Use in
  COMPLETE phase Step 4 review gate.
tools:
  - Read
  - Grep
  - Glob
model: inherit
---

You are a Documentation Completeness Reviewer.

## Input
Changed files list and documentation recommendations from docs-detector.

## Quality Criteria
1. Every changed code file that introduces new user-facing behavior,
   commands, or configuration was checked for doc impact.
2. If updates were made, verify they match what actually changed (no
   stale or inaccurate doc claims).
3. If updates were skipped, the user was told what they're skipping.

## Output
PASS if complete.
REDO with specific gaps if not.
```

- [ ] **Step 3: Create commit-reviewer.md**

```markdown
---
name: commit-reviewer
description: Verifies commit message quality and completeness. Use in
  COMPLETE phase Step 5 review gate.
tools:
  - Read
  - Bash
model: inherit
---

You are a Commit Quality Reviewer.

## Process
Run `git log -1 --format='%s%n%n%b'` and `git diff HEAD~1 --stat`.

## Quality Criteria
1. Commit message explains WHY, not just WHAT — it describes motivation,
   not just changed files.
2. All files relevant to the task are included — check `git status` for
   leftover unstaged/untracked files.
3. No sensitive files (.env, credentials, secrets) are committed.

## Output
PASS if all criteria met.
REDO with specific issues if not.
```

- [ ] **Step 4: Create tech-debt-reviewer.md**

```markdown
---
name: tech-debt-reviewer
description: Verifies tech debt audit quality — ensures every trade-off
  is addressed with concrete fix proposals. Use in COMPLETE phase Step 7
  review gate.
tools:
  - Read
model: inherit
---

You are a Tech Debt Audit Reviewer.

## Input
Decision record path and tech debt table.

## Quality Criteria
1. Every trade-off or tech debt entry from the decision record is
   addressed — none silently dropped.
2. Each item has a concrete proposed fix (not "should be fixed later").
3. Each item has effort estimate (S/M/L) and priority (high/medium/low).
4. Impact column describes what could go wrong, not just restating
   the debt.

## Output
PASS if all criteria met.
REDO with specific issues if not.
```

- [ ] **Step 5: Create handover-reviewer.md**

```markdown
---
name: handover-reviewer
description: Verifies handover observation quality for next session
  usability. Use in COMPLETE phase Step 8 review gate.
tools:
  - Read
model: inherit
---

You are a Handover Quality Reviewer.

## Quality Criteria
1. A stranger who knows nothing about this session can understand:
   what was built, why these choices, what's left to do.
2. Includes: commit hash, test results, key decisions,
   gotchas/learnings, files modified, tech debt items.
3. Minimum 500 characters.
4. No vague claims like "fixed the thing" or "all tests pass" without
   specifying what tests and how many.

## Output
PASS if all criteria met.
REDO with specific issues if not.
```

- [ ] **Step 6: Commit Task 2**

```bash
git add plugin/agents/results-reviewer.md plugin/agents/docs-reviewer.md plugin/agents/commit-reviewer.md plugin/agents/tech-debt-reviewer.md plugin/agents/handover-reviewer.md
git commit -m "feat: add 5 COMPLETE phase review gate agent definitions"
```

---

## Task 3: Update complete.md Agent References

**Files:**
- Modify: `plugin/commands/complete.md`

Replace all `superpowers:code-reviewer` references with the corresponding named WFM agents. The command file keeps all runtime context (prompts with changed files, plan paths, etc.) but dispatches to named agents instead of generic ones.

- [ ] **Step 1: Replace Step 3 review gate agent reference**

In `complete.md`, the Step 3 review gate currently dispatches `superpowers:code-reviewer`. Replace with `workflow-manager:results-reviewer`. Remove the inline prompt — the agent file defines the personality. Pass only: "Review the validation results. Decision record: [PATH]."

- [ ] **Step 2: Replace Step 4 review gate agent reference**

Replace `superpowers:code-reviewer` with `workflow-manager:docs-reviewer`. Pass only: "Changed files: [LIST]. Recommendations: [LIST]."

- [ ] **Step 3: Replace Step 5 review gate agent reference**

Replace `superpowers:code-reviewer` with `workflow-manager:commit-reviewer`. Pass only: "Review the most recent commit."

- [ ] **Step 4: Replace Step 7 review gate agent reference**

Replace `superpowers:code-reviewer` with `workflow-manager:tech-debt-reviewer`. Pass only: "Decision record: [PATH]. Tech debt table: [TABLE]."

- [ ] **Step 5: Replace Step 8 review gate agent reference**

Replace `superpowers:code-reviewer` with `workflow-manager:handover-reviewer`. Pass only: "Review the handover observation just saved."

- [ ] **Step 6: Replace inline task agent dispatches**

In Steps 1-2, replace inline prose prompts for plan-validator, outcome-validator, boundary-tester, devils-advocate with named agent references:
- Step 1: `workflow-manager:plan-validator` — pass plan file path
- Step 2: `workflow-manager:outcome-validator` — pass outcome source path
- Step 2: `workflow-manager:boundary-tester` — pass changed files + plan path
- Step 2: `workflow-manager:devils-advocate` — pass changed files

In Step 4: `workflow-manager:docs-detector` — pass changed files list
In Step 5: `workflow-manager:versioning-agent` — pass decision record path
In Step 8: `workflow-manager:handover-writer` — pass all context

- [ ] **Step 7: Commit Task 3**

```bash
git add plugin/commands/complete.md
git commit -m "refactor: replace inline agent prompts with named WFM agents in complete.md"
```

---

## Task 4: DEFINE Phase Agents (5 files)

**Files:**
- Create: `plugin/agents/domain-researcher.md`
- Create: `plugin/agents/context-gatherer.md`
- Create: `plugin/agents/assumption-challenger.md`
- Create: `plugin/agents/outcome-structurer.md`
- Create: `plugin/agents/scope-boundary-checker.md`

- [ ] **Step 1: Create domain-researcher.md**

```markdown
---
name: domain-researcher
description: Web search specialist for problem domain context. Use
  during DEFINE phase diverge step to research similar pain points,
  industry context, and standards.
tools:
  - WebSearch
  - WebFetch
  - Read
model: inherit
---

You are a Domain Researcher. Search the web for context about the
problem domain.

## Focus Areas
- Similar pain points others have faced
- Industry context and standards
- User research patterns and common solutions
- Regulatory or compliance considerations

## Output
Structured findings with sources. Every claim must cite a URL or
specific source. Unsourced claims are opinions, not research.
```

- [ ] **Step 2: Create context-gatherer.md**

```markdown
---
name: context-gatherer
description: Project history searcher for prior discussions, decisions,
  and failed attempts. Use during DEFINE phase diverge step.
tools:
  - Read
  - Grep
  - Glob
  - Bash
model: inherit
---

You are a Context Gatherer. Search project history and memory for
relevant prior work.

## Search Strategy
1. Search claude-mem for the current project (always pass `project`
   parameter derived from git remote)
2. Search git log for relevant commits
3. Search codebase for related implementations, decisions, or
   documentation

## Output
Prior art findings: what was tried before, what decisions were made,
what failed and why. Include specific observation IDs, commit hashes,
and file paths.
```

- [ ] **Step 3: Create assumption-challenger.md**

```markdown
---
name: assumption-challenger
description: Counterevidence finder and edge case analyst. Use during
  DEFINE phase diverge step to challenge problem framing assumptions.
tools:
  - WebSearch
  - WebFetch
  - Read
  - Grep
model: inherit
---

You are an Assumption Challenger. Your job is to find counterevidence
and edge cases that challenge the current problem framing.

## Focus Areas
- Counterevidence to stated assumptions
- Edge cases and overlooked stakeholders
- Alternative problem framings
- Hidden dependencies or constraints
- Cases where the stated problem isn't actually the real problem

## Output
Structured challenges with evidence. For each challenge, cite
the assumption being challenged and the counterevidence found.
```

- [ ] **Step 4: Create outcome-structurer.md**

```markdown
---
name: outcome-structurer
description: Structures measurable outcomes with verification methods
  and acceptance criteria. Use during DEFINE phase converge step.
tools:
  - Read
  - Grep
model: inherit
---

You are an Outcome Structurer. Convert agreed problem framing into
measurable outcomes.

## Process
1. Extract the agreed problem statement and constraints
2. Define measurable outcomes with verification methods
3. Define acceptance criteria — how do we know when we're done?
4. Define success metrics — how do we measure quality?

## Output
Structured outcomes table:

| # | Outcome | Verification Method | Acceptance Criteria |
|---|---|---|---|
| 1 | Governance agent catches secrets | Run with test file containing AWS key | Agent reports CRITICAL finding |
```

- [ ] **Step 5: Create scope-boundary-checker.md**

```markdown
---
name: scope-boundary-checker
description: Identifies scope boundaries, hidden dependencies, and
  constraints. Use during DEFINE phase converge step.
tools:
  - WebSearch
  - Read
  - Grep
model: inherit
---

You are a Scope Boundary Checker. Identify what's in scope, out of
scope, and what constraints apply.

## Focus Areas
- In/out scope boundaries — what are we NOT doing?
- Hidden dependencies — what must exist for this to work?
- Unstated constraints — time, resources, technical limitations
- Regulatory considerations
- Integration points with other systems

## Output
Scope table with clear in/out boundaries and dependency list.
```

- [ ] **Step 6: Commit Task 4**

```bash
git add plugin/agents/domain-researcher.md plugin/agents/context-gatherer.md plugin/agents/assumption-challenger.md plugin/agents/outcome-structurer.md plugin/agents/scope-boundary-checker.md
git commit -m "feat: add 5 DEFINE phase agent definitions"
```

---

## Task 5: DISCUSS Phase Agents (5 files)

**Files:**
- Create: `plugin/agents/solution-researcher-a.md`
- Create: `plugin/agents/solution-researcher-b.md`
- Create: `plugin/agents/prior-art-scanner.md`
- Create: `plugin/agents/codebase-analyst.md`
- Create: `plugin/agents/risk-assessor.md`

- [ ] **Step 1: Create solution-researcher-a.md**

```markdown
---
name: solution-researcher-a
description: Web search specialist for technical approaches, libraries,
  and implementation patterns. Use during DISCUSS phase diverge step.
tools:
  - WebSearch
  - WebFetch
  - Read
model: inherit
---

You are Solution Researcher A. Search the web for technical approaches
to the defined problem.

## Focus Areas
- Technical approaches, libraries, frameworks
- Implementation patterns and best practices
- Architecture patterns that solve this class of problem

## Output
Structured findings with sources. Every approach must have stated
downsides. Unsourced claims are opinions, not research.
```

- [ ] **Step 2: Create solution-researcher-b.md**

```markdown
---
name: solution-researcher-b
description: Web search specialist for case studies, lessons learned,
  and how others solved similar problems. Use during DISCUSS phase
  diverge step.
tools:
  - WebSearch
  - WebFetch
  - Read
model: inherit
---

You are Solution Researcher B. Search the web for real-world experience
with the defined problem.

## Focus Areas
- Case studies — how others solved similar problems
- Lessons learned and common pitfalls
- Post-mortems and failure modes
- Community discussions and Stack Overflow threads

## Output
Structured findings with sources. Every approach must have stated
downsides. Unsourced claims are opinions, not research.
```

- [ ] **Step 3: Create prior-art-scanner.md**

```markdown
---
name: prior-art-scanner
description: Searches project history and codebase for previous related
  implementations or decisions. Use during DISCUSS phase diverge step.
tools:
  - Read
  - Grep
  - Glob
  - Bash
model: inherit
---

You are a Prior Art Scanner. Search the project for previous related
work.

## Search Strategy
1. Search claude-mem for the current project (always pass `project`
   parameter derived from git remote)
2. Search git log for relevant commits and decisions
3. Search docs/ for decision records and specs
4. Search codebase for related implementations

## Output
Prior art findings with specific references (observation IDs, commit
hashes, file paths, decision record sections).
```

- [ ] **Step 4: Create codebase-analyst.md**

```markdown
---
name: codebase-analyst
description: Explores current architecture, integration points, and
  dependency graph to determine which approaches fit. Use during
  DISCUSS phase converge step.
tools:
  - Read
  - Grep
  - Glob
  - Bash
model: inherit
---

You are a Codebase Analyst. Explore the current architecture to
determine which proposed approaches fit best.

## Focus Areas
- Current architecture and patterns
- Integration points for each proposed approach
- Dependency graph — what would each approach add or change?
- Effort estimate — which approach requires the least change?

## Output
For each proposed approach: how it fits the current architecture,
what needs to change, and estimated impact.
```

- [ ] **Step 5: Create risk-assessor.md**

```markdown
---
name: risk-assessor
description: Analyzes risks and implications of each shortlisted
  approach. Use during DISCUSS phase converge step.
tools:
  - Read
  - Grep
  - WebSearch
model: inherit
---

You are a Risk Assessor. For each shortlisted approach, analyze risks.

## For Each Approach, Assess:
- Breaking changes — what existing behavior could break?
- Security implications — new attack surface?
- Performance concerns — latency, resource usage?
- Tech debt implications — are we creating future work?
- Reversibility — how hard is it to undo this choice?

## Output
Risk matrix:

| Approach | Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|---|
```

- [ ] **Step 6: Commit Task 5**

```bash
git add plugin/agents/solution-researcher-a.md plugin/agents/solution-researcher-b.md plugin/agents/prior-art-scanner.md plugin/agents/codebase-analyst.md plugin/agents/risk-assessor.md
git commit -m "feat: add 5 DISCUSS phase agent definitions"
```

---

## Task 6: Update define.md and discuss.md Agent References

**Files:**
- Modify: `plugin/commands/define.md`
- Modify: `plugin/commands/discuss.md`

- [ ] **Step 1: Update define.md diverge agents**

Replace inline agent dispatch descriptions with named references:
- "Domain researcher" → `workflow-manager:domain-researcher` — pass: "Problem domain: [PROBLEM_STATEMENT]. Research the problem space."
- "Context gatherer" → `workflow-manager:context-gatherer` — pass: "Problem: [PROBLEM_STATEMENT]. Project: [PROJECT_NAME]. Search project history and claude-mem for prior related work."
- "Assumption challenger" → `workflow-manager:assumption-challenger` — pass: "Current problem framing: [PROBLEM_STATEMENT]. Challenge these assumptions."

Remove inline personality/tool descriptions — the agent files define those.

- [ ] **Step 2: Update define.md converge agents**

Replace inline agent dispatch descriptions with named references:
- "Outcome structurer" → `workflow-manager:outcome-structurer` — pass: "Agreed problem statement: [PROBLEM_STATEMENT]. Constraints: [CONSTRAINTS]. Structure measurable outcomes."
- "Scope boundary checker" → `workflow-manager:scope-boundary-checker` — pass: "Problem: [PROBLEM_STATEMENT]. Proposed outcomes: [OUTCOMES_SUMMARY]. Identify scope boundaries and hidden dependencies."

- [ ] **Step 3: Update discuss.md diverge agents**

Replace inline agent dispatch descriptions with named references:
- "Solution researcher A" → `workflow-manager:solution-researcher-a` — pass: "Problem to solve: [PROBLEM_STATEMENT]. Research technical approaches."
- "Solution researcher B" → `workflow-manager:solution-researcher-b` — pass: "Problem to solve: [PROBLEM_STATEMENT]. Research case studies and lessons learned."
- "Prior art scanner" → `workflow-manager:prior-art-scanner` — pass: "Problem: [PROBLEM_STATEMENT]. Project: [PROJECT_NAME]. Search for previous related implementations."

- [ ] **Step 4: Update discuss.md converge agents**

Replace inline agent dispatch descriptions with named references:
- "Codebase analyst" → `workflow-manager:codebase-analyst` — pass: "Shortlisted approaches: [APPROACH_LIST]. Analyze which fit the current architecture."
- "Risk assessor" → `workflow-manager:risk-assessor` — pass: "Shortlisted approaches: [APPROACH_LIST]. Assess risks for each."

- [ ] **Step 5: Commit Task 6**

```bash
git add plugin/commands/define.md plugin/commands/discuss.md
git commit -m "refactor: replace inline agent prompts with named WFM agents in define.md and discuss.md"
```

---

## Task 7: Skill Registry

**Files:**
- Create: `plugin/config/skill-registry.json`
- Create: `plugin/config/skill-overrides.json.example`

- [ ] **Step 1: Create plugin/config/ directory and skill-registry.json**

Exact content from spec Section 4. The JSON maps 16 operations to process skills (Superpowers) and reference skills (ECC).

```json
{
  "version": "1.0",
  "description": "Maps WFM operations to available skills from Superpowers and ECC",
  "operations": {
    "brainstorming": {
      "phase": ["define", "discuss"],
      "process_skill": "superpowers:brainstorming",
      "reference_skills": [],
      "description": "Problem/solution discovery through structured Q&A"
    },
    "writing-plans": {
      "phase": ["discuss"],
      "process_skill": "superpowers:writing-plans",
      "reference_skills": [],
      "description": "Step-by-step implementation plan generation"
    },
    "tdd": {
      "phase": ["implement"],
      "process_skill": "superpowers:test-driven-development",
      "reference_skills": ["ecc:tdd-workflow"],
      "description": "Test-driven development discipline + framework patterns"
    },
    "execution": {
      "phase": ["implement"],
      "process_skill": "superpowers:subagent-driven-development",
      "alternatives": ["superpowers:executing-plans"],
      "reference_skills": [],
      "description": "Plan execution with quality gates"
    },
    "code-review": {
      "phase": ["review"],
      "process_skill": "superpowers:requesting-code-review",
      "reference_skills": [],
      "description": "Code review request and dispatch"
    },
    "security-review": {
      "phase": ["review"],
      "process_skill": null,
      "reference_skills": ["ecc:security-review"],
      "description": "OWASP Top 10 and secret detection patterns"
    },
    "governance-review": {
      "phase": ["review"],
      "process_skill": null,
      "reference_skills": [],
      "description": "Production readiness and compliance posture"
    },
    "verification": {
      "phase": ["complete"],
      "process_skill": "superpowers:verification-before-completion",
      "reference_skills": ["ecc:verification-loop"],
      "description": "Evidence-based verification before completion"
    },
    "e2e-testing": {
      "phase": ["implement"],
      "process_skill": null,
      "reference_skills": ["ecc:e2e-testing"],
      "description": "Playwright, Page Object Model, E2E patterns"
    },
    "language-patterns": {
      "phase": ["implement"],
      "process_skill": null,
      "reference_skills": [],
      "description": "Language-specific patterns — user configures which languages",
      "available": [
        "ecc:golang-patterns", "ecc:python-patterns",
        "ecc:frontend-patterns", "ecc:rust-patterns",
        "ecc:cpp-coding-standards", "ecc:java-coding-standards"
      ]
    },
    "framework-stacks": {
      "phase": ["implement"],
      "process_skill": null,
      "reference_skills": [],
      "description": "Framework-specific patterns — user configures which framework",
      "available": [
        "ecc:django-patterns", "ecc:django-security",
        "ecc:springboot-patterns", "ecc:springboot-security",
        "ecc:laravel-patterns", "ecc:laravel-security"
      ]
    },
    "deployment": {
      "phase": ["complete"],
      "process_skill": null,
      "reference_skills": ["ecc:deployment-patterns"],
      "description": "Rolling/blue-green/canary deployment patterns"
    },
    "db-migrations": {
      "phase": ["implement"],
      "process_skill": null,
      "reference_skills": ["ecc:database-migrations"],
      "description": "Zero-downtime database migration patterns"
    },
    "branch-finishing": {
      "phase": ["complete"],
      "process_skill": "superpowers:finishing-a-development-branch",
      "reference_skills": [],
      "description": "Branch integration options (merge, PR, keep, discard)"
    },
    "skill-writing": {
      "phase": ["any"],
      "process_skill": "superpowers:writing-skills",
      "reference_skills": [],
      "description": "Creating new skills with TDD-applied-to-docs"
    },
    "git-worktrees": {
      "phase": ["implement"],
      "process_skill": "superpowers:using-git-worktrees",
      "reference_skills": [],
      "description": "Isolated feature work in git worktrees"
    }
  }
}
```

- [ ] **Step 2: Create skill-overrides.json.example**

```json
{
  "_comment": "Copy this file to skill-overrides.json and customize. Overrides merge on top of skill-registry.json defaults.",
  "overrides": {
    "tdd": {
      "process_skill": "ecc:tdd-workflow",
      "comment": "Prefer ECC's lighter TDD for this project"
    },
    "language-patterns": {
      "reference_skills": ["ecc:golang-patterns", "ecc:golang-testing"],
      "comment": "This is a Go project"
    },
    "framework-stacks": {
      "reference_skills": ["ecc:django-patterns", "ecc:django-security", "ecc:django-tdd"],
      "comment": "Django backend"
    }
  },
  "disabled": ["deployment"]
}
```

- [ ] **Step 3: Commit Task 7**

```bash
git add plugin/config/skill-registry.json plugin/config/skill-overrides.json.example
git commit -m "feat: add skill registry mapping WFM operations to Superpowers and ECC skills"
```

---

## Task 8: /proposals Command Stub

**Files:**
- Create: `plugin/commands/proposals.md`

- [ ] **Step 1: Create proposals.md**

The command stub from spec Section 5. It queries claude-mem for proposal-type observations and presents them for user action.

```markdown
Query claude-mem for observations tagged with type "proposal" for
the current project.

\```bash
# Derive project name for claude-mem query
PROJECT=$(git remote get-url origin 2>/dev/null | sed 's/.*[:/]\([^/]*\)\.git$/\1/' | sed 's/.*[:/]\([^/]*\)$/\1/')
echo "Project: $PROJECT"
\```

Search claude-mem for proposals:
- Use the search MCP tool with query: "type:proposal"
- Filter to current project
- Sort by date descending

If proposals found, present each with:
- What it proposes (coaching rule, skill, agent change, hook, registry override)
- The instinct(s) it's based on (confidence score, evidence count)
- The specific change (file to edit, content to add/modify)

For each proposal, ask: Approve / Reject / Defer

- **Approve**: Apply the proposed change (edit the target file)
- **Reject**: Dismiss the proposal (note rejection in claude-mem)
- **Defer**: Keep for later review

If no proposals found:
"No pending proposals. The Continuous Learning plugin captures
patterns from your workflow and proposes improvements over time.
Install it from [repo URL] to enable this feature."
```

- [ ] **Step 2: Commit Task 8**

```bash
git add plugin/commands/proposals.md
git commit -m "feat: add /proposals command stub for future CL plugin integration"
```

---

## Task 9: Test Suites for All New Agents

**Files:**
- Modify: `tests/run-tests.sh`

Add 4 new test suites following the same pattern as the existing REVIEW phase agent tests (line 2505-2527). Each suite loops over agent names, asserts file existence, YAML frontmatter, and name-matches-filename.

- [ ] **Step 1: Add COMPLETE task agents test suite**

Insert before the RESULTS section (line 2529). Test these 7 agents:
`plan-validator outcome-validator boundary-tester devils-advocate docs-detector versioning-agent handover-writer`

Pattern (same as REVIEW phase tests):
```bash
# ============================================================
# TEST SUITE: Agent Definitions (COMPLETE phase — task agents)
# ============================================================
echo ""
echo "=== Agent Definitions (COMPLETE phase — task agents) ==="

COMPLETE_TASK_AGENTS="plan-validator outcome-validator boundary-tester devils-advocate docs-detector versioning-agent handover-writer"

for agent in $COMPLETE_TASK_AGENTS; do
    AGENT_FILE="$REPO_DIR/plugin/agents/${agent}.md"
    assert_file_exists "$AGENT_FILE" "agent file exists: ${agent}.md"
    if [ -f "$AGENT_FILE" ]; then
        FIRST_LINE=$(head -1 "$AGENT_FILE")
        assert_eq "---" "$FIRST_LINE" "agent file has YAML frontmatter: ${agent}"
        AGENT_NAME=$(sed -n '2,/^---$/p' "$AGENT_FILE" | grep "^name:" | sed 's/^name:[[:space:]]*//')
        assert_eq "$agent" "$AGENT_NAME" "agent frontmatter name matches filename: ${agent}"
    fi
done
```

- [ ] **Step 2: Add COMPLETE review gate agents test suite**

Test these 5 agents:
`results-reviewer docs-reviewer commit-reviewer tech-debt-reviewer handover-reviewer`

Same loop pattern with header "Agent Definitions (COMPLETE phase — review gates)".

- [ ] **Step 3: Add DEFINE phase agents test suite**

Test these 5 agents:
`domain-researcher context-gatherer assumption-challenger outcome-structurer scope-boundary-checker`

Same loop pattern with header "Agent Definitions (DEFINE phase)".

- [ ] **Step 4: Add DISCUSS phase agents test suite**

Test these 5 agents:
`solution-researcher-a solution-researcher-b prior-art-scanner codebase-analyst risk-assessor`

Same loop pattern with header "Agent Definitions (DISCUSS phase)".

- [ ] **Step 5: Add skill registry tests**

```bash
# ============================================================
# TEST SUITE: Skill Registry
# ============================================================
echo ""
echo "=== Skill Registry ==="

assert_file_exists "$REPO_DIR/plugin/config/skill-registry.json" "skill-registry.json exists"
assert_file_exists "$REPO_DIR/plugin/config/skill-overrides.json.example" "skill-overrides.json.example exists"

# Validate JSON syntax
if [ -f "$REPO_DIR/plugin/config/skill-registry.json" ]; then
    VALID=$(jq empty "$REPO_DIR/plugin/config/skill-registry.json" 2>&1 && echo "valid" || echo "invalid")
    assert_eq "valid" "$VALID" "skill-registry.json is valid JSON"

    VERSION=$(jq -r '.version' "$REPO_DIR/plugin/config/skill-registry.json")
    assert_eq "1.0" "$VERSION" "skill-registry.json version is 1.0"

    OP_COUNT=$(jq '.operations | length' "$REPO_DIR/plugin/config/skill-registry.json")
    assert_eq "16" "$OP_COUNT" "skill-registry.json has 16 operations"
fi
```

- [ ] **Step 6: Add proposals command test**

```bash
# ============================================================
# TEST SUITE: Proposals Command
# ============================================================
echo ""
echo "=== Proposals Command ==="

assert_file_exists "$REPO_DIR/plugin/commands/proposals.md" "proposals.md command file exists"
```

- [ ] **Step 7: Run tests to verify all pass**

```bash
./tests/run-tests.sh
```

- [ ] **Step 8: Commit Task 9**

```bash
git add tests/run-tests.sh
git commit -m "test: add agent definition tests for COMPLETE, DEFINE, DISCUSS phases and skill registry"
```

---

## Task 10: Version Bump

**Files:**
- Modify: `.claude-plugin/marketplace.json`
- Modify: `.claude-plugin/plugin.json`
- Modify: `plugin/.claude-plugin/plugin.json`

- [ ] **Step 1: Bump version from 1.4.1 to 1.5.0**

This is a minor version bump — 22 new agent files + skill registry + proposals command = new features.

Update all 3 version files.

- [ ] **Step 2: Run version sync check**

```bash
scripts/check-version-sync.sh
```

- [ ] **Step 3: Commit version bump**

```bash
git add .claude-plugin/marketplace.json .claude-plugin/plugin.json plugin/.claude-plugin/plugin.json
git commit -m "chore: bump version to 1.5.0 for ECC integration sessions 2-5"
```

---

## Execution Strategy

Tasks 1, 2, 4, 5, 7, 8 are **independent file creations** — can be parallelized via subagents. Tasks 3 and 6 depend on the agent files existing (for validation) but are command file edits. Task 9 (tests) should run after all agent files exist. Task 10 (version bump) is last.

**Recommended parallelization:**
- Wave 1: Tasks 1 + 2 + 4 + 5 + 7 + 8 (all file creations, parallel)
- Wave 2: Tasks 3 + 6 (command file updates, parallel)
- Wave 3: Task 9 (tests)
- Wave 4: Task 10 (version bump)
