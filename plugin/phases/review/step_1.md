# Step 1: Verify Tests Passed

The IMPLEMENT phase runs the full test suite as an exit gate (`tests_passing` milestone). Do NOT re-run the test suite here — use the IMPLEMENT result.

```bash
TESTS_PASSED=$(.claude/hooks/workflow-cmd.sh get_implement_field "tests_passing")
echo "IMPLEMENT tests_passing: $TESTS_PASSED"
```

- If `"true"`: report "Tests verified in IMPLEMENT phase" and continue.
- If not `"true"` or empty: tests may not have run or code changed since IMPLEMENT. Run the test suite now and report results.

Update state after this step:

```bash
.claude/hooks/workflow-cmd.sh set_review_field "verification_complete" "true"
```
