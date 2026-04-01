# Step 3: Present Validation Results

**You MUST present the full evidence to the user — not just a summary.** The user cannot trust "24/24 PASS" without seeing what was checked and how.

Present validation results as tables:

**Plan Deliverables:**

| Task | Deliverable | Status | Evidence |
|---|---|---|---|
| 1 | Function X exists | PASS | `file.sh:42` |

**Outcomes:**

| # | Outcome | Status | Evidence |
|---|---|---|---|
| 1 | User can select levels | PASS | `command.md` calls `set_level`, test passes |

**Boundary Tests:**

| # | Component | Edge Case | Expected | Actual | Status |
|---|-----------|-----------|----------|--------|--------|
| 1 | <component> | <edge case description> | <expected behavior> | <actual behavior> | PASS/FAIL |

**Devil's Advocate:**

| # | Attack Vector | Target | Result | Severity |
|---|--------------|--------|--------|----------|
| 1 | <attack type> | <target component> | <what happened> | Critical/Warning/Info |

Then enrich the plan with the **Outcome Verification** section:

```markdown
## Outcome Verification (COMPLETE phase)
- [x] Outcome 1: <description> — PASS — evidence: <what was observed>
- [ ] Outcome 2: <description> — FAIL — evidence: <what went wrong>
- Success metric 1: <target> — MET/NOT MET/TO MONITOR
- **Unresolved items:** what's left for future work
- **Tech debt incurred:** what should be addressed next
```

**If any validation fails:**
- Present specific diagnosis with quantified fix effort
- Recommend the right next phase: "This is a code fix — I recommend `/implement` to address it, then `/review` to validate"
- Don't let the user skip without understanding consequences
- If validation finds critical issues:
  1. Document findings in the plan's Open Issues section
  2. Save as claude-mem observations (one per category)
  3. Create GitHub issues for critical/high findings (autonomy-gated)
  4. Continue the COMPLETE pipeline — commit what we have
  5. Next session picks them up from tracked observations

#### Step 3 Review Gate

Dispatch a **review agent** — read `plugin/agents/results-reviewer.md`, then dispatch as `general-purpose`:

Context: "Review the validation results. Plan: [PLAN_PATH]."

If REDO: fix the issues and re-dispatch the reviewer. Max 3 iterations, then surface to user.
Present summary: "Step 3 review: [findings found / no issues]. Fixed: [what changed]. Verdict: PASS."

Mark milestone:
```bash
.claude/hooks/workflow-cmd.sh set_completion_field "results_presented" "true"
```
