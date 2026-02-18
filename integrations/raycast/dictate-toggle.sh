#!/usr/bin/env bash

# @raycast.schemaVersion 1
# @raycast.title Dictate Toggle (tmux)
# @raycast.mode silent
# @raycast.packageName Dictate
# @raycast.description Toggle recording → paste+Enter into tmux pane

export PATH="/opt/homebrew/bin:$PATH"
export DICTATE_CLEAN=1
SWIFTBAR_PLUGIN_ID="dictate-status.0.2s.sh"

if [[ -f "$HOME/.zshenv" ]]; then
  # Load XDG vars + SOUNDS_DIR for Raycast environment
  source "$HOME/.zshenv"
fi

# Raycast often runs without interactive shell env; load API key similarly
# to inline/SwiftBar paths so tmux postprocess can run reliably.
if [[ -z "${CEREBRAS_API_KEY:-}" && -f "${ZDOTDIR:-$HOME}/.zshrc" ]]; then
  eval "$(grep '^export CEREBRAS_API_KEY=' "${ZDOTDIR:-$HOME}/.zshrc" 2>/dev/null || true)"
fi

DICTATE_SOUNDS_DIR="${SOUNDS_DIR:-}/dictate"
CONFIG_TOML="$HOME/.config/dictate/config.toml"

refresh_swiftbar() {
  /usr/bin/open -g "swiftbar://refreshplugin?plugin=${SWIFTBAR_PLUGIN_ID}" 2>/dev/null || true
}

expand_sound_path() {
  local p="${1:-}"
  [[ -n "$p" ]] || return 0
  if [[ "$p" == "~"* ]]; then
    p="$HOME${p:1}"
  fi
  if [[ -n "${SOUNDS_DIR:-}" ]]; then
    p="${p//\$\{SOUNDS_DIR\}/$SOUNDS_DIR}"
    p="${p//\$SOUNDS_DIR/$SOUNDS_DIR}"
  fi
  printf "%s" "$p"
}

load_config_sounds() {
  command -v python3 >/dev/null 2>&1 || return 0
  [[ -f "$CONFIG_TOML" ]] || return 0
  eval "$(
    python3 - "$CONFIG_TOML" <<'PYEOF'
import os, shlex, sys, tomllib

path = os.path.expanduser(sys.argv[1])
with open(path, "rb") as f:
  cfg = tomllib.load(f) or {}

def get_raw(path, default=None):
  cur = cfg
  for part in path.split("."):
    if not isinstance(cur, dict) or part not in cur:
      return default
    cur = cur[part]
  return cur

def get_str(path, default=""):
  v = get_raw(path, default)
  return "" if v is None else str(v)

def b(v, default=True):
  if v is None:
    return default
  if isinstance(v, bool):
    return v
  s = str(v).strip().lower()
  if s in ("1", "true", "yes", "on"):
    return True
  if s in ("0", "false", "no", "off"):
    return False
  return default

out = {
  "CFG_AUDIO_SOUNDS_START": get_str("audio.sounds.start", ""),
  "CFG_AUDIO_SOUNDS_STOP": get_str("audio.sounds.stop", ""),
  "CFG_AUDIO_SOUNDS_ENABLED": "1" if b(get_raw("audio.sounds.enabled", True), True) else "0",
  "CFG_AUDIO_SOUNDS_START_ENABLED": "1" if b(get_raw("audio.sounds.start_enabled", True), True) else "0",
  "CFG_AUDIO_SOUNDS_STOP_ENABLED": "1" if b(get_raw("audio.sounds.stop_enabled", True), True) else "0",
}

for k, v in out.items():
  print(f"{k}={shlex.quote(v)}")
PYEOF
  )"
}

sound_path() {
  local event="${1:-}"
  local cfg=""
  [[ "${CFG_AUDIO_SOUNDS_ENABLED:-1}" == "1" ]] || return 0
  case "$event" in
    start)
      [[ "${CFG_AUDIO_SOUNDS_START_ENABLED:-1}" == "1" ]] || return 0
      cfg="${CFG_AUDIO_SOUNDS_START:-}"
      ;;
    stop)
      [[ "${CFG_AUDIO_SOUNDS_STOP_ENABLED:-1}" == "1" ]] || return 0
      cfg="${CFG_AUDIO_SOUNDS_STOP:-}"
      ;;
    *) return 0 ;;
  esac

  if [[ -n "$cfg" ]]; then
    cfg="$(expand_sound_path "$cfg")"
  else
    cfg="$DICTATE_SOUNDS_DIR/$event.wav"
  fi

  [[ -f "$cfg" ]] && printf "%s" "$cfg"
}

load_config_sounds

STATE_FILE="/tmp/whisper-dictate.state"

if ! tmux list-sessions &>/dev/null; then
  osascript -e 'display notification "No tmux session running" with title "Dictate" sound name "Basso"'
  exit 1
fi

PANE="$(tmux display-message -p '#{pane_id}' 2>/dev/null || tmux list-panes -F '#{pane_id}' | head -1)"
export DICTATE_TARGET_PANE="$PANE"

if [[ -f "$STATE_FILE" ]]; then
  # Stopping - just play sound
  $HOME/.local/bin/dictate toggle 2>/tmp/dictate-raycast.log
  refresh_swiftbar
  # Stop sound is played by Dictate after transcription/paste completes.
else
  # Starting - just play sound
  $HOME/.local/bin/dictate toggle 2>/tmp/dictate-raycast.log
  refresh_swiftbar
  p="$(sound_path start)"
  # Raycast can terminate background children when the script exits; play synchronously.
  [[ -n "$p" ]] && afplay "$p" 2>/dev/null
fi
