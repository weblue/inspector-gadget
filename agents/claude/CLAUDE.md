## Claude Code
- Prefer built-in Read/Grep/Glob/Edit tools over shell equivalents; rtk applies to Bash commands.
- Worker subagents live in `~/.claude/agents/` (orchestrator, coder, reviewer, tester, architect, security). Delegate parallelizable multi-file work; keep small fixes in the main session.
- Subagent prompts must be self-contained: exact file paths, acceptance criteria, expected report format. Subagents return summaries, not transcripts.
- Skills: stop-slop (strip AI prose patterns), grill-me (interrogate a plan). Invoke when the task matches.
