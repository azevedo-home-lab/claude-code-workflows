# Step 2: Detect Changed Files

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
