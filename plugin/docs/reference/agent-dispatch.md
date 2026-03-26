# Agent Dispatch Pattern

Claude Code does not support custom `subagent_type` values. The `workflow-manager:*`
agent types defined in `plugin/agents/` are specifications, not runtime-registered agents.

## How to dispatch a named agent

1. **Read** the agent file: `plugin/agents/<agent-name>.md`
2. **Extract** the agent's system prompt (everything after the YAML frontmatter closing `---`)
3. **Dispatch** using the Agent tool with:
   - `subagent_type`: `"general-purpose"`
   - `prompt`: Combine the agent's system prompt with the runtime context for this specific dispatch

## Example

To dispatch `plan-validator` with runtime context about the plan file:

1. Read `plugin/agents/plan-validator.md`
2. Use Agent tool:
   - `subagent_type: "general-purpose"`
   - `prompt: "<content of plan-validator.md after frontmatter>\n\n---\n\nRuntime context: Plan file is at docs/superpowers/specs/2026-03-26-example-design.md. Validate all deliverables."`

## Model selection

Agent files specify `model: inherit`. When dispatching as general-purpose, the parent
session's model is used automatically (this is the default behavior).

## Tools

Agent files list allowed tools in frontmatter (e.g., `tools: [Read, Grep, Glob]`).
When dispatching as general-purpose, all tools are available. The tool list in
frontmatter serves as documentation of what the agent needs, not as a restriction.
Review this section if Claude Code adds tool-scoping support for general-purpose agents.
