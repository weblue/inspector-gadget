#!/usr/bin/env bash
# connect.sh — open briefcase server sessions as cmux workspaces (tabs)
#
# Run this on a client mac after client-install.sh.
# Opens three cmux workspaces, each SSH'd into the server:
#   1. pi      — attaches to the Pi agent tmux window
#   2. shell   — general-purpose shell on the server
#   3. logs    — tail of server logs / monitoring
#
# cmux must be running. Tailscale must be connected.
# SSH alias must be configured (~/.ssh/config Host briefcase-server).
#
# Usage:
#   ./connect.sh                      # uses default alias 'briefcase-server'
#   ./connect.sh my-server-alias      # use a custom SSH alias

set -euo pipefail

SSH_ALIAS="${1:-briefcase-server}"

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

# ─── preflight ────────────────────────────────────────────────────────────────
[[ "$(uname -s)" == "Darwin" ]] || error "connect.sh is macOS only (cmux is a macOS app)."

command -v cmux &>/dev/null || error "cmux CLI not found. Is cmux running? Open cmux from Applications first."

if ! cmux ping &>/dev/null; then
  error "cmux is not responding. Open cmux from Applications and try again."
fi

# Check Tailscale
TS_STATUS="$(tailscale status --json 2>/dev/null | python3 -c \
  "import sys,json; d=json.load(sys.stdin); print(d.get('BackendState',''))" 2>/dev/null || echo "unknown")"
if [[ "$TS_STATUS" != "Running" ]]; then
  error "Tailscale is not connected (state: ${TS_STATUS}). Connect to your tailnet first."
fi
success "Tailscale connected."

# Check SSH alias is in config
if ! ssh -G "$SSH_ALIAS" &>/dev/null; then
  error "SSH alias '${SSH_ALIAS}' not found in ~/.ssh/config. Run ./client-install.sh first."
fi

# ─── helpers ──────────────────────────────────────────────────────────────────
# Opens a new cmux workspace running an initial command.
# Uses `new-workspace --command`, the documented race-free way to launch a
# command in a fresh workspace (avoids the send + send-key + sleep timing dance).
open_workspace() {
  local label="$1"
  local cmd="$2"

  info "Opening workspace: ${label}..."
  cmux new-workspace --command "$cmd"

  # Set sidebar status label for this workspace (best-effort).
  cmux set-status "workspace" "$label" 2>/dev/null || true

  success "Workspace '${label}' opened."
}

# ─── open workspaces ──────────────────────────────────────────────────────────
echo ""
info "Opening briefcase server sessions in cmux..."
echo ""

# 1. Pi agent — attaches to the 'pi' tmux window on the server.
# Set TERM via the remote shell (attach-session's -E takes no argument), then
# attach if the session exists, otherwise create it.
open_workspace "pi" \
  "ssh ${SSH_ALIAS} -t 'export TERM=xterm-256color; tmux attach -t briefcase 2>/dev/null || tmux new-session -s briefcase -n pi pi'"

# 2. Shell — general-purpose server shell
open_workspace "shell" \
  "ssh ${SSH_ALIAS}"

# 3. Logs — placeholder for tailing logs or running monitoring
open_workspace "logs" \
  "ssh ${SSH_ALIAS} -t 'tail -f ~/.pi/agent/logs/*.log 2>/dev/null || echo \"No log files found. Use this tab for monitoring.\"'"

# ─── done ─────────────────────────────────────────────────────────────────────
echo ""
echo "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo "${BOLD}  Connected${RESET}"
echo "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""
echo "  Workspaces open in cmux:"
echo "  ${CYAN}pi${RESET}     — Pi agent session (tmux: briefcase)"
echo "  ${CYAN}shell${RESET}  — General server shell"
echo "  ${CYAN}logs${RESET}   — Log monitoring"
echo ""
echo "  ${DIM}Add more workspaces: cmux new-workspace${RESET}"
echo "  ${DIM}Send a command:      cmux send 'your-command' && cmux send-key enter${RESET}"
echo ""
echo "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""
