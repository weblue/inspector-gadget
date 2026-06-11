#!/usr/bin/env bash
# maintain.sh — recurring hygiene checks for agent-jacket machines
#
# Usage:
#   ./maintain.sh           # report only
#   ./maintain.sh --prune   # also delete junk files and stale install backups
#
# Run ad hoc, or schedule it (cron / launchd, or a Claude Code routine via /schedule).
# Covers the recurring items in docs/TODO.md: rtk savings, junk files, stale
# backups, prompt bloat, gitignore candidates, stale sandcastle branches.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRUNE=0
[[ "${1:-}" == "--prune" ]] && PRUNE=1

if [[ -t 1 ]]; then
  BOLD=$'\033[1m'; DIM=$'\033[2m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; CYAN=$'\033[36m'; RESET=$'\033[0m'
else
  BOLD="" DIM="" GREEN="" YELLOW="" CYAN="" RESET=""
fi
info()    { echo -e "${CYAN}${BOLD}=>${RESET} $*"; }
success() { echo -e "${GREEN}${BOLD}✓${RESET}  $*"; }
warn()    { echo -e "${YELLOW}${BOLD}!${RESET}  $*"; }

# ─── rtk savings ──────────────────────────────────────────────────────────────
info "rtk token savings"
if command -v rtk &>/dev/null; then
  rtk gain 2>/dev/null | tail -n 6 || true
  echo "   ${DIM}Find unwrapped commands: rtk discover${RESET}"
else
  warn "rtk not installed — run ./install.sh"
fi

# ─── junk files ───────────────────────────────────────────────────────────────
info "Finder junk in repo"
JUNK_COUNT=$(find "$REPO_DIR" -name ".DS_Store" -not -path "*/node_modules/*" 2>/dev/null | wc -l | tr -d ' ')
if [[ "$JUNK_COUNT" -gt 0 ]]; then
  if [[ "$PRUNE" -eq 1 ]]; then
    find "$REPO_DIR" -name ".DS_Store" -not -path "*/node_modules/*" -delete
    success "Deleted $JUNK_COUNT .DS_Store file(s)."
  else
    warn "$JUNK_COUNT .DS_Store file(s) — rerun with --prune to delete."
  fi
else
  success "No junk files."
fi

# ─── stale install backups ────────────────────────────────────────────────────
# seed_file writes <dest>.backup.<timestamp> on overwrite; prune after 30 days.
info "Stale install backups (>30 days) in agent homes"
BACKUPS=$(find "$HOME/.claude" "$HOME/.codex" "$HOME/.pi" -maxdepth 3 -name "*.backup.*" -mtime +30 2>/dev/null || true)
if [[ -n "$BACKUPS" ]]; then
  echo "$BACKUPS" | sed 's/^/   /'
  if [[ "$PRUNE" -eq 1 ]]; then
    echo "$BACKUPS" | while IFS= read -r f; do rm -f "$f"; done
    success "Backups pruned."
  else
    warn "Rerun with --prune to delete."
  fi
else
  success "No stale backups."
fi

# ─── prompt bloat ─────────────────────────────────────────────────────────────
# Installed prompts load every session; flag any that grow past ~600 words.
info "Installed prompt sizes (words; flag > 600)"
for f in "$HOME/.claude/CLAUDE.md" "$HOME/.codex/AGENTS.md" "$HOME/.pi/agent/AGENTS.md" "$HOME"/.claude/agents/*.md; do
  [[ -f "$f" ]] || continue
  WORDS=$(wc -w < "$f" | tr -d ' ')
  if [[ "$WORDS" -gt 600 ]]; then
    warn "$WORDS  $f — consider pruning"
  else
    echo "   ${DIM}$WORDS  $f${RESET}"
  fi
done

# ─── gitignore candidates ─────────────────────────────────────────────────────
info "Large untracked files in repo (>1MB; gitignore candidates)"
LARGE=$(cd "$REPO_DIR" && git ls-files --others --exclude-standard -z 2>/dev/null \
  | xargs -0 -I{} find "{}" -size +1M 2>/dev/null || true)
if [[ -n "$LARGE" ]]; then
  echo "$LARGE" | sed 's/^/   /'
  warn "Add to .gitignore or move under tmp/."
else
  success "None."
fi

# ─── stale sandcastle branches ────────────────────────────────────────────────
info "Stale sandcastle/* branches (>14 days) in repo"
STALE=$(cd "$REPO_DIR" && git for-each-ref --format='%(refname:short) %(committerdate:relative)' \
  --sort=committerdate refs/heads/sandcastle/ 2>/dev/null \
  | awk '$2 ~ /weeks|months|years/ {print}' || true)
if [[ -n "$STALE" ]]; then
  echo "$STALE" | sed 's/^/   /'
  warn "Review and delete merged ones: git branch -d <branch>"
else
  success "None."
fi

echo ""
success "Maintenance pass complete.${PRUNE:+ }"
