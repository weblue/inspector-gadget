# rtk

CLI proxy that compresses command output 60–90% before it reaches agent context. `install.sh` installs it on every platform (`brew install rtk-ai/tap/rtk` on mac, upstream install script on linux) and wires it per harness:

| Harness | Wiring |
|---|---|
| claude | `rtk init --global` — hook + `~/.claude/settings.json` |
| codex | `rtk init --global --codex` — rules appended to `~/.codex/AGENTS.md` |
| pi | `rtk init --agent pi --global` — extension `~/.pi/agent/extensions/rtk.ts` |

## Usage rules (mirrored in system-prompt.md)

- Dedicated filters: `rtk git|gh|grep|ls|tree|find|read|diff|json|log|npm|pnpm|npx|tsc|lint|jest|vitest|pytest|cargo|docker|kubectl|curl`.
- Any other command: `rtk err <cmd>` (errors/warnings only) or `rtk summary <cmd>` (2-line summary).
- Filtered output missing needed detail: rerun once as `rtk proxy <cmd>` (unfiltered, still tracked).

## Auditing savings

- `rtk gain` — accumulated token savings and history.
- `rtk discover` — finds unwrapped commands in Claude Code history.
- `rtk cc-economics` — spend (ccusage) vs savings analysis.
