#!/usr/bin/env bash
# server.sh — start remote access services on this machine
#
# What this does:
#   1. Verifies Tailscale is up and connected
#   2. Verifies SSH (Remote Login) is running
#   3. Creates or reattaches to the shared tmux session "briefcase"
#   4. Prints connection info for remote clients
#
# Prerequisites (run ./install.sh first):
#   - Tailscale installed and joined to your tailnet ('tailscale up')
#   - SSH enabled and hardened
#   - tmux installed
#
# boss-man is NOT started here.
# Run ~/projects/boss-man-dashboard/start.sh separately to serve the dashboard.
# Your homelab nginx should proxy to this machine's boss-man port externally.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ─── colours ──────────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
  BOLD=$'\033[1m'
  DIM=$'\033[2m'
  GREEN=$'\033[32m'
  YELLOW=$'\033[33m'
  CYAN=$'\033[36m'
  RED=$'\033[31m'
  RESET=$'\033[0m'
else
  BOLD="" DIM="" GREEN="" YELLOW="" CYAN="" RED="" RESET=""
fi

info()    { echo "${CYAN}${BOLD}=>${RESET} $*"; }
success() { echo "${GREEN}${BOLD}✓${RESET}  $*"; }
warn()    { echo "${YELLOW}${BOLD}!${RESET}  $*"; }
error()   { echo "${RED}${BOLD}✗${RESET}  $*" >&2; exit 1; }

SESSION="briefcase"

# ─── tailscale ────────────────────────────────────────────────────────────────
info "Checking Tailscale..."

if ! command -v tailscale &>/dev/null; then
  error "Tailscale not found. Run ./install.sh first."
fi

TS_STATUS="$(tailscale status --json 2>/dev/null | python3 -c \
  "import sys,json; d=json.load(sys.stdin); print(d.get('BackendState',''))" 2>/dev/null || echo "unknown")"

if [[ "$TS_STATUS" != "Running" ]]; then
  warn "Tailscale is not connected (state: ${TS_STATUS})."
  warn "Run 'tailscale up' to authenticate and join your tailnet, then re-run this script."
  exit 1
fi

TS_IP="$(tailscale ip -4 2>/dev/null || echo 'unknown')"
TS_HOSTNAME="$(tailscale status --json 2>/dev/null | python3 -c \
  "import sys,json; d=json.load(sys.stdin); s=d.get('Self',{}); print(s.get('DNSName','').rstrip('.'))" 2>/dev/null || echo 'unknown')"

success "Tailscale connected — ${TS_HOSTNAME} (${TS_IP})"

# ─── ssh ──────────────────────────────────────────────────────────────────────
info "Checking SSH (Remote Login)..."

if [[ "$(uname -s)" == "Darwin" ]]; then
  if sudo systemsetup -getremotelogin 2>/dev/null | grep -q "On"; then
    success "SSH (Remote Login) is enabled."
  else
    warn "SSH (Remote Login) is off — enabling now..."
    sudo systemsetup -setremotelogin on
    sudo launchctl load -w /System/Library/LaunchDaemons/ssh.plist 2>/dev/null || true
    success "SSH enabled."
  fi
else
  if systemctl is-active --quiet sshd 2>/dev/null; then
    success "sshd is running."
  else
    warn "sshd is not running. Start it with: sudo systemctl start sshd"
  fi
fi

# ─── tmux session ─────────────────────────────────────────────────────────────
info "Starting tmux session '${SESSION}'..."

if ! command -v tmux &>/dev/null; then
  error "tmux not found. Run ./install.sh first."
fi

if tmux has-session -t "$SESSION" 2>/dev/null; then
  success "Session '${SESSION}' already running."
else
  tmux new-session -d -s "$SESSION" -n "pi" \; \
    send-keys -t "${SESSION}:pi" "pi" Enter \; \
    new-window -t "$SESSION" -n "shell"
  success "Session '${SESSION}' started (windows: pi, shell)."
fi

# ─── connection info ──────────────────────────────────────────────────────────
echo ""
echo "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo "${BOLD}  Remote access ready${RESET}"
echo "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""
echo "  ${BOLD}SSH (Tailscale hostname):${RESET}"
echo "  ${CYAN}ssh ${USER}@${TS_HOSTNAME}${RESET}"
echo ""
echo "  ${BOLD}SSH (Tailscale IP):${RESET}"
echo "  ${CYAN}ssh ${USER}@${TS_IP}${RESET}"
echo ""
echo "  ${BOLD}Attach to tmux session after SSH:${RESET}"
echo "  ${CYAN}tmux attach -t ${SESSION}${RESET}"
echo ""
echo "  ${DIM}Session windows: 'pi' (Pi agent), 'shell' (general)${RESET}"
echo "  ${DIM}New windows: tmux new-window -t ${SESSION}${RESET}"
echo ""
echo "  ${BOLD}boss-man dashboard:${RESET}"
echo "  ${DIM}Start: ~/projects/boss-man-dashboard/start.sh${RESET}"
echo "  ${DIM}Configure homelab nginx to proxy → this machine on the boss-man port${RESET}"
echo ""
echo "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""
