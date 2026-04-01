# Step 5: Tests

Run the full test suite and verify all pass:

```bash
bash tests/run-tests.sh   # or equivalent for this project
```

If tests fail: fix them before proceeding. Do not mark `tests_passing` with failing tests.

If tests pass:

```bash
.claude/hooks/workflow-cmd.sh set_implement_field "tests_passing" "true"
.claude/hooks/workflow-cmd.sh set_tests_passed_at "$(git rev-parse HEAD)"
```

**If tests fail:** fix the code before marking `tests_passing`. Do not proceed to REVIEW with failing tests.
