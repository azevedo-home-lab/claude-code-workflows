# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in Claude Code Workflows, please report it responsibly:

1. **Do NOT open a public issue**
2. Use [GitHub Security Advisories](https://github.com/azevedo-home-lab/claude-code-workflows/security/advisories/new) to report privately
3. Include: description of the vulnerability, steps to reproduce, and potential impact

You should receive a response within 7 days.

## Scope

Claude Code Workflows is a development workflow tool that runs locally. Security issues in scope include:

- **Hook bypass** — ways to circumvent workflow phase enforcement
- **Code injection** — exploiting hook scripts to execute unintended commands
- **Information disclosure** — exposing secrets or credentials through hook output
- **State manipulation** — tampering with workflow state to skip review gates

Out of scope:
- Vulnerabilities in Claude Code itself (report to [Anthropic](https://github.com/anthropics/claude-code/security))
- Vulnerabilities in Superpowers (report to [obra/superpowers](https://github.com/obra/superpowers/security))
- Social engineering or prompt injection (behavioral, not code-level)

## Supported Versions

| Version | Supported |
|---------|-----------|
| Latest on `main` | Yes |
| Previous releases | Best effort |
