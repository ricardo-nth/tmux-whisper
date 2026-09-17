#!/usr/bin/env bash

# @raycast.schemaVersion 1
# @raycast.title Tmux Whisper Cancel
# @raycast.mode silent
# @raycast.packageName Tmux Whisper
# @raycast.description Cancel current recording (discard without pasting)

export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:${PATH:-/usr/bin:/bin}"

if [[ -f "$HOME/.zshenv" ]]; then
  source "$HOME/.zshenv"
fi

# Cancel any active inline recording
STATE_FILE="${DICTATE_INLINE_STATE_FILE:-/tmp/whisper-dictate-inline.state}"
TMUX_STATE="${DICTATE_STATE_FILE:-/tmp/whisper-dictate.state}"
CANCEL_FLAG="${DICTATE_CANCEL_FLAG:-/tmp/dictate-cancelled.flag}"
PROCESSING_DIR="${DICTATE_PROCESSING_DIR:-/tmp/dictate-processing}"
SOUNDS_DIR="${SOUNDS_DIR:-$HOME/.local/share/sounds}"

refresh_swiftbar() {
  local dictate_bin="${DICTATE_BIN:-$(command -v tmux-whisper 2>/dev/null || true)}"
  dictate_bin="${dictate_bin:-$HOME/.local/bin/tmux-whisper}"
  [[ -x "$dictate_bin" ]] || return 0
  "$dictate_bin" swiftbar refresh >/dev/null 2>&1 || true
}

cancel_recording() {
  local state_file="$1"
  
  if [[ ! -f "$state_file" ]]; then
    return 1
  fi
  
  # shellcheck disable=SC1090
  source "$state_file"
  rm -f "$state_file"
  
  # Stop recording process
  if [[ -n "${pid:-}" ]]; then
    kill -INT "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  fi
  
  # Remove wav file without transcribing
  if [[ -n "${wav:-}" && -f "$wav" ]]; then
    rm -f "$wav"
  fi
  
  # Clear any processing markers
  rm -f "$PROCESSING_DIR"/* 2>/dev/null || true
  
  # Set cancel flag for SwiftBar (shows cancel icon briefly)
  touch "$CANCEL_FLAG"
  refresh_swiftbar
  
  # Play cancel sound
  local cancel_sound="$SOUNDS_DIR/dictate/cancel.wav"
  # Raycast can terminate background children when the script exits; play synchronously.
  [[ -f "$cancel_sound" ]] && afplay "$cancel_sound" 2>/dev/null
  
  return 0
}

# Try inline state first, then tmux state
if cancel_recording "$STATE_FILE"; then
  echo "🚫 Cancelled inline recording"
elif cancel_recording "$TMUX_STATE"; then
  echo "🚫 Cancelled tmux recording"
else
  echo "Not recording"
fi
