## Pi
- rtk is loaded as an extension; prefix shell commands with rtk.
- Web: use the `search` and `scrape` tools (Firecrawl) instead of curl for pages. Keep `limit` ≤ 5 and `scrapeResults` off unless full page content is required.
- bash-guard may block risky commands. If blocked, propose a safer alternative — never retry the same command.
- Subagents run headless with destructive ops hard-blocked; do `git commit/pull/push` only in the main session.
