Transition the workflow to DEFINE phase. Run this command:

```bash
WF_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}" && source "$WF_DIR/.claude/hooks/workflow-state.sh" && set_phase "define" && cat > "$STATE_DIR/active-skill.json" <<'SK'
{"skill": "", "updated": "phase-transition"}
SK
echo "Phase set to DEFINE — code edits are blocked. Define the problem and outcomes first."
```

Then confirm to the user that the phase has changed and code edits are blocked.

**You are now in DEFINE phase.** Guide the user through these sections, one at a time. Ask questions conversationally — one question per message, prefer multiple choice when possible.

## Section 1 — Problem Discovery

Understand the problem before trying to solve it:
- Who is affected by this problem?
- What pain or friction are they experiencing?
- What's the current state or workaround?
- Why does this matter now?

## Section 2 — Problem Statement

Synthesize the discovery into a crisp problem statement. Use a "How Might We" framing if appropriate.
Present it to the user: "Is this the right problem?"
Iterate until the user confirms.

## Section 3 — Outcome Definition

Define what success looks like — observable, measurable criteria that can be verified.

For each outcome, capture:
- **Description** — what should be true when we're done
- **Type** — functional, performance, security, reliability, usability, maintainability, compatibility
- **Verification method** — how to demonstrate it (not just prove code exists)
- **Acceptance criteria** — the specific evidence that confirms it

Present diverse examples appropriate to the project type. A CLI tool needs different examples than a web API, a library, or an infrastructure script. Outcomes must be verifiable — expressible as a test that can pass or fail. Verification means exercising the behavior end-to-end, not just proving code exists.

**Success metrics** — quantifiable measures of whether the outcomes collectively solve the problem:
- What to measure, what the target is, how to measure it
- Some metrics are immediately verifiable; others are long-term (flag as "to monitor post-release")
- Not every project needs formal metrics — don't force them when they'd be artificial

## Section 4 — Boundaries

- What's explicitly **in scope**?
- What's explicitly **out of scope** (anti-goals)?
- Any constraints or dependencies?

## Output

After all sections are complete, save the definition to `docs/plans/define.json`. The file must capture:
- The problem statement and who is affected
- All defined outcomes with their type, verification method, and acceptance criteria
- Success metrics with targets and how to measure them (if applicable)
- Linkage between outcomes and the metrics they support
- Scope boundaries (in-scope, out-of-scope, constraints)
- Creation date

Confirm to the user: "Problem and outcomes saved to `docs/plans/define.json`. Use `/discuss` to proceed to discussion and planning."

**Important:** When transitioning, update the active skill tracker:
```bash
WF_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}" && echo '{"skill": "SKILL_NAME", "updated": "now"}' > "$WF_DIR/.claude/state/active-skill.json"
```
Replace SKILL_NAME with the skill being used (e.g., "brainstorming", "writing-plans").
