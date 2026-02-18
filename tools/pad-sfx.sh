#!/usr/bin/env bash
set -euo pipefail

ms="150"
recursive="0"

usage() {
  cat <<'EOF'
pad-sfx.sh: add front-padding (silence) to WAV files, in-place, keeping an .orig backup.

Usage:
  pad-sfx.sh [--ms N] [--recursive] <file-or-dir>...

Behavior:
  - For each *.wav (excluding *.orig.wav / *.wav.orig.wav), creates a backup:
      <name>.wav.orig.wav
    then rewrites <name>.wav with N ms of silence prepended.

Examples:
  pad-sfx.sh --ms 150 ~/.local/share/sounds/dictate
  pad-sfx.sh --ms 150 ~/.local/share/sounds/events
  pad-sfx.sh --ms 200 ~/.local/share/sounds/dictate/stop.wav
EOF
}

die() { echo "pad-sfx: $*" >&2; exit 2; }
need() { command -v "$1" >/dev/null 2>&1 || die "missing dependency: $1"; }

args=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --ms)
      shift || true
      [[ -n "${1:-}" ]] || die "--ms requires a value"
      [[ "$1" =~ ^[0-9]+([.][0-9]+)?$ ]] || die "--ms must be a number"
      ms="$1"
      ;;
    --recursive) recursive="1" ;;
    --) shift; break ;;
    -*) die "unknown flag: $1" ;;
    *) args+=("$1") ;;
  esac
  shift || true
done
args+=("$@")

[[ "${#args[@]}" -gt 0 ]] || { usage; exit 2; }

need ffmpeg

pad_one() {
  local f="$1"
  [[ -f "$f" ]] || return 0
  [[ "$f" == *.wav ]] || return 0
  [[ "$f" == *.orig.wav || "$f" == *.wav.orig.wav ]] && return 0

  local orig="${f}.orig.wav"
  if [[ ! -f "$orig" ]]; then
    mv -f "$f" "$orig"
  fi

  local tmp
  tmp="$(mktemp "${f}.tmp.XXXXXX.wav")"

  # Use adelay to prepend silence; a single value applies to all channels.
  # Keep output as PCM16 WAV for compatibility.
  ffmpeg -hide_banner -loglevel error -y \
    -i "$orig" \
    -af "adelay=${ms}:all=1" \
    -c:a pcm_s16le \
    "$tmp"

  mv -f "$tmp" "$f"
  printf "padded %s (+%sms)\n" "$f" "$ms"
}

expand_targets() {
  local p="$1"
  if [[ -d "$p" ]]; then
    if [[ "$recursive" == "1" ]]; then
      find "$p" -type f -name "*.wav" -print
    else
      find "$p" -maxdepth 1 -type f -name "*.wav" -print
    fi
  else
    printf "%s\n" "$p"
  fi
}

while [[ ${#args[@]} -gt 0 ]]; do
  t="${args[0]}"
  args=("${args[@]:1}")
  while IFS= read -r f; do
    pad_one "$f"
  done < <(expand_targets "$t")
done

