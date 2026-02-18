#!/usr/bin/env bash

# <swiftbar.hideAbout>true</swiftbar.hideAbout>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
# <swiftbar.hideLastUpdated>true</swiftbar.hideLastUpdated>
# <swiftbar.hideDisablePlugin>true</swiftbar.hideDisablePlugin>

STATE_FILE="/tmp/whisper-dictate.state"
INLINE_STATE="/tmp/whisper-dictate-inline.state"
ERROR_FLAG="/tmp/dictate-error.flag"
PROCESSING_DIR="/tmp/dictate-processing"
PROCESSED_FLAG="/tmp/dictate-just-processed"
CANCEL_FLAG="/tmp/dictate-cancelled.flag"
PROCESSING_LONG_FLAG="/tmp/dictate-inline-processing-long.flag"
TMUX_JOBS_DIR="/tmp/dictate-tmux-jobs"

# Ensure $HOME is set (SwiftBar environment can be minimal).
if [[ -z "${HOME:-}" ]]; then
  HOME="$(eval echo "~$(id -un)")"
  export HOME
fi

# SwiftBar often runs with a minimal PATH; prefer Homebrew for python3/ffmpeg, etc.
export PATH="/opt/homebrew/bin:/usr/local/bin:${PATH:-/usr/bin:/bin}"

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
CONFIG_DIR="$XDG_CONFIG_HOME/dictate"
CONFIG_TOML="$CONFIG_DIR/config.toml"
MODE_FILE="$CONFIG_DIR/current-mode"
DICTATE_BIN="${DICTATE_BIN:-$(command -v dictate 2>/dev/null || true)}"
DICTATE_BIN="${DICTATE_BIN:-$HOME/.local/bin/dictate}"

# SwiftBar may run without interactive shell env; load API key similarly to Raycast path.
if [[ -z "${CEREBRAS_API_KEY:-}" && -f "${ZDOTDIR:-$HOME}/.zshrc" ]]; then
  eval "$(grep '^export CEREBRAS_API_KEY=' "${ZDOTDIR:-$HOME}/.zshrc" 2>/dev/null || true)"
fi

# Keep caches out of /tmp to avoid unpredictable OS cleanup causing slow (re)parsing.
CACHE_DIR="${SWIFTBAR_PLUGIN_CACHE_PATH:-/tmp}"
mkdir -p "$CACHE_DIR" 2>/dev/null || true
CONFIG_CACHE="$CACHE_DIR/dictate-config.cache"

shopt -s nullglob

safe_key() {
  printf "%s" "${1:-}" | sed -E 's/[^A-Za-z0-9_]/_/g'
}

short_path_tail() {
  local p="${1:-}"
  [[ -n "$p" ]] || return 0
  p="${p%/}"
  [[ -z "$p" ]] && { echo "/"; return 0; }
  local base parent
  base="$(basename "$p")"
  parent="$(basename "$(dirname "$p")")"
  if [[ "$parent" == "/" || "$parent" == "." || "$parent" == "$base" ]]; then
    echo "$base"
  else
    echo "$parent/$base"
  fi
}

# NOTE: SwiftBar runs this script frequently; flags are meant to be short-lived.
is_recent_file() {
  local f="${1:-}"
  local max_age_s="${2:-}"
  [[ -n "$f" && -n "$max_age_s" && -f "$f" ]] || return 1
  local now mtime age
  now="$(date +%s)"
  mtime="$(stat -f %m "$f" 2>/dev/null || echo 0)"
  age=$((now - mtime))
  [[ "$age" -le "$max_age_s" ]]
}

load_config() {
  command -v python3 >/dev/null 2>&1 || return 0

  local mtime="0"
  mtime="$(stat -f %m "$CONFIG_TOML" 2>/dev/null || echo 0)"
  if [[ -f "$CONFIG_CACHE" ]]; then
    # shellcheck disable=SC1090
    source "$CONFIG_CACHE" 2>/dev/null || true
    if [[ "${CFG_CACHE_MTIME:-}" == "$mtime" && -n "${CFG_AUDIO_SILENCE_TRIM:-}" && -n "${CFG_CLEAN_REPEATS_LEVEL:-}" && -n "${CFG_TMUX_PROCESS_SOUND:-}" ]]; then
      return 0
    fi
  fi

  local out
  out="$(
    python3 - "$CONFIG_TOML" <<'PYEOF' 2>/dev/null || true
import os, shlex, sys, tomllib

path = os.path.expanduser(sys.argv[1])
cfg = {}
if os.path.exists(path):
  with open(path, "rb") as f:
    cfg = tomllib.load(f) or {}

def get(path, default=None):
  cur = cfg
  for part in path.split("."):
    if not isinstance(cur, dict) or part not in cur:
      return default
    cur = cur[part]
  return cur

def safe_key(k: str) -> str:
  out = []
  for ch in k:
    out.append(ch if (ch.isalnum() or ch == "_") else "_")
  return "".join(out)

def b(v, default=False):
  if v is None:
    return default
  return bool(v)

post_enabled = "1" if b(get("postprocess.enabled", False), False) else "0"
autosend = "1" if b(get("inline.autosend", True), True) else "0"
whisper_model = str(get("whisper.model", "base"))

print(f"CFG_CACHE_MTIME={shlex.quote(str(int(os.path.getmtime(path)) if os.path.exists(path) else 0))}")
print(f"CFG_POSTPROCESS_ENABLED={shlex.quote(post_enabled)}")
print(f"CFG_INLINE_AUTOSEND={shlex.quote(autosend)}")
print(f"CFG_INLINE_PASTE_TARGET={shlex.quote(str(get('inline.paste_target', 'restore')))}")
print(f"CFG_WHISPER_MODEL={shlex.quote(whisper_model)}")
print(f"CFG_AUDIO_SOURCE={shlex.quote(str(get('audio.source', 'auto')))}")
print(f"CFG_AUDIO_DEVICE_NAME={shlex.quote(str(get('audio.device_name', '')))}")
print(f"CFG_AUDIO_MAC_NAME={shlex.quote(str(get('audio.mac_name', 'MacBook Air Microphone')))}")
print(f"CFG_AUDIO_IPHONE_NAME={shlex.quote(str(get('audio.iphone_name', '')))}")
print(f"CFG_AUDIO_SILENCE_TRIM={shlex.quote('1' if b(get('audio.silence_trim', False), False) else '0')}")
print(f"CFG_CLEAN_REPEATS_LEVEL={shlex.quote(str(get('clean.repeats_level', '1')))}")
print(f"CFG_TMUX_AUTOSEND={shlex.quote('1' if b(get('tmux.autosend', True), True) else '0')}")
print(f"CFG_TMUX_PASTE_TARGET={shlex.quote(str(get('tmux.paste_target', 'origin')))}")
print(f"CFG_TMUX_POSTPROCESS={shlex.quote('1' if b(get('tmux.postprocess', False), False) else '0')}")
print(f"CFG_TMUX_PROCESS_SOUND={shlex.quote('1' if b(get('tmux.process_sound', False), False) else '0')}")
print(f"CFG_TMUX_MODE={shlex.quote(str(get('tmux.mode', 'short')))}")
print(f"CFG_TMUX_MODEL={shlex.quote(str(get('tmux.model', 'base')))}")
print(f"CFG_TMUX_SEND_MODE={shlex.quote(str(get('tmux.send_mode', 'auto')))}")
print(f"CFG_DEBUG_KEEP_LOGS={shlex.quote('1' if b(get('debug.keep_logs', False), False) else '0')}")

icons = get("ui.icons", {}) or {}
if isinstance(icons, dict):
  for k, v in icons.items():
    print(f"CFG_ICON_{safe_key(str(k))}={shlex.quote(str(v))}")

keybinds = get("ui.keybinds", {}) or {}
if isinstance(keybinds, dict):
  for k, v in keybinds.items():
    print(f"CFG_KEYBIND_{safe_key(str(k))}={shlex.quote(str(v))}")
PYEOF
  )"

  if [[ -n "$out" ]]; then
    eval "$out"
    {
      echo "# Autogenerated cache for SwiftBar"
      echo "$out"
    } >"$CONFIG_CACHE".tmp 2>/dev/null && mv -f "$CONFIG_CACHE".tmp "$CONFIG_CACHE" 2>/dev/null || true
  fi
}

load_config

get_icon() {
  local key="$1"
  local fallback="$2"
  local safe var value
  safe="$(safe_key "$key")"
  var="CFG_ICON_${safe}"
  value="${!var:-}"
  [[ -n "$value" ]] && echo "$value" || echo "$fallback"
}

get_keybind() {
  local key="$1"
  local fallback="$2"
  local safe var value
  safe="$(safe_key "$key")"
  var="CFG_KEYBIND_${safe}"
  value="${!var:-}"
  [[ -n "$value" ]] && echo "$value" || echo "$fallback"
}

normalize_audio_source() {
  local src="${1:-auto}"
  src="$(printf "%s" "$src" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
  case "$src" in
    auto|external|mac|iphone|name) echo "$src" ;;
    *) echo "auto" ;;
  esac
}

audio_source_label() {
  local src
  src="$(normalize_audio_source "${1:-auto}")"
  case "$src" in
    auto) echo "auto (external -> mac -> iphone)" ;;
    external) echo "external mic" ;;
    mac) echo "mac built-in mic" ;;
    iphone) echo "iphone mic" ;;
    name) echo "named device" ;;
    *) echo "auto (external -> mac -> iphone)" ;;
  esac
}

load_audio_resolution_cache() {
  AUDIO_CACHE_NAME=""
  AUDIO_CACHE_MATCH=""
  AUDIO_CACHE_INDEX=""
  local cache_file="$CONFIG_DIR/.cache/audio-index.sh"
  [[ -f "$cache_file" ]] || return 1
  # shellcheck disable=SC1090
  source "$cache_file" 2>/dev/null || return 1
  AUDIO_CACHE_NAME="${CACHED_AUDIO_NAME:-}"
  AUDIO_CACHE_MATCH="${CACHED_AUDIO_MATCH:-}"
  AUDIO_CACHE_INDEX="${CACHED_AUDIO_INDEX:-}"
  [[ -n "$AUDIO_CACHE_INDEX" ]] || return 1
  return 0
}

canonical_mode_name() {
  local m="${1:-}"
  case "$m" in
    "") echo "short" ;;
    *) echo "$m" ;;
  esac
}

mode_to_dir_name() {
  local m
  m="$(canonical_mode_name "${1:-}")"
  echo "$m"
}

normalize_mode_name() {
  local mode
  mode="$(canonical_mode_name "${1:-}")"
  [[ -z "$mode" ]] && mode="short"
  if [[ -d "$CONFIG_DIR/modes/$(mode_to_dir_name "$mode")" ]]; then
    echo "$mode"
  else
    echo "short"
  fi
}

read_saved_mode() {
  if [[ -f "$MODE_FILE" ]]; then
    normalize_mode_name "$(cat "$MODE_FILE" 2>/dev/null || true)"
  else
    echo "short"
  fi
}

mode_exists() {
  local mode_name
  mode_name="$(normalize_mode_name "${1:-}")"
  [[ -d "$CONFIG_DIR/modes/$(mode_to_dir_name "$mode_name")" ]]
}

emit_inline_modes_menu() {
  local current_mode
  current_mode="$(normalize_mode_name "${1:-short}")"
  local mode_name
  for mode_name in short long; do
    mode_exists "$mode_name" || continue
    if [[ "$mode_name" == "$current_mode" ]]; then
      echo "-- ✓ $mode_name | bash=$DICTATE_BIN param1=mode param2=$mode_name terminal=false refresh=true"
    else
      echo "-- $mode_name | bash=$DICTATE_BIN param1=mode param2=$mode_name terminal=false refresh=true"
    fi
  done
}

emit_tmux_modes_menu() {
  local current_mode
  current_mode="$(normalize_mode_name "${1:-short}")"
  case "$current_mode" in
    short|long) ;;
    *) current_mode="short" ;;
  esac
  local mode_name
  for mode_name in short long; do
    mode_exists "$mode_name" || continue
    if [[ "$mode_name" == "$current_mode" ]]; then
      echo "-- ✓ $mode_name | bash=$DICTATE_BIN param1=tmux param2=mode param3=$mode_name terminal=false refresh=true"
    else
      echo "-- $mode_name | bash=$DICTATE_BIN param1=tmux param2=mode param3=$mode_name terminal=false refresh=true"
    fi
  done
}

# Count active processing jobs
count_processing() {
  if [[ -d "$PROCESSING_DIR" ]]; then
    local now count
    now="$(date +%s)"
    count=0
    local f line pid kind
    for f in "$PROCESSING_DIR"/*; do
      [[ -f "$f" ]] || continue

      pid=""
      kind=""
      line="$(head -n 1 "$f" 2>/dev/null || true)"
      if [[ "$line" =~ ^pid=([0-9]+)$ ]]; then
        pid="${BASH_REMATCH[1]}"
      elif [[ "$line" =~ ^[0-9]+$ ]]; then
        pid="$line"
      fi
      kind="$(sed -n 's/^kind=//p' "$f" 2>/dev/null | head -n 1 || true)"

      # Only show processing for inline flows (Raycast inline or `dictate inline`).
      # Still clean up stale markers for other kinds.
      local is_inline="0"
      if [[ "$kind" == "raycast-inline" || "$kind" == "inline" ]]; then
        is_inline="1"
      elif [[ "$(basename "$f")" == inline-* ]]; then
        is_inline="1"
      fi

      if [[ -n "$pid" ]]; then
        if kill -0 "$pid" 2>/dev/null; then
          [[ "$is_inline" == "1" ]] && count=$((count + 1))
          continue
        fi
        rm -f "$f" 2>/dev/null || true
        continue
      fi

      # If there's no pid, treat it as stale.
      rm -f "$f" 2>/dev/null || true
    done
    echo "$count"
  else
    echo "0"
  fi
}

# Count tmux jobs (recording/processing)
count_tmux_jobs() {
  local rec=0 proc=0
  [[ -d "$TMUX_JOBS_DIR" ]] || { echo "0 0"; return 0; }
  local now mtime age status marker_pid f
  now="$(date +%s)"
  for f in "$TMUX_JOBS_DIR"/*; do
    [[ -f "$f" ]] || continue
    mtime="$(stat -f %m "$f" 2>/dev/null || echo 0)"
    age=$((now - mtime))
    if [[ "$age" -gt 1800 ]]; then
      rm -f "$f" 2>/dev/null || true
      continue
    fi
    status="$(sed -n 's/^status=//p' "$f" 2>/dev/null | head -n 1 || true)"
    marker_pid="$(sed -n 's/^pid=//p' "$f" 2>/dev/null | head -n 1 || true)"
    case "$status" in
      recording|processing)
        if [[ -z "$marker_pid" || ! "$marker_pid" =~ ^[0-9]+$ ]]; then
          rm -f "$f" 2>/dev/null || true
          continue
        fi
        if ! kill -0 "$marker_pid" 2>/dev/null; then
          rm -f "$f" 2>/dev/null || true
          continue
        fi
        ;;
    esac
    case "$status" in
      recording) rec=$((rec + 1)) ;;
      processing) proc=$((proc + 1)) ;;
      *) ;;
    esac
  done
  echo "$rec $proc"
}

# Check if just processed (within last 1 second)
just_processed() {
  if [[ -f "$PROCESSED_FLAG" ]]; then
    if is_recent_file "$PROCESSED_FLAG" 1; then
      return 0
    fi
    rm -f "$PROCESSED_FLAG" 2>/dev/null || true
  fi
  return 1
}

# Check if just cancelled (within last 1 second)
just_cancelled() {
  if [[ -f "$CANCEL_FLAG" ]]; then
    if is_recent_file "$CANCEL_FLAG" 1; then
      return 0
    fi
    rm -f "$CANCEL_FLAG" 2>/dev/null || true
  fi
  return 1
}

# Mode icon from config
mode_icon() {
  local mode="$1"
  case "$mode" in
    base) get_icon "base" "⚪" ;;
    short) get_icon "short" "💻" ;;
    email) get_icon "email" "📧" ;;
    chat) get_icon "chat" "💬" ;;
    long) get_icon "long" "📝" ;;
    linkedin) get_icon "linkedin" "in" ;;
    twitter) get_icon "twitter" "𝕏" ;;
    *) get_icon "$mode" "${mode:0:2}" ;;
  esac
}

# State icons from config
ICON_RECORDING="$(get_icon "recording" "🔴")"
ICON_PROCESSING="$(get_icon "processing" "⏳")"
ICON_READY="$(get_icon "ready" "🎙️")"
ICON_ERROR="$(get_icon "error" "⚠️")"
ICON_CANCEL="$(get_icon "cancel" "🚫")"

# Check for recent cancel (show briefly)
if just_cancelled; then
  echo "$ICON_CANCEL"
  echo "---"
  echo "Cancelled | color=orange"
  exit 0
fi

# Check for recent error
if [[ -f "$ERROR_FLAG" ]]; then
  if is_recent_file "$ERROR_FLAG" 10; then
    echo "$ICON_ERROR"
    echo "---"
    echo "Error occurred | color=red"
    echo "Check: /tmp/dictate-raycast-inline.log | size=11"
    echo "---"
    echo "Clear Error | bash=/bin/rm param1=-f param2=$ERROR_FLAG terminal=false refresh=true"
    exit 0
  else
    rm -f "$ERROR_FLAG"
  fi
fi

saved_mode="$(read_saved_mode)"

# Determine mode icon display
current_mode_icon="$(mode_icon "$saved_mode")"
mode_display="$saved_mode"

# Check if recording (either tmux or inline mode)
if [[ -f "$STATE_FILE" ]] || [[ -f "$INLINE_STATE" ]]; then
  source "$STATE_FILE" 2>/dev/null || source "$INLINE_STATE" 2>/dev/null
  # SwiftBar may run before the recording process is fully “visible”; use a short
  # grace window for freshly-written state files so the icon flips immediately.
  state_seen="$STATE_FILE"
  [[ -f "$INLINE_STATE" ]] && state_seen="$INLINE_STATE"
  if kill -0 "$pid" 2>/dev/null || is_recent_file "$state_seen" 2; then
    # Recording state
    echo "$ICON_RECORDING $current_mode_icon"
    echo "---"
    echo "Recording... | color=red"
    echo "Mode: $mode_display | size=11"
    if [[ -n "$target_pane" ]]; then
      target_label="$target_pane"
      if command -v tmux >/dev/null 2>&1; then
        pane_title="$(tmux display-message -p -t "$target_pane" '#{pane_title}' 2>/dev/null || true)"
        pane_path="$(tmux display-message -p -t "$target_pane" '#{pane_current_path}' 2>/dev/null || true)"
        pane_path="$(short_path_tail "$pane_path")"
        [[ -n "$pane_title" ]] && target_label="$target_label · $pane_title"
        [[ -n "$pane_path" ]] && target_label="$target_label · $pane_path"
      fi
      echo "Target: tmux $target_label | size=11"
    else
      echo "Target: inline | size=11"
    fi
    echo "---"
    echo "Stop Recording | bash=$DICTATE_BIN param1=stop terminal=false refresh=true"
    echo "Cancel Recording | bash=$DICTATE_BIN param1=cancel terminal=false refresh=true"
    exit 0
  else
    # Stale state file with no live pid; clean it up.
    rm -f "$STATE_FILE" "$INLINE_STATE" 2>/dev/null || true
  fi
fi

# Processing count can be mildly expensive; avoid unless needed.
processing_count="$(count_processing)"

# Check if processing (inline-only, threshold-based).
processing_long="0"
if [[ -f "$PROCESSING_LONG_FLAG" ]]; then
  if [[ "$processing_count" -gt 0 ]]; then
    processing_long="1"
  else
    rm -f "$PROCESSING_LONG_FLAG" 2>/dev/null || true
  fi
fi

if [[ "$processing_long" == "1" ]]; then
  current_mode="$saved_mode"
  echo "$ICON_PROCESSING $current_mode_icon"
  echo "---"
  echo "Processing ($processing_count) | color=orange"
  echo "Mode: $mode_display | size=11"
  echo "---"
  echo "Inline"
  echo "-- Modes"
  emit_inline_modes_menu "$current_mode"
  exit 0
fi

# “Just processed” should not hold the ⏳ icon; show Ready icon with a brief status.
recently_processed="0"
if just_processed; then
  recently_processed="1"
fi

# Ready state
current_mode="$saved_mode"

# Ready state
echo "$ICON_READY $current_mode_icon"
echo "---"
if [[ "$recently_processed" == "1" ]]; then
  echo "Just processed | color=orange"
else
  echo "Ready | color=gray"
fi
audio_source_val="$(normalize_audio_source "${DICTATE_AUDIO_SOURCE:-${CFG_AUDIO_SOURCE:-auto}}")"
audio_source_display="$(audio_source_label "$audio_source_val")"
audio_active_label="unresolved"
if [[ -n "${DICTATE_AUDIO_INDEX:-}" ]]; then
  audio_active_label="env index ${DICTATE_AUDIO_INDEX}"
elif load_audio_resolution_cache; then
  audio_active_label="${AUDIO_CACHE_NAME:-index ${AUDIO_CACHE_INDEX}}"
  [[ -n "${AUDIO_CACHE_MATCH:-}" ]] && audio_active_label="$audio_active_label (${AUDIO_CACHE_MATCH})"
fi
echo "Mode: $mode_display"
echo "Mic source: $audio_source_display | size=11"
echo "Mic active: $audio_active_label | size=11 color=gray"
read -r tmux_rec tmux_proc < <(count_tmux_jobs)
if [[ "${tmux_rec:-0}" -gt 0 || "${tmux_proc:-0}" -gt 0 ]]; then
  echo "TMUX queue: 🔴 ${tmux_rec:-0} · ⏳ ${tmux_proc:-0} | size=11"
fi
echo "---"
echo "Inline"
echo "-- Modes"
emit_inline_modes_menu "$current_mode"
echo "-- Settings"
postprocess_val="${CFG_POSTPROCESS_ENABLED:-0}"
key_set="0"
[[ -n "${CEREBRAS_API_KEY:-}" ]] && key_set="1"
if [[ "$postprocess_val" == "1" && "$key_set" == "1" ]]; then
  postprocess_label="ON"
elif [[ "$postprocess_val" == "1" ]]; then
  postprocess_label="OFF (no key)"
else
  postprocess_label="OFF"
fi
autosend_val="${CFG_INLINE_AUTOSEND:-1}"
[[ -z "$autosend_val" ]] && autosend_val="1"
[[ "$autosend_val" == "1" ]] && autosend_label="ON" || autosend_label="OFF"
tmux_postprocess_val="${CFG_TMUX_POSTPROCESS:-0}"
if [[ "$tmux_postprocess_val" == "1" && "$key_set" == "1" ]]; then
  tmux_postprocess_label="ON"
elif [[ "$tmux_postprocess_val" == "1" ]]; then
  tmux_postprocess_label="OFF (no key)"
else
  tmux_postprocess_label="OFF"
fi
tmux_process_sound_val="${CFG_TMUX_PROCESS_SOUND:-0}"
[[ "$tmux_process_sound_val" == "1" ]] && tmux_process_sound_label="ON" || tmux_process_sound_label="OFF"
tmux_autosend_val="${CFG_TMUX_AUTOSEND:-1}"
[[ -z "$tmux_autosend_val" ]] && tmux_autosend_val="1"
[[ "$tmux_autosend_val" == "1" ]] && tmux_autosend_label="ON" || tmux_autosend_label="OFF"
inline_target_val="${CFG_INLINE_PASTE_TARGET:-restore}"
if [[ "$inline_target_val" == "current" ]]; then
  inline_target_val="current"
else
  inline_target_val="origin"
fi
tmux_target_val="${CFG_TMUX_PASTE_TARGET:-origin}"
tmux_send_mode_val="${DICTATE_TMUX_SEND_MODE:-${CFG_TMUX_SEND_MODE:-auto}}"
case "$tmux_send_mode_val" in
  auto|enter|codex) ;;
  *) tmux_send_mode_val="auto" ;;
esac
keep_logs_val="${DICTATE_KEEP_LOGS:-${CFG_DEBUG_KEEP_LOGS:-0}}"
[[ "$keep_logs_val" == "1" ]] && keep_logs_label="ON" || keep_logs_label="OFF"
silence_trim_val="${CFG_AUDIO_SILENCE_TRIM:-0}"
[[ "$silence_trim_val" == "1" ]] && silence_trim_label="ON" || silence_trim_label="OFF"
repeats_level_val="${CFG_CLEAN_REPEATS_LEVEL:-1}"
model_id="${CFG_WHISPER_MODEL:-base}"
model_base="$model_id"
if [[ "$model_id" == */* ]]; then
  model_base="$(basename "$model_id")"
elif [[ "$model_id" == *.bin ]]; then
  model_base="$model_id"
fi
# Toggle commands (dictate uses on/off)
autosend_toggle_val=$([[ "$autosend_val" == "1" ]] && echo "off" || echo "on")
postprocess_toggle_val=$([[ "$postprocess_val" == "1" ]] && echo "off" || echo "on")
tmux_autosend_toggle_val=$([[ "$tmux_autosend_val" == "1" ]] && echo "off" || echo "on")
tmux_postprocess_toggle_val=$([[ "$tmux_postprocess_val" == "1" ]] && echo "off" || echo "on")
tmux_process_sound_toggle_val=$([[ "$tmux_process_sound_val" == "1" ]] && echo "off" || echo "on")
tmux_target_toggle_val=$([[ "$tmux_target_val" == "origin" ]] && echo "current" || echo "origin")
inline_target_toggle_val=$([[ "$inline_target_val" == "origin" ]] && echo "current" || echo "origin")
keep_logs_toggle_val=$([[ "$keep_logs_val" == "1" ]] && echo "off" || echo "on")
silence_trim_toggle_val=$([[ "$silence_trim_val" == "1" ]] && echo "off" || echo "on")

echo "-- Postprocess: $postprocess_label | bash=$DICTATE_BIN param1=postprocess param2=$postprocess_toggle_val terminal=false refresh=true"
echo "-- Autosend: $autosend_label | bash=$DICTATE_BIN param1=autosend param2=$autosend_toggle_val terminal=false refresh=true"
model_display="$model_base"
case "$model_base" in
  ggml-tiny.en.bin) model_display="base" ;;
  ggml-base.en.bin) model_display="base" ;;
  ggml-small.en.bin) model_display="small" ;;
  ggml-large-v3-turbo-q5_0.bin) model_display="turbo" ;;
  ggml-large-v3-turbo-q8_0.bin|ggml-large-v3-turbo.bin) model_display="turbo" ;;
  base|small|turbo) model_display="$model_base" ;;
  *) model_display="base" ;;
esac
echo "-- Models"
for m in base small turbo; do
  if [[ "$m" == "$model_display" ]]; then
    echo "-- ✓ $m | bash=$DICTATE_BIN param1=model param2=$m terminal=false refresh=true"
  else
    echo "-- $m | bash=$DICTATE_BIN param1=model param2=$m terminal=false refresh=true"
  fi
done
echo "Tmux"
echo "-- Modes"
emit_tmux_modes_menu "$(normalize_mode_name "${CFG_TMUX_MODE:-short}")"
echo "-- Settings"
echo "-- Postprocess: $tmux_postprocess_label | bash=$DICTATE_BIN param1=tmux param2=postprocess param3=$tmux_postprocess_toggle_val terminal=false refresh=true"
echo "-- Process sound: $tmux_process_sound_label | bash=$DICTATE_BIN param1=tmux param2=process-sound param3=$tmux_process_sound_toggle_val terminal=false refresh=true"
echo "-- Autosend: $tmux_autosend_label | bash=$DICTATE_BIN param1=tmux param2=autosend param3=$tmux_autosend_toggle_val terminal=false refresh=true"
echo "-- Target: $tmux_target_val | bash=$DICTATE_BIN param1=tmux param2=target param3=$tmux_target_toggle_val terminal=false refresh=true"

tmux_model_id="${CFG_TMUX_MODEL:-${CFG_WHISPER_MODEL:-base}}"
tmux_model_base="$tmux_model_id"
if [[ "$tmux_model_id" == */* ]]; then
  tmux_model_base="$(basename "$tmux_model_id")"
elif [[ "$tmux_model_id" == *.bin ]]; then
  tmux_model_base="$tmux_model_id"
fi
tmux_model_display="$tmux_model_base"
case "$tmux_model_base" in
  ggml-tiny.en.bin) tmux_model_display="base" ;;
  ggml-base.en.bin) tmux_model_display="base" ;;
  ggml-small.en.bin) tmux_model_display="small" ;;
  ggml-large-v3-turbo-q5_0.bin) tmux_model_display="turbo" ;;
  ggml-large-v3-turbo-q8_0.bin|ggml-large-v3-turbo.bin) tmux_model_display="turbo" ;;
  base|small|turbo) tmux_model_display="$tmux_model_base" ;;
  *) tmux_model_display="base" ;;
esac
echo "-- Models"
for m in base small turbo; do
  if [[ "$m" == "$tmux_model_display" ]]; then
    echo "-- ✓ $m | bash=$DICTATE_BIN param1=tmux param2=model param3=$m terminal=false refresh=true"
  else
    echo "-- $m | bash=$DICTATE_BIN param1=tmux param2=model param3=$m terminal=false refresh=true"
  fi
done
echo "Advanced"
echo "-- Global | color=gray"
echo "-- Keep logs: $keep_logs_label | bash=$DICTATE_BIN param1=keep-logs param2=$keep_logs_toggle_val terminal=false refresh=true"
echo "-- Inline | color=gray"
echo "-- Paste target: $inline_target_val | bash=$DICTATE_BIN param1=target param2=$inline_target_toggle_val terminal=false refresh=true"
echo "-- Silence trim: $silence_trim_label | bash=$DICTATE_BIN param1=silence-trim param2=$silence_trim_toggle_val terminal=false refresh=true"
echo "-- Repeats level"
for lvl in 0 1 2; do
  if [[ "$lvl" == "$repeats_level_val" ]]; then
    echo "---- ✓ $lvl | bash=$DICTATE_BIN param1=repeats param2=$lvl terminal=false refresh=true"
  else
    echo "---- $lvl | bash=$DICTATE_BIN param1=repeats param2=$lvl terminal=false refresh=true"
  fi
done
echo "-- Tmux | color=gray"
echo "-- Send mode"
if [[ "auto" == "$tmux_send_mode_val" ]]; then
  echo "---- ✓ auto (detect Codex) | bash=$DICTATE_BIN param1=tmux param2=send-mode param3=auto terminal=false refresh=true"
else
  echo "---- auto (detect Codex) | bash=$DICTATE_BIN param1=tmux param2=send-mode param3=auto terminal=false refresh=true"
fi
if [[ "enter" == "$tmux_send_mode_val" ]]; then
  echo "---- ✓ enter (always Enter) | bash=$DICTATE_BIN param1=tmux param2=send-mode param3=enter terminal=false refresh=true"
else
  echo "---- enter (always Enter) | bash=$DICTATE_BIN param1=tmux param2=send-mode param3=enter terminal=false refresh=true"
fi
if [[ "codex" == "$tmux_send_mode_val" ]]; then
  echo "---- ✓ codex (Tab+Enter) | bash=$DICTATE_BIN param1=tmux param2=send-mode param3=codex terminal=false refresh=true"
else
  echo "---- codex (Tab+Enter) | bash=$DICTATE_BIN param1=tmux param2=send-mode param3=codex terminal=false refresh=true"
fi
echo "Mic src"
if [[ "$audio_source_val" == "auto" ]]; then
  echo "-- ✓ auto | bash=$DICTATE_BIN param1=device param2=source param3=auto terminal=false refresh=true"
else
  echo "-- auto | bash=$DICTATE_BIN param1=device param2=source param3=auto terminal=false refresh=true"
fi
if [[ "$audio_source_val" == "mac" ]]; then
  echo "-- ✓ mac | bash=$DICTATE_BIN param1=device param2=source param3=mac terminal=false refresh=true"
else
  echo "-- mac | bash=$DICTATE_BIN param1=device param2=source param3=mac terminal=false refresh=true"
fi
if [[ "$audio_source_val" == "external" ]]; then
  echo "-- ✓ external | bash=$DICTATE_BIN param1=device param2=source param3=external terminal=false refresh=true"
else
  echo "-- external | bash=$DICTATE_BIN param1=device param2=source param3=external terminal=false refresh=true"
fi
if [[ "$audio_source_val" == "iphone" ]]; then
  echo "-- ✓ iphone | bash=$DICTATE_BIN param1=device param2=source param3=iphone terminal=false refresh=true"
else
  echo "-- iphone | bash=$DICTATE_BIN param1=device param2=source param3=iphone terminal=false refresh=true"
fi
echo "---"
TMUX_KEY="$(get_keybind "tmux" "F12")"
INLINE_KEY="$(get_keybind "inline" "F17")"
echo "$TMUX_KEY tmux · $INLINE_KEY inline | size=11 color=gray"
