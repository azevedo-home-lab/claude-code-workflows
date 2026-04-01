# Step 5: Consolidate, Persist, and Present Findings

Take the verified findings and:

1. Deduplicate: same file+line from multiple agents → merge
2. Rank by severity: Critical → Warning → Suggestion
3. **Persist to plan**: Read `get_plan_path` for the path. If a plan exists, write the findings to its Review Findings section. If no plan, skip persistence and note it.

4. Present the report:

```
## Review Findings

### Critical (must fix before merge)
Prefix findings with category: [QUAL] code quality, [SEC] security, [ARCH] architecture, [GOV] governance, [HYG] codebase hygiene
- [findings or "None"]

### Warnings (should fix)
- [findings or "None"]

### Suggestions (nice to have)
- [findings or "None"]

---
Would you like to:
1. Fix issues now (stay in REVIEW phase, re-run /review after fixing)
2. Proceed to /complete (acknowledge findings as-is)
```

Update state:

```bash
.claude/hooks/workflow-cmd.sh set_review_field "agents_dispatched" "true"
.claude/hooks/workflow-cmd.sh set_review_field "findings_presented" "true"
```

Wait for the user's response. If they choose option 2 (acknowledge):

```bash
.claude/hooks/workflow-cmd.sh set_review_field "findings_acknowledged" "true"
```
