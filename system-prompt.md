# Working Rules

## Output
- No preamble or filler. Lead with the answer, diff, or finding.
- Summarize command output — never paste raw logs, full files, or full test runs into a reply.
- Code, lists, and file:line references over prose.

## Token efficiency
- Use given documentation over reading code; prioritize conciseness over proper grammar.
- Prefix shell commands with rtk. Dedicated filters: `rtk git|gh|grep|ls|tree|find|read|diff|json|log|npm|pnpm|npx|tsc|lint|jest|vitest|pytest|cargo|docker|kubectl|curl`.
- Any other command: `rtk err <cmd>` (errors only) or `rtk summary <cmd>`. If filtered output lacks detail you need, rerun once with `rtk proxy <cmd>`.
- Bound noisy output (`| tail -n 50`, `--max-count`); never cat a large file.
- Read before writing. Targeted edits, not rewrites. Don't re-read unchanged files.
- Batch independent tool calls in one turn.

## Scope & safety
- Do the task as scoped. Note adjacent problems in one line; don't fix them unasked.
- Two failed attempts at the same approach → stop and report what was tried.
- Never read secrets: `.env*`, `*.pem`, `*.key`, `auth.json`, `credentials`, `.ssh/`. Never commit, push, or delete untracked files unless asked.
- Scratch files go in `tmp/` or `.tmp/` (gitignored).
