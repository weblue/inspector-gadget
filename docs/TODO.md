# TODO

High-value items that need real effort, priority order. Low-effort fixes land directly in the repo. (Replaces `action-items.md` — its remaining items are folded in below.)

1. **Decide Pi subagent VCS policy.** bash-guard hard-blocks `git commit/pull/push` in every Pi subagent (`PI_SUBAGENT_DEPTH >= 1`) — the main reason Pi multi-agent worked poorly: worker agents can't finish an implement→commit cycle and fail silently (no UI in headless mode). Either drop those three patterns from `HEADLESS_BLOCKED` (subagents commit; main session still guards) or keep VCS main-session-only and document Pi subagents as implement-only. Also on the server: two competing subagent packages are installed (`pi-subagents` v0.28 + `@tintinweb/pi-subagents`) — remove the tintinweb one from `~/.pi/agent` settings/npm, and add `subagents.agentOverrides` model routing to `~/.pi/agent/settings.json`. Value: working multi-agent on Pi.
2. **Merge-seed settings.json.** Install overwrites (with backup / `--force`). A python merge of `permissions.deny` + `env` into existing settings would propagate updates without clobbering local config. Value: painless updates on already-installed machines.
3. **Pin `curl | sh` installers.** rtk (linux) and Tailscale run unpinned remote scripts — the exact pattern bash-guard flags as high risk. Pin versioned release artifacts + checksums. Value: supply-chain safety on every new machine.
4. **bash-guard test suite.** vitest cases for `analyzeBashCommand` (rtk-wrapped, git subcommands, headless variants). shell-quote is already a dep. Value: guard regressions are silent safety gaps — the rtk bypass shipped unnoticed.
5. **OSC52 clipboard in copy-all.** Native clipboard tools don't cross SSH/tmux; OSC52 does. Value: `/copy-all` works from the server, where Pi actually runs.
6. **Per-profile thinking budgets.** Lower `MAX_THINKING_TOKENS` for mechanical roles (coder/tester), keep large for planning/review. A blanket global cap would hurt planning, so this needs per-profile env plumbing. Value: cost.
7. **Audit MCP/tool registrations per harness.** Every registered tool's description costs context each turn; disable unused ones. (firecrawl-search now self-disables without an API key.)

## Recurring hygiene

- Run `rtk discover` / `rtk gain` periodically; wrap missed commands.
- Revisit `.gitignore` when new tooling adds caches, logs, or generated output.
- Keep prompts lean; prune stale instructions from `system-prompt.md` / `agents/`.
- Scratch and generated files go under ignored `tmp/` / `.tmp/`.
