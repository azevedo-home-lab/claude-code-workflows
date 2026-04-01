# Pre-validation: Test Evidence Gate

Before running the completion pipeline, check if tests need to re-run:

1. Read `tests_last_passed_at` from workflow state:
```bash
TESTS_COMMIT=$(.claude/hooks/workflow-cmd.sh get_tests_passed_at)
echo "Tests last passed at: $TESTS_COMMIT"
```

2. If set, check what changed since then:
```bash
git diff --name-only $TESTS_COMMIT..HEAD
```

3. Classify changed files using a **safe-to-skip whitelist** — only skip test re-run if ALL changed files match:
   - **Safe to skip** (non-code): `docs/**/*.md`, `*.txt`, `.gitignore`, `LICENSE`, `README.md`, `CHANGELOG.md`
   - **Everything else is code** — treat as requiring test re-run
   - Rule: if in doubt, treat as code (run tests)

4. If ALL changed files are safe to skip:
   - Present evidence: "No code files changed since tests passed at commit [hash]. Git diff shows only: [list]. Using previous test results as evidence."
   - Skip test re-run

5. If code files changed OR `tests_last_passed_at` is not set:
   - Run full test suite
   - Store the result: `.claude/hooks/workflow-cmd.sh set_tests_passed_at "$(git rev-parse HEAD)"`
