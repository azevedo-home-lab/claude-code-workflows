# Design Spec: Workflow Manager Rework

**Date:** 2026-03-20
**Status:** Draft
**Scope:** Major rework of ClaudeWorkflows phase model, agent pipelines, coaching system, and documentation artifacts

---

## 1. Phase Model & Transitions

### 6 Phases, 5 Commands

| Phase | Command | Purpose | Edit Policy |
|-------|---------|---------|-------------|
| OFF | — | No enforcement, normal Claude Code | All allowed |
| DEFINE | `/define` | Frame the problem, define measurable outcomes | Blocked (state/plans only) |
| DISCUSS | `/discuss` | Research solutions, choose approach, write plan | Blocked (state/plans/specs only) |
| IMPLEMENT | `/implement` | Build the chosen solution with TDD | All allowed |
| REVIEW | `/review` | Multi-agent code review & validation | All allowed |
| COMPLETE | `/complete` | Verify outcomes, update docs, hand over | Code blocked; `docs/` + root `*.md` allowed |

### Transition Rules

Every `/phase` command is a **direct jump** from any phase. No `/override` command. No `/approve` command. DEFINE is optional — `/discuss` from OFF works.

**Recommended happy path:**

```
OFF → DEFINE → DISCUSS → IMPLEMENT → REVIEW → COMPLETE → OFF
```

> **Note:** This is the recommended path. Any `/phase` command can jump directly to any phase. Soft gates warn when skipping recommended steps. OFF is reached only through COMPLETE's pipeline (Step 8: phase transition to OFF). There is no `/off` command — to disable enforcement without completing, use `/define` or `/discuss` and then close the session.

**Soft gates** (warn but never block):

| Transition | Condition checked | Warning message |
|------------|-------------------|-----------------|
| → IMPLEMENT | No plan file found | "No plan exists. The workflow recommends `/discuss` first. Proceed without a plan?" |
| → REVIEW | No code changes detected (clean diff) | "No code changes detected. The review pipeline requires changed files to analyze. Proceed anyway?" |
| → COMPLETE | Review not completed | "Review hasn't been run. The workflow should be followed for best results. Proceed anyway?" |
| → DEFINE | — | No gate |
| → DISCUSS | — | No gate |

### Edit-Blocking Whitelist Tiers

| Tier | Phases | Allowed writes |
|------|--------|----------------|
| Restrictive | DEFINE, DISCUSS | `.claude/state/`, `docs/superpowers/specs/`, `docs/superpowers/plans/`, `docs/plans/` |
| Docs-allowed | COMPLETE | `.claude/state/`, `docs/` (all), `*.md` at project root |
| Open | IMPLEMENT, REVIEW | Everything |

**Security:** `.claude/hooks/` is removed from all whitelists. The enforcement mechanism must not be editable by the thing it constrains.

### State Management

Single state file: `.claude/state/workflow.json`

```json
{
  "phase": "review",
  "message_shown": false,
  "active_skill": "review-pipeline",
  "decision_record": "docs/plans/2026-03-20-workflow-rework-decisions.md",
  "review": {
    "verification_complete": true,
    "agents_dispatched": false,
    "findings_presented": false,
    "findings_acknowledged": false
  },
  "coaching": {
    "tool_calls_since_agent": 0,
    "layer2_fired": []
  },
  "updated": "2026-03-20T08:35:00Z"
}
```

- Replaces three separate files: `phase.json`, `active-skill.json`, `review-status.json`
- The `review` sub-object exists only during REVIEW phase; cleaned up on phase exit
- The `coaching` sub-object tracks state for Layer 2/3 coaching triggers (tool call counts, cooldown)
- `active_skill` replaces the separate `active-skill.json`
- `decision_record` tracks the current cycle's decision record path; set by `/define` or `/discuss`, consumed by `/review` and `/complete`
- The `workflow-state.sh` API (`get_phase`, `set_phase`, etc.) stays the same — callers use functions, not direct file access
- New API functions: `set_active_skill(name)` and `get_active_skill()` to manage the `active_skill` field. Each command file calls `set_active_skill` when invoking a superpowers skill.
- New API function: `set_decision_record(path)` and `get_decision_record()` to track the current cycle's decision record path. Set by `/define` or `/discuss` when the record is created, read by `/review` and `/complete` to know which file to update.
- New API functions: `check_soft_gate(target_phase)` returns a warning message if preconditions for the target phase are not met, or empty string if no warning. Used by command files to implement soft gates.
- Valid phases: `off`, `define`, `discuss`, `implement`, `review`, `complete`

### Statusline

Update `statusline/statusline.sh`:
- Add COMPLETE phase display with magenta color
- Read `active_skill` from `workflow.json` instead of the deleted `active-skill.json`
- Read `phase` from `workflow.json` instead of `phase.json`

---

## 2. Artifacts & Documentation

### Artifact 1: Decision Record (per task cycle)

**File:** `docs/plans/YYYY-MM-DD-<topic>-decisions.md`

Created in whichever phase starts the cycle (DEFINE or DISCUSS). Enriched by every subsequent phase. This is the E2E traceability document.

```markdown
# Decision Record: <topic>

## Problem (DEFINE phase)
- Problem statement
- Who is affected and why it matters now
- Current state / workarounds
- Measurable outcomes with verification methods
- Success metrics with targets
- Scope: in / out / constraints

## Approaches Considered (DISCUSS phase — diverge)
### Approach A: <name>
- Description
- Pros / cons
- Source: where this was found (web link, prior art, agent research)

### Approach B: <name>
- Description
- Pros / cons
- Source

### Approach C: <name>
- Description
- Pros / cons
- Source

## Decision (DISCUSS phase — converge)
- **Chosen approach:** <which and why>
- **Rationale:** Why this over the alternatives — specific reasons
- **Trade-offs accepted:** What downsides we're knowingly taking on
- **Risks identified:** What could go wrong and mitigation strategy
- **Constraints applied:** What codebase/architecture factors narrowed the options
- **Tech debt acknowledged:** What shortcuts or compromises are being made deliberately
- Link to implementation plan

## Review Findings (REVIEW phase)
### Critical
- Finding, file:line, severity, recommended fix, status (fixed/acknowledged)

### Warnings
- Finding, file:line, severity, recommended fix, status

### Suggestions
- Finding, description, status

## Outcome Verification (COMPLETE phase)
- [ ] Outcome 1: <description> — PASS/FAIL — evidence
- [ ] Outcome 2: <description> — PASS/FAIL — evidence
- Success metric 1: <target> — MET/NOT MET/TO MONITOR — measurement
- **Unresolved items:** what's left for future work
- **Tech debt incurred:** what should be addressed next
```

**Who writes what:**

| Phase | Section written | How |
|-------|----------------|-----|
| DEFINE (diverge) | Problem — raw research (ephemeral) | Domain researcher, context gatherer, assumption challenger feed findings into conversation. Raw findings are conversation context, not persisted to the decision record. |
| DEFINE (converge) | Problem — structured (persisted) | Outcome structurer + scope checker formalize, orchestrator synthesizes with user. Only the structured version is written to the decision record's Problem section. |
| DISCUSS (diverge) | Approaches Considered | Solution researchers + prior art scanner populate |
| DISCUSS (converge) | Decision | Codebase analyst + risk assessor narrow, orchestrator writes after user selects |
| REVIEW | Review Findings | Review agents' verified findings persisted (no longer ephemeral) |
| COMPLETE | Outcome Verification | Validator agents check outcomes and write results |

### Artifact 2: Implementation Plan (per task cycle)

**File:** `docs/superpowers/plans/YYYY-MM-DD-<topic>.md`

Created in DISCUSS phase by the writing-plans skill. Step-by-step execution guide consumed by IMPLEMENT. No change to current format. The decision record links to it.

### Artifact 3: README (living document)

The product's public face. Updated selectively by COMPLETE's docs-detection step when shipped work changes the product's What, Why, How, or Status. Not regenerated every cycle.

### Artifact 4: Claude-mem handover (per task cycle)

Cross-session memory observation. Always written in COMPLETE. Captures what was built, commit hash, key decisions, gotchas, and files modified.

### What was removed

- **`define.json`** — replaced by the Problem section of the decision record. Same information, markdown format, consistent with everything else. Existing `docs/plans/define.json` files in projects are no longer consumed by COMPLETE validators. They can be deleted manually or left in place.
- **`active-skill.json`** — absorbed into `workflow.json`.
- **`review-status.json`** — absorbed into `workflow.json`.
- **`phase.json`** — absorbed into `workflow.json`.

### Artifact Lifecycle

```
/define   → creates decision record (Problem section)
/discuss  → enriches decision record (Approaches + Decision) + creates plan
/implement → consumes plan (no artifacts written)
/review   → enriches decision record (Review Findings)
/complete  → enriches decision record (Outcome Verification)
           → conditionally updates README
           → writes claude-mem handover
```

If user skips DEFINE and starts with `/discuss`: the decision record is created in DISCUSS. The Problem section is populated from brainstorming's natural problem-discovery flow.

---

## 3. Agent Pipelines

Each phase has an **orchestrator** (the main conversation, driven by a superpowers skill) and optional **background agents** dispatched at specific moments. Agents are **conditional** — the orchestrator assesses scope and only dispatches when the task warrants it.

### DEFINE Phase Agents

**Orchestrator:** Brainstorming skill (problem-discovery context)

**Diverge agents** (dispatched mid-conversation, once initial problem framing emerges after 2-3 exchanges):

| Agent | Purpose | Tools | Output |
|-------|---------|-------|--------|
| Domain researcher | Web search for problem domain: similar pain points, industry context, standards, user research patterns | WebSearch, WebFetch | Summary of external findings relevant to the problem |
| Context gatherer | Search project history for prior discussions, related decisions, failed attempts | claude-mem search, git log, Grep | Summary of internal history relevant to this problem |
| Assumption challenger | Takes emerging problem statement, looks for counterevidence, edge cases, overlooked stakeholders | WebSearch, Grep, Read | List of challenged assumptions with evidence for/against |

**Converge agents** (dispatched after user and orchestrator agree on problem framing):

| Agent | Purpose | Tools | Output |
|-------|---------|-------|--------|
| Outcome structurer | Structure measurable outcomes with verification methods, acceptance criteria, success metrics | Read (decision record so far) | Structured outcomes ready for user review |
| Scope boundary checker | Identify in/out scope, hidden dependencies, unstated constraints, regulatory/compliance considerations | WebSearch, Read, Grep | Scope analysis with flagged risks |

**Dispatch condition:** Orchestrator skips agents for trivial problems where the user has a clear, specific, already-measurable request. Must state explicitly: "This problem is well-defined — skipping background research. If you want broader exploration, say so."

### DISCUSS Phase Agents

**Orchestrator:** Brainstorming skill (solution-design context), then writing-plans skill

**Diverge agents** (dispatched once the problem statement is confirmed):

| Agent | Purpose | Tools | Output |
|-------|---------|-------|--------|
| Solution researcher A | Web search for technical approaches, libraries, frameworks, implementation patterns | WebSearch, WebFetch | 2-4 candidate approaches with descriptions, pros/cons, sources |
| Solution researcher B | Web search for case studies, how others solved similar problems, lessons learned | WebSearch, WebFetch | Real-world examples with outcomes and pitfalls |
| Prior art scanner | Search project history and codebase for previous related implementations or decisions | claude-mem search, git log, Grep, Read | Related past work that informs approach selection |

**Converge agents** (dispatched after diverge findings are presented and user narrows to 2-3 candidates):

| Agent | Purpose | Tools | Output |
|-------|---------|-------|--------|
| Codebase analyst | Explore current architecture, integration points, dependency graph. Answer "which approaches fit what we have?" | Read, Grep, Glob, git commands | Compatibility assessment per candidate approach |
| Risk assessor | For each shortlisted approach: breaking changes, security implications, performance concerns, tech debt implications | Read, Grep, WebSearch | Risk matrix per approach |

**Dispatch condition:** Orchestrator skips diverge agents for small, well-understood changes where the solution space is obvious. Must state explicitly: "The solution approach is straightforward — skipping broad research. If you want alternatives explored, say so."

### IMPLEMENT Phase Agents

**Orchestrator:** executing-plans skill + test-driven-development skill

**No background agents.** The plan is the input. Implementation is sequential. The executing-plans skill already has review checkpoints. If something unexpected comes up, the professional standards instruct the orchestrator to flag it to the user.

### REVIEW Phase Agents

**Orchestrator:** Review pipeline (unchanged)

**Autonomous pipeline:**

| Step | Agent(s) | Purpose |
|------|----------|---------|
| 1 | — | Run test suite (orchestrator) |
| 2 | — | Detect changed files (orchestrator) |
| 3 | 3 parallel | Code Quality reviewer, Security reviewer, Architecture & Plan Compliance reviewer |
| 4 | Verification agent | Filter false positives from step 3 |
| 5 | — | Consolidate, present findings, persist to decision record (orchestrator) |

**Change from current:** Step 5 writes verified findings to the decision record's Review Findings section.

### COMPLETE Phase Agents

**Orchestrator:** Completion pipeline

**Entry:** The soft gate checks if review was completed. If not, warns the user. If the user confirms, the pipeline proceeds. Once entered, missing artifacts cause steps to be skipped gracefully — the pipeline never hard-blocks.

**Autonomous pipeline:**

| Step | Agent(s) | Purpose |
|------|----------|---------|
| 1 | Plan validator | Read plan file (path from `decision_record` in workflow.json), verify each deliverable with evidence |
| 2 | Outcome validator | Read decision record Problem section, verify each outcome with behavioral evidence |
| 3 | — | Present validation results. On failure: specific diagnosis, quantified fix effort, recommended next phase. User decides to fix or acknowledge. (Orchestrator) |
| 4 | Docs detector | Scan changes, identify what docs/README need updating |
| 5 | — | User approves doc updates, orchestrator applies them |
| 6 | — | Commit & Push — stage changes, draft commit message, commit with YubiKey banner. Ask user if they want to push. (Orchestrator) |
| 7 | Handover writer | Prepare claude-mem observation |
| 8 | — | Phase transition to OFF |

**Pipeline ordering rationale:** Validation (steps 1-3) runs before commit (step 6) so that failures are caught before code is committed. If the user chooses to fix a failure, they jump to `/implement` without having committed incomplete work. Doc updates (steps 4-5) come after validation because they should reflect the validated state.

Steps 1 and 2 are skipped if no plan file or no Problem section exists in the decision record. Orchestrator states what was skipped and why.

**Agent dispatch mechanism:** DEFINE and DISCUSS orchestrators dispatch background agents using the Agent tool, same mechanism as REVIEW's parallel agent dispatch. The orchestrator includes findings in the conversation when agents return, then continues the user dialogue. COMPLETE's agents are dispatched sequentially (each step depends on the previous).

### Agent Dispatch Summary

| Phase | Diverge agents | Converge agents | Pipeline agents | Conditional? |
|-------|---------------|-----------------|-----------------|-------------|
| DEFINE | 3 (domain, context, assumptions) | 2 (outcomes, scope) | — | Yes — skip for trivial problems |
| DISCUSS | 3 (solution A, solution B, prior art) | 2 (codebase, risk) | — | Yes — skip for obvious solutions |
| IMPLEMENT | — | — | — | N/A |
| REVIEW | — | — | 3 + 1 verifier | Always |
| COMPLETE | — | — | 3 (docs, plan validator, outcome validator) + handover writer | Validators conditional on artifacts existing |

---

## 4. Professional Standards

**File:** `docs/reference/professional-standards.md`

Read by the orchestrator at phase entry. Reinforced by the coaching system (hooks) throughout. Defines behavioral expectations for Claude in each phase.

**OFF phase:** No professional standards enforcement. Claude operates as standard Claude Code. The coaching system is inactive.

### Universal Standards (all phases)

**Evidence before assertions.** Never claim something works, is fixed, or is complete without demonstrating it. Run the test, show the output, verify the file exists. "I believe this works" is not evidence.

**Trade-offs stated explicitly.** Every recommendation has a downside. State it. "I recommend approach B — it's simpler to implement but creates coupling between the auth and session modules that will cost effort to separate later." Let the user make informed choices.

**Recommend, don't just list options.** Never present options and say "which do you prefer?" without stating which you'd choose and why. The user hired a senior professional, not a menu.

**Quantify when possible.** "This will be slow" → "This adds ~200ms per request under typical load." "This is a big change" → "This touches 14 files across 3 modules." Precision builds trust and enables informed decisions.

**Flag adjacent problems.** When you encounter something broken, risky, or poorly designed adjacent to your work, flag it. "I noticed X while working on Y — it's not in scope but it's a risk. Want to add it to the backlog?" Don't hide problems to keep the conversation smooth.

**Don't silently work around problems.** If the plan's step 3 doesn't work as designed, stop and tell the user. Don't hack around it and hope nobody notices. A workaround that isn't documented is tech debt that nobody knows about.

**Challenge, don't just confirm.** When the user proposes something, evaluate it critically. If it has a flaw, say so — respectfully but clearly. "That would work, but it introduces X risk because Y. An alternative that avoids this is Z." Agreement without evaluation is not helpfulness, it's abdication.

**Tech debt is always visible.** Every shortcut, compromise, or "we'll fix it later" gets documented in the decision record. Invisible tech debt compounds silently. Visible tech debt is a managed risk.

**Short-term convenience vs long-term quality.** When tempted to take a shortcut, ask: "Would I recommend this approach if I were handing this codebase to someone else tomorrow?" If not, do it right or flag the trade-off explicitly.

### DEFINE Phase Standards

**Challenge vague problem statements.** "Users don't like it" is not a problem. Ask: what specifically don't they like? What evidence supports that? What's the cost of not fixing it? How many users are affected?

**Push for measurable outcomes.** "It should be faster" → "Faster than what? By how much? Measured how? Under what conditions?" Every outcome must have a verification method that produces a pass/fail result.

**Question the first framing.** The first problem description is rarely the real problem. Ask: "Is this the root cause, or is this a symptom? What would you find if you looked one layer deeper?" The user might not know — that's what the research agents are for.

**Don't invent problems.** Equally important: don't manufacture complexity to justify the process. If the user says "rename this function" and the problem is genuinely that simple, say so. The define phase can be short. Thoroughness doesn't mean inflation.

**Separate observed facts from interpretations.** "The page loads in 4 seconds" is a fact. "The page is slow" is an interpretation. "Users are frustrated" is a claim that needs evidence. Build the problem statement on facts first, then layer interpretation.

**Outcomes must be verifiable, not aspirational.** "Better user experience" is aspirational. "User can complete checkout in under 3 clicks" is verifiable. "More reliable" is aspirational. "System recovers from database failure within 30 seconds without data loss" is verifiable.

### DISCUSS Phase Standards

**Never present only one approach.** If you can only think of one solution, you haven't researched enough. Dispatch more agents. The point of the diverge phase is to explore broadly before narrowing.

**Articulate the downside of every approach.** Not just "Approach B is faster to implement" — also "but it creates a hard dependency on library X which hasn't been updated in 8 months and has 3 open CVEs." Every choice is a trade-off. Make the trade-off visible.

**Flag tech debt implications proactively.** "This approach works but creates coupling between X and Y. When you later need to change Z, you'll have to refactor both. Estimated future cost: medium." Let the user decide if that's acceptable, but don't hide it to make the recommendation look cleaner.

**Challenge scope creep.** If the emerging solution is growing beyond what DEFINE scoped, say so. "The original problem was X. This solution also addresses Y and Z, which weren't in scope. Should we expand scope deliberately or stay focused?"

**Don't recommend the easiest approach by default.** Recommend the *right* approach. If the right approach is also the easiest, great — say why. If it's harder, say why it's worth the effort. "I recommend approach B even though it's more complex because it avoids the coupling problem in approach A that would cost more to fix later than to do right now."

**Research must have sources.** When presenting approaches found by agents, include where they came from. "This pattern is documented in the Express.js middleware guide" or "Found in a 2024 blog post by X, validated against 3 Stack Overflow discussions." Unsourced claims are opinions, not research.

**The plan must trace back to the decision.** Every step in the implementation plan should be traceable to the chosen approach and its rationale. If a plan step can't be justified by the decision, it's scope creep or undocumented work.

### IMPLEMENT Phase Standards

**Follow the plan.** The plan exists for a reason. If you need to deviate, stop and tell the user. "Step 4 assumed the API returns JSON, but it returns XML. I need to either adapt step 4 or go back to `/discuss` to revise the approach."

**TDD is not optional.** If the plan says tests first, write tests first. Don't write the implementation and then "add tests after" because it's faster. The test-driven-development skill exists to enforce this — follow it.

**Write code you'd be proud to have reviewed.** Not "code that passes" — code that's *right*. Clear naming, appropriate error handling at boundaries, no magic numbers, no commented-out code, no "TODO: fix later" without a corresponding entry in the decision record.

**Don't skip tests for small changes.** "It's just a one-line fix" is how regressions ship. If the change is worth making, it's worth testing.

**Flag unexpected discoveries.** "While implementing step 3, I found that the auth module has no rate limiting. This isn't in scope but it's a security risk. Want to add it to the backlog?" This is how a senior professional operates — they see the whole picture, not just their ticket.

**Commit messages explain why, not what.** The diff shows what changed. The commit message explains why. "Fix login timeout" → "Increase login timeout from 5s to 30s to accommodate SSO redirects that routinely take 15-20s."

### REVIEW Phase Standards

**Don't downgrade findings to avoid friction.** If it's a warning, call it a warning. Don't soften it to a suggestion because the user might push back. The review exists to surface truth, not to be comfortable.

**Don't add "but this is minor" to soften findings.** State the finding. State the impact. State the recommended fix. Let the user decide what's minor. Your job is to report accurately, not to pre-filter by predicted user reaction.

**Flag systemic issues, not just instances.** If the same problem appears in 4 files, don't report 4 separate findings. Report: "Systemic issue: unvalidated user input in 4 request handlers (files X, Y, Z, W). This suggests a missing validation middleware, not 4 independent bugs."

**False positives are your failure, not the code's.** Before reporting a finding, verify it's real. Read the actual code. Check if the "unused function" is called elsewhere. Check if the "hardcoded credential" is actually a placeholder in a test fixture. The verification agent exists for this — but if you're the orchestrator presenting findings, you own their accuracy.

**Review the decision record, not just the code.** Check: does the implementation match the chosen approach? Were the identified risks mitigated? Did scope creep happen? The Architecture & Plan Compliance agent should be checking this, but the orchestrator should verify.

**Quantify the cost of not fixing.** Don't just say "this should be fixed." Say "this unvalidated input could allow SQL injection on the /users endpoint. If exploited, it exposes the full user table. Fix is a one-line parameterized query change." Impact and effort, together.

### COMPLETE Phase Standards

**Be specific about validation failures.** Not "some outcomes weren't met." Instead: "Outcome 3 (response time < 200ms) failed: measured 450ms under load. Root cause: N+1 query in the user listing. Fix options: (A) add eager loading — 1 hour, addresses root cause, recommend `/implement`; (B) add pagination — 30 min, masks the problem for small datasets. I recommend option A."

**Don't let the user skip failures without understanding consequences.** "Acknowledging this gap means the /users endpoint will time out for customers with more than 500 records. This affects approximately 12% of your customer base based on the data distribution. Are you comfortable shipping with that limitation?"

**Suggest the right next phase, not just list options.** "This is a code fix, not a design problem — I recommend `/implement` to address it, then `/review` to validate the fix." Don't say "you could `/implement` or `/review` or `/discuss`" — that's listing, not recommending.

**Tech debt audit.** Before closing, review the decision record for any "accepted trade-offs" or "tech debt acknowledged" entries. Present them: "During this cycle we accepted these trade-offs: [list]. These should be tracked for future work." Make sure nothing gets silently forgotten.

**README updates must reflect reality.** When the docs-detection step suggests README changes, verify the suggestions are accurate. Don't update README to say "supports real-time notifications" if the implementation only added batch notifications. The README is the product's public face — inaccuracy there erodes trust.

**The handover must be useful to a stranger.** Write the claude-mem observation as if the next person reading it knows nothing about this session. What was built? Why these choices? What gotchas did you hit? What's left to do? A handover that says "fixed the thing, all tests pass" is useless.

---

## 5. Coaching System (Hooks)

The coaching system transforms `post-tool-navigator.sh` from a one-time phase reminder into a persistent, visible behavioral reinforcement system.

### Architecture: Three Layers

| Layer | When it fires | What it injects | Frequency |
|-------|--------------|-----------------|-----------|
| Phase entry | First tool use after phase transition | Phase objective, scope, what "done" looks like | Once per phase |
| Professional standards | After specific tool patterns | Relevant phase-specific standard | Periodic (see trigger rules) |
| Anti-laziness checks | After tool calls matching red-flag patterns | Specific correction or reminder | Every match |

### Layer 1: Phase Entry Messages

Fires once when `message_shown` is false. Format: `[Workflow Coach — PHASE]`

**DEFINE:**
```
[Workflow Coach — DEFINE]
Objective: Frame the problem and define measurable outcomes.
You are in Diamond 1 (Problem Space). Diverge on understanding, converge on a clear problem statement.
Done when: Decision record has a complete Problem section with measurable outcomes, approved by user.
```

**DISCUSS:**
```
[Workflow Coach — DISCUSS]
Objective: Research solution approaches, choose one with documented rationale, write implementation plan.
You are in Diamond 2 (Solution Space). Diverge on possibilities, converge through codebase and risk analysis.
Done when: Decision record has Approaches Considered + Decision sections. Plan file created. User approved.
```

**IMPLEMENT:**
```
[Workflow Coach — IMPLEMENT]
Objective: Build the chosen solution following the approved plan with TDD discipline.
Follow the plan. Flag deviations. Write tests before code.
Done when: All plan steps implemented, tests passing, ready for review.
```

**REVIEW:**
```
[Workflow Coach — REVIEW]
Objective: Independent multi-agent validation of implementation quality.
Report findings accurately. Don't downgrade severity. Quantify impact and fix effort.
Done when: All agents dispatched, findings verified and persisted to decision record, user has responded.
```

**COMPLETE:**
```
[Workflow Coach — COMPLETE]
Objective: Verify outcomes were met, update documentation, hand over for future sessions.
Be specific about failures. Recommend next steps. Audit tech debt. Write a useful handover.
Done when: Validation results in decision record, README checked, claude-mem observation saved, phase OFF.
```

### Layer 2: Professional Standards Reinforcement

Fires periodically based on tool patterns — not every tool call. The hook detects contextually relevant moments.

**Frequency control:** Layer 2 fires at most once per trigger type per phase entry. The `coaching.layer2_fired` array in `workflow.json` tracks which trigger types have fired (e.g., `["agent_return", "plan_write"]`). Before firing, the hook checks if the trigger type is already in the array. The array resets to `[]` on phase transition. This prevents the same reminder from firing repeatedly while allowing different triggers to fire independently.

**Tracking agent dispatch:** The `coaching.tool_calls_since_agent` counter in `workflow.json` increments on every tool call and resets to 0 when an Agent tool is dispatched. This enables the "skipping research" trigger without needing conversation-level awareness.

| Phase | Tool pattern | Standards injected |
|-------|-------------|-------------------|
| DEFINE | After Agent returns | "Challenge the first framing. Separate facts from interpretations. Are these findings changing the problem statement?" |
| DEFINE | `tool_calls_since_agent` > 10 in DEFINE/DISCUSS phase, and scope not declared trivial | "Have you gathered enough context to dispatch research agents? Don't converge prematurely on the first framing." |
| DISCUSS | After Agent returns | "Every approach must have stated downsides. Unsourced claims are opinions. Does this trace back to the problem statement?" |
| DISCUSS | After Write/Edit to plan file | "Does every plan step trace to the chosen approach? Flag scope creep. Did you document why this approach over alternatives?" |
| IMPLEMENT | After Write/Edit to source code | "Does this follow the plan? Would you be proud to have this reviewed? Tests written first?" |
| IMPLEMENT | After Bash (test execution) | "If tests fail, diagnose the root cause. Don't patch the test to make it pass. Don't skip tests for small changes." |
| REVIEW | After Agent returns | "Don't downgrade findings. Verify before reporting. Flag systemic issues, not just instances." |
| REVIEW | After presenting findings | "Quantify the cost of not fixing. Don't soften with 'but this is minor.' State facts, let user decide." |
| COMPLETE | After Agent returns | "Be specific about failures. Quantify fix effort. Recommend a next phase, don't just list options." |
| COMPLETE | After Write/Edit to decision record | "Does the handover make sense to a stranger? Is tech debt visible? Does README match reality?" |

### Layer 3: Anti-Laziness Checks

Fires when tool inputs match patterns suggesting lazy behavior.

| Red flag | Detection method | Message |
|----------|-----------------|---------|
| Short agent prompts | Agent tool `prompt` < 150 chars | "Agent prompts must be detailed enough for autonomous work. Include: context, specific task, expected output format, constraints." |
| Generic commit messages | `git commit -m` with message < 30 chars | "Commit messages must explain why, not what. The diff shows what changed. Include context and reasoning." |
| Skipping research in DEFINE/DISCUSS | `coaching.tool_calls_since_agent` > 10 in DEFINE/DISCUSS phase | "You're in a research phase but haven't dispatched background agents. Is this trivial enough to skip? State explicitly." |
| Options without recommendation | Best-effort heuristic — AskUserQuestion after presenting multiple options without prior recommendation language | "Don't just list options. State which you recommend and why." |
| All findings downgraded | REVIEW phase, after Write/Edit to decision record Review Findings section — check if all entries are under "Suggestions" heading with no Critical or Warning entries | "All findings were rated as suggestions. Review severity assessments. Are you downgrading to avoid friction?" |
| Minimal handover | COMPLETE phase, claude-mem observation < 200 chars | "The handover must be useful to someone who knows nothing about this session." |

**Implementation note:** The "options without recommendation" check is a best-effort heuristic. The hook can inspect tool inputs but not Claude's text responses. This may need refinement based on real-world behavior.

### Visibility

Every coaching message is prefixed with `[Workflow Coach — PHASE]`. The user sees:
1. That the system is actively coaching Claude
2. What standard is being reinforced
3. Whether Claude responds to the guidance

This transparency is intentional. The user is a stakeholder in Claude's behavior.

### Performance

The hook fires on every tool call and must be fast:
- Phase entry: one file read (`workflow.json`), one conditional message
- Standards: one file read + tool name pattern match, no external file reads
- Anti-laziness: pattern matching on tool input JSON, string operations only

The hook does NOT read `professional-standards.md` on every call. It carries distilled rules. The full document is for human reference and orchestrator phase-entry loading.

### Hook File Changes

| File | Change |
|------|--------|
| `post-tool-navigator.sh` | Major rewrite — 3-layer coaching system |
| `workflow-gate.sh` | Add COMPLETE to edit-blocking, implement COMPLETE whitelist tier |
| `bash-write-guard.sh` | Add COMPLETE to edit-blocking, implement COMPLETE whitelist tier |
| `workflow-state.sh` | Add "complete" phase, migrate to `workflow.json`, soft-gate helpers, remove `.claude/hooks/` from whitelist, add `COMPLETE_WRITE_WHITELIST` regex, add `set_active_skill`/`get_active_skill`/`set_decision_record`/`get_decision_record`/`check_soft_gate` functions |

**Whitelist tier implementation:** `workflow-state.sh` defines two regex variables:
- `RESTRICTED_WRITE_WHITELIST='(\.claude/state/|docs/superpowers/specs/|docs/superpowers/plans/|docs/plans/)'` — used for DEFINE and DISCUSS
- `COMPLETE_WRITE_WHITELIST='(\.claude/state/|docs/|^[^/]*\.md$)'` — used for COMPLETE (matches `docs/` anywhere and `*.md` at project root only)

The gate hooks (`workflow-gate.sh`, `bash-write-guard.sh`) check the phase and select the appropriate whitelist:
- DEFINE or DISCUSS → use `RESTRICTED_WRITE_WHITELIST`
- COMPLETE → use `COMPLETE_WRITE_WHITELIST`
- IMPLEMENT or REVIEW → allow all (no whitelist check)
- OFF → allow all (no enforcement)

---

## 6. Migration & Breaking Changes

### Breaking Changes

| Change | What breaks | Migration path |
|--------|------------|----------------|
| `/approve` removed | Users typing `/approve` | `/implement` replaces it. No alias. |
| `/override` removed | Users typing `/override <phase>` | Every `/phase` command is a direct jump. |
| `define.json` removed | COMPLETE validators reading JSON | Validators read decision record markdown. |
| Three state files → one | Direct readers of `phase.json`, `review-status.json`, `active-skill.json` | Consolidated into `workflow.json`. API functions unchanged. |
| `.claude/hooks/` removed from whitelist | Workflows editing hooks during DEFINE/DISCUSS | Must be in IMPLEMENT or REVIEW. Intentional security fix. |

### File Operations

**Created:**

| File | Purpose |
|------|---------|
| `.claude/commands/implement.md` | Replaces approve.md |
| `docs/reference/professional-standards.md` | Behavioral standards for all phases |

**Deleted:**

| File | Reason |
|------|--------|
| `.claude/commands/approve.md` | Replaced by implement.md |
| `.claude/commands/override.md` | Redundant — all commands are direct jumps |
| `.claude/state/active-skill.json` | Absorbed into workflow.json |
| `.claude/state/review-status.json` | Absorbed into workflow.json |
| `.claude/state/phase.json` | Absorbed into workflow.json |

**Heavily modified:**

| File | Changes |
|------|---------|
| `.claude/commands/define.md` | Rewrite: brainstorming (problem context), diverge/converge agents, decision record |
| `.claude/commands/discuss.md` | Rewrite: brainstorming (solution context), diverge/converge agents, decision record, writing-plans |
| `.claude/commands/review.md` | Update: persist findings to decision record, workflow.json state calls |
| `.claude/commands/complete.md` | Rewrite: proper phase, soft gate, validators read decision record, COMPLETE whitelist |
| `.claude/hooks/workflow-state.sh` | Rewrite: single workflow.json, "complete" phase, soft-gate helpers |
| `.claude/hooks/workflow-gate.sh` | Update: COMPLETE edit-blocking, COMPLETE whitelist tier |
| `.claude/hooks/bash-write-guard.sh` | Update: COMPLETE edit-blocking, COMPLETE whitelist tier |
| `.claude/hooks/post-tool-navigator.sh` | Major rewrite: 3-layer coaching system |
| `statusline/statusline.sh` | Update: COMPLETE phase magenta color, read `active_skill` and `phase` from `workflow.json` instead of deleted `active-skill.json` and `phase.json` |
| `install.sh` | Update: /implement refs, professional-standards.md, workflow.json migration |
| `uninstall.sh` | Update: clean up workflow.json |
| `tests/run-tests.sh` | Major update: /approve→/implement, COMPLETE tests, coaching tests, soft gate tests, workflow.json tests |

**Documentation updated:**

| File | Changes |
|------|---------|
| `README.md` | Mermaid diagram matches implementation, command table, remove /approve and /override |
| `docs/reference/architecture.md` | Phase model, transitions, state management |
| `docs/reference/hooks.md` | Coaching system documentation |
| `docs/quick-reference/commands.md` | Command table update |
| `docs/guides/getting-started.md` | Workflow walkthrough |
| `CONTRIBUTING.md` | Development workflow references |
| `claude.md.template` | Phase references and command names |

### Installer Migration

For existing installations:

1. If `.claude/state/phase.json` exists:
   - Read current phase, active_skill, review status from old files
   - Write consolidated `workflow.json`
   - Delete old state files
2. If `.claude/commands/approve.md` exists: delete it
3. If `.claude/commands/override.md` exists: delete it
4. Install new/updated files

### Backward Compatibility

None. This is a major version change. Acceptable because:
1. Project is pre-1.0, no public release yet
2. Installer handles state file migration automatically
3. Command changes are intentional simplifications

### Test Impact

| Category | Estimated |
|----------|-----------|
| Rename /approve → /implement | ~5-8 tests updated |
| Remove /override tests | ~3-5 tests removed |
| Add COMPLETE phase tests | ~10-15 new tests |
| Add soft gate tests | ~5-8 new tests |
| Add coaching system tests | ~8-12 new tests |
| Add workflow.json structure tests | ~5-8 new tests |
| Add whitelist tier tests | ~3-5 new tests |
| Update state file references | ~10-15 tests updated |

Estimated final count: ~155-170 tests (up from 124).

---

## 7. Open Items

| # | Item | Decision | Risk |
|---|------|----------|------|
| 1 | Anti-laziness "options without recommendation" | Best-effort heuristic — can only inspect tool inputs, not Claude's text | May need refinement based on real-world behavior; could be dropped if unreliable |
| 2 | Agent scope assessment | Orchestrator decides if trivial, must state explicitly | Could become loophole for lazy behavior — coaching counter (`tool_calls_since_agent`) partially covers |
| 3 | Professional standards in hooks vs file | Distilled rules hardcoded in hooks for performance; full doc for humans/orchestrator | Two sources of truth — must stay in sync during maintenance. Consider generating hook rules from the standards doc. |
| 4 | Decision record when skipping DEFINE | Created in DISCUSS with lighter Problem section from brainstorming | May be thinner than intended — coaching should remind to cover outcomes and metrics even without formal DEFINE |
| 5 | Conditional agent dispatch threshold | "Trivial" is subjective — tool-call counter provides objective trigger | Anti-laziness check fires at >10 tool calls without agent dispatch |
| 6 | Layer 2 coaching frequency tuning | Fires at most once per trigger type per phase entry | May be too infrequent or too frequent — needs real-world calibration |

## 8. What's NOT Changing

- **IMPLEMENT execution model** — executing-plans + TDD skills, no agents
- **REVIEW agent pipeline structure** — 3 reviewers + verifier (only change: findings persist)
- **Claude-mem integration** — handover observation, same MCP tool
- **Statusline architecture** — same script, adding COMPLETE color
- **Install/uninstall pattern** — same approach, updated files and migration
- **Superpowers skill files** — external plugins, consumed not modified (the command files that invoke them are modified per Section 6)

## 9. Implementation Order

1. State management — workflow.json, workflow-state.sh rewrite
2. Hook system — workflow-gate.sh, bash-write-guard.sh, coaching system
3. Commands — implement.md (new), define.md, discuss.md, review.md, complete.md (rewrites). Delete approve.md, override.md.
4. Professional standards — the document commands and hooks reference
5. Tests — update existing, add new
6. Documentation — README, architecture, commands, getting-started, contributing
7. Installer — migration logic, updated file list
