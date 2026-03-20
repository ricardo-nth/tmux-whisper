#!/usr/bin/env bash

# @raycast.schemaVersion 1
# @raycast.title Tmux Whisper Inline
# @raycast.mode silent
# @raycast.packageName Tmux Whisper
# @raycast.description Toggle recording → paste into frontmost app

set -euo pipefail

LOG="/tmp/dictate-raycast-inline.log"
exec >> "$LOG" 2>&1
echo "=== $(date) ==="

export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:${PATH:-/usr/bin:/bin}"
export DICTATE_CLEAN=1
SWIFTBAR_PLUGIN_ID="tmux-whisper-status.0.2s.sh"

if [[ -f "$HOME/.zshenv" ]]; then
  source "$HOME/.zshenv"
fi

if [[ -z "${CEREBRAS_API_KEY:-}" && -f "${ZDOTDIR:-$HOME}/.zshrc" ]]; then
  eval "$(grep '^export CEREBRAS_API_KEY=' "${ZDOTDIR:-$HOME}/.zshrc" 2>/dev/null || true)"
fi

DICTATE_BIN="${DICTATE_BIN:-$(command -v tmux-whisper 2>/dev/null || true)}"
DICTATE_BIN="${DICTATE_BIN:-$HOME/.local/bin/tmux-whisper}"

notify_inline_error() {
  local msg="${1:-Tmux Whisper inline error}"
  local escaped="${msg//\"/\\\"}"
  echo "ERROR: $msg"
  command -v osascript >/dev/null 2>&1 || return 0
  osascript -e "display notification \"$escaped\" with title \"Tmux Whisper Inline\"" 2>/dev/null || true
}

refresh_swiftbar() {
  /usr/bin/open -g "swiftbar://refreshplugin?plugin=${SWIFTBAR_PLUGIN_ID}" 2>/dev/null || true
}

if [[ ! -x "$DICTATE_BIN" ]]; then
  notify_inline_error "Tmux Whisper binary not found. Install via brew or ./install.sh --force."
  exit 1
fi

if ! "$DICTATE_BIN" inline toggle; then
  notify_inline_error "Tmux Whisper inline failed. Check $LOG."
  refresh_swiftbar
  exit 1
fi

refresh_swiftbar
