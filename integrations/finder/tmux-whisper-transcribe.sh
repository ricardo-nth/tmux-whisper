#!/usr/bin/env bash
# tmux-whisper.adapter: finder-transcribe
# tmux-whisper.adapter-version: 1
#
# Finder Quick Action handler: transcribe the selected audio files with
# `tmux-whisper transcribe`, write <name>.txt next to each one, copy the
# transcript to the clipboard, and post a notification.
#
# Automator/Shortcuts pass the selected files as arguments and run with a
# minimal PATH, so resolve the CLI explicitly.

set -uo pipefail

LOG="${DICTATE_FINDER_TRANSCRIBE_LOG:-/tmp/tmux-whisper-finder.log}"

# Fire-and-forget: the first notification from a Quick Action can wait on a
# macOS permission prompt, which must never hold up the transcription.
notify() {
  local message="$1"
  if [[ -n "${DICTATE_FINDER_NOTIFY_LOG:-}" ]]; then
    printf '%s\n' "$message" >>"$DICTATE_FINDER_NOTIFY_LOG"
    return 0
  fi
  message="${message//\\/\\\\}"
  message="${message//\"/\\\"}"
  /usr/bin/osascript -e "display notification \"$message\" with title \"Tmux Whisper\"" </dev/null >/dev/null 2>&1 &
}

resolve_bin() {
  local candidate
  for candidate in \
    "${DICTATE_BIN:-}" \
    "$HOME/.local/bin/tmux-whisper" \
    /opt/homebrew/bin/tmux-whisper \
    /usr/local/bin/tmux-whisper
  do
    [[ -n "$candidate" && -x "$candidate" ]] && { printf '%s\n' "$candidate"; return 0; }
  done
  return 1
}

if (( $# == 0 )); then
  notify "No files selected."
  exit 0
fi

BIN="$(resolve_bin)" || {
  notify "tmux-whisper not found. Install it first."
  exit 0
}

count=$#
if (( count == 1 )); then
  notify "Transcribing $(basename "$1")..."
else
  notify "Transcribing $count files..."
fi

{
  printf '\n[%s] transcribe %s file(s)\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$count"
} >>"$LOG" 2>/dev/null

if "$BIN" transcribe --beside --clipboard "$@" >>"$LOG" 2>&1; then
  if (( count == 1 )); then
    notify "Saved $(basename "${1%.*}").txt and copied it to the clipboard."
  else
    notify "Saved $count transcripts and copied them to the clipboard."
  fi
  exit 0
fi

reason="$(grep -E '^tmux-whisper: ' "$LOG" 2>/dev/null | tail -1 | sed 's/^tmux-whisper: //')"
notify "Transcription failed: ${reason:-see $LOG}"
# The notification reports the failure; a non-zero exit would also make Finder
# show a generic Automator error alert.
exit 0
