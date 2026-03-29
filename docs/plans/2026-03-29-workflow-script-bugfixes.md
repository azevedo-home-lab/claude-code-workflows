# Workflow Script Bugfixes

## Bugs Found During Architecture Docs Audit

| # | File | Bug | Severity |
|---|------|-----|----------|
| 1 | `workflow-state.sh:62` | `RESTRICTED_WRITE_WHITELIST` missing `docs/specs/` — blocks spec writes in DEFINE/DISCUSS | **High** |
| 2 | `workflow-state.sh:560-568` | Soft gate for `implement` checks for any plan file rather than current cycle's `plan_path` | **Medium** |
| 3 | `workflow-cmd.sh:49-51` | Error message gives no guidance on available commands or correct phase transition paths | **Medium** |
| 4 | Phase command files | No documentation of how phase transitions work — agent learns by failing | **Medium** |
| 5 | `bash-write-guard.sh:186-269` | Inconsistent indentation across guard-system and phase-gate sections | **Low** |
| 6 | `post-tool-navigator.sh:628` | Missing trailing newline | **Low** |
