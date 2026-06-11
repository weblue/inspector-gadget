# TODO

High-value items that need real effort, priority order. Low-effort fixes land directly in the repo.

1. **Merge-seed settings.json.** Install overwrites (with backup / `--force`). A python merge of `permissions.deny` + `env` into existing settings would propagate updates without clobbering local config. Value: painless updates on already-installed machines.
2. **Audit MCP/tool registrations per harness.** Every registered tool's description costs context each turn; disable unused ones.

## Resolved

- **Pinned installers** (2026-06-10): rtk Linux installs pinned to v0.42.3 release tarballs with in-repo sha256 verification (mac stays on brew, which verifies via formula). Tailscale Linux pinned to v1.98.4 static tarballs + in-repo sha256 on systemd hosts; non-systemd falls back to the official script with a loud unpinned warning. Bump instructions are inline comments in install.sh.
- **Sandcastle first-run** (2026-06-10): images are per-repo (`sandcastle:<repo-dir>`), so a central install-time prebuild doesn't apply. Resolved by documenting the per-repo `init && docker build-image` flow in the skill, install output, and the extension's error hint.
- **pi-subagents model routing** (2026-06-10): install.sh now seeds `subagents.agentOverrides` thinking levels (scout/context-builder low, worker medium, planner/reviewer/oracle high) into `~/.pi/agent/settings.json` — only when no `subagents` key exists, so user tuning is never clobbered.
- **OSC52 clipboard** (2026-06-10): copy-all falls back to OSC52 (with tmux passthrough wrapping) when no display server is present — clipboard now works from the headless server. Needs `set -g allow-passthrough on` in tmux ≥3.3.
- **Per-profile thinking budgets** (2026-06-10): Claude subagent frontmatter supports `effort` — coder/tester now `medium`, reviewer/architect/security `high`. Pi side covered by the agentOverrides thinking levels above.
- **Pi subagent VCS policy** (2026-06-10): bash-guard removed; AFK work routes through the sandcastle extension (Docker + worktree), parallel pi-subagents runs use `worktree: true`, duplicate `@tintinweb/pi-subagents` removed.

## Recurring hygiene

Run `./maintain.sh` (report) or `./maintain.sh --prune` (also deletes junk + stale backups). It covers: rtk savings + unwrapped-command hints, Finder junk, stale install backups, installed-prompt bloat (>600 words), large untracked files, stale `sandcastle/*` branches. Schedule it via cron or a Claude Code routine if manual runs lapse.
