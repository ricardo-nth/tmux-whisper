#!/usr/bin/env bash

# @raycast.schemaVersion 1
# @raycast.title Tmux Whisper Inline
# @raycast.mode silent
# @raycast.packageName Tmux Whisper
# @raycast.description Toggle recording → paste into frontmost app

LOG="/tmp/dictate-raycast-inline.log"
exec >> "$LOG" 2>&1
echo "=== $(date) ==="

export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:${PATH:-/usr/bin:/bin}"
export DICTATE_CLEAN=1

if [[ -f "$HOME/.zshenv" ]]; then
  # Load XDG vars + SOUNDS_DIR for Raycast environment
  source "$HOME/.zshenv"
fi

# Load API keys from .zshrc if not already set (Raycast doesn't source interactive shell config)
if [[ -z "${CEREBRAS_API_KEY:-}" && -f "${ZDOTDIR:-$HOME}/.zshrc" ]]; then
  # Extract just the CEREBRAS_API_KEY export, avoiding interactive-only code
  eval "$(grep '^export CEREBRAS_API_KEY=' "${ZDOTDIR:-$HOME}/.zshrc" 2>/dev/null || true)"
fi
DICTATE_SOUNDS_DIR="${SOUNDS_DIR:-}/dictate"

notify_inline_error() {
  local msg="${1:-Tmux Whisper inline error}"
  local escaped="${msg//\"/\\\"}"
  echo "ERROR: $msg"
  command -v osascript >/dev/null 2>&1 || return 0
  osascript -e "display notification \"$escaped\" with title \"Tmux Whisper Inline\"" 2>/dev/null || true
}

STATE_FILE="/tmp/whisper-dictate-inline.state"
PROCESSING_DIR="/tmp/dictate-processing"
SWIFTBAR_PLUGIN_ID="tmux-whisper-status.0.2s.sh"
PROCESSING_THRESHOLD_S="0.35"
PROCESSING_LONG_FLAG="/tmp/dictate-inline-processing-long.flag"
CONFIG_DIR="$HOME/.config/dictate"
MODE_FILE="$CONFIG_DIR/current-mode"

CONFIG_TOML="$CONFIG_DIR/config.toml"
DICTATE_LIB_PATH="${DICTATE_LIB_PATH:-$HOME/.local/bin/dictate-lib.sh}"

if [[ ! -r "$DICTATE_LIB_PATH" ]]; then
  if command -v dictate-lib.sh >/dev/null 2>&1; then
    DICTATE_LIB_PATH="$(command -v dictate-lib.sh)"
  else
    dictate_bin_path="$(command -v tmux-whisper 2>/dev/null || true)"
    if [[ -n "$dictate_bin_path" ]]; then
      maybe_lib="$(cd "$(dirname "$dictate_bin_path")" && pwd)/dictate-lib.sh"
      [[ -r "$maybe_lib" ]] && DICTATE_LIB_PATH="$maybe_lib"
    fi
  fi
fi

if [[ ! -r "$DICTATE_LIB_PATH" ]]; then
  notify_inline_error "Missing dictate-lib.sh. Reinstall with brew or ./install.sh --force."
  exit 1
fi
# shellcheck disable=SC1090
source "$DICTATE_LIB_PATH"

for dep in ffmpeg whisper-cli; do
  if ! command -v "$dep" >/dev/null 2>&1; then
    notify_inline_error "Missing dependency: $dep"
    echo "error" >/tmp/dictate-error.flag
    exit 1
  fi
done

TRACE="${DICTATE_RAYCAST_TRACE:-0}"
now_ms() {
  perl -MTime::HiRes=time -e 'printf "%.0f\n", time()*1000'
}
sleep_ms() {
  local ms="${1:-0}"
  [[ "$ms" =~ ^[0-9]+$ ]] || ms=0
  if (( ms <= 0 )); then
    return 0
  fi
  local sec=$((ms / 1000))
  local rem=$((ms % 1000))
  sleep "${sec}.$(printf '%03d' "$rem")"
}

bool_is_on() {
  local raw="${1:-}"
  local v
  v="$(printf "%s" "$raw" | tr '[:upper:]' '[:lower:]')"
  case "$v" in
    1|true|yes|on) return 0 ;;
    *) return 1 ;;
  esac
}

trace() {
  [[ "$TRACE" == "1" ]] || return 0
  echo "[trace] $*"
}
SCRIPT_STARTED_MS="$(now_ms)"
STARTUP_AUDIO_MS=0
STARTUP_AUDIO_SOURCE="(none)"
STARTUP_FFMPEG_LIVE_MS=0
STARTUP_TARGET_MS=0
STARTUP_TOTAL_MS=0

# Cache resolved audio index to avoid paying `ffmpeg -list_devices` cost on every hotkey press.
CACHE_DIR="$CONFIG_DIR/.cache"
AUDIO_INDEX_CACHE="$CACHE_DIR/audio-index.sh"

load_audio_index_cache() {
  [[ -f "$AUDIO_INDEX_CACHE" ]] || return 1
  # shellcheck disable=SC1090
  source "$AUDIO_INDEX_CACHE" 2>/dev/null || return 1
  if [[ -z "${CACHED_AUDIO_KEY:-}" && -n "${CACHED_AUDIO_NAME:-}" ]]; then
    CACHED_AUDIO_KEY="$CACHED_AUDIO_NAME"
  fi
  [[ -n "${CACHED_AUDIO_KEY:-}" && -n "${CACHED_AUDIO_INDEX:-}" ]] || return 1
  return 0
}

write_audio_index_cache() {
  local key="${1:-}"
  local idx="${2:-}"
  local name="${3:-}"
  local match="${4:-}"
  [[ -n "$key" && -n "$idx" ]] || return 0

  mkdir -p "$CACHE_DIR" 2>/dev/null || return 0
  local tmp
  tmp="$(mktemp "$CACHE_DIR/.audio-index.XXXXXX" 2>/dev/null || true)"
  [[ -n "$tmp" ]] || return 0

  umask 077
  printf 'CACHED_AUDIO_KEY=%q\nCACHED_AUDIO_NAME=%q\nCACHED_AUDIO_MATCH=%q\nCACHED_AUDIO_INDEX=%q\nCACHED_AUDIO_AT=%q\n' \
    "$key" "$name" "$match" "$idx" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" > "$tmp" 2>/dev/null || {
    rm -f "$tmp" 2>/dev/null || true
    return 0
  }
  mv -f "$tmp" "$AUDIO_INDEX_CACHE" 2>/dev/null || true
}

clear_audio_index_cache() {
  rm -f "$AUDIO_INDEX_CACHE" 2>/dev/null || true
}

load_config() {
  command -v python3 >/dev/null 2>&1 || return 0
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

def b(v, default=False):
  if v is None:
    return default
  return bool(v)

print(f"CFG_WHISPER_MODELS_DIR={shlex.quote(str(get('whisper.models_dir', '')))}")
print(f"CFG_WHISPER_MODEL={shlex.quote(str(get('whisper.model', 'base')))}")
print(f"CFG_WHISPER_THREADS={shlex.quote(str(get('whisper.threads', '5')))}")
print(f"CFG_WHISPER_BEAM_SIZE={shlex.quote(str(get('whisper.beam_size', '1')))}")
print(f"CFG_WHISPER_BEST_OF={shlex.quote(str(get('whisper.best_of', '1')))}")
print(f"CFG_AUDIO_SILENCE_TRIM={shlex.quote('1' if b(get('audio.silence_trim', False), False) else '0')}")
print(f"CFG_AUDIO_SILENCE_TRIM_MODE={shlex.quote(str(get('audio.silence_trim_mode', 'edges')))}")
print(f"CFG_AUDIO_SILENCE_THRESHOLD_DB={shlex.quote(str(get('audio.silence_threshold_db', '-60')))}")
print(f"CFG_AUDIO_SILENCE_MIN_MS={shlex.quote(str(get('audio.silence_min_ms', '250')))}")
print(f"CFG_AUDIO_SILENCE_KEEP_MS={shlex.quote(str(get('audio.silence_keep_ms', '50')))}")
print(f"CFG_CLEAN_REPEATS_LEVEL={shlex.quote(str(get('clean.repeats_level', '1')))}")
print(f"CFG_WHISPER_VAD_ENABLED={shlex.quote('1' if b(get('whisper.vad', False), False) else '0')}")
print(f"CFG_WHISPER_VAD_MODEL={shlex.quote(str(get('whisper.vad_model', '')))}")
print(f"CFG_WHISPER_VAD_THRESHOLD={shlex.quote(str(get('whisper.vad_threshold', '0.5')))}")
print(f"CFG_WHISPER_VAD_MIN_SPEECH_MS={shlex.quote(str(get('whisper.vad_min_speech_ms', '250')))}")
print(f"CFG_WHISPER_VAD_MIN_SILENCE_MS={shlex.quote(str(get('whisper.vad_min_silence_ms', '100')))}")
print(f"CFG_WHISPER_VAD_SPEECH_PAD_MS={shlex.quote(str(get('whisper.vad_speech_pad_ms', '30')))}")
print(f"CFG_AUDIO_SOURCE={shlex.quote(str(get('audio.source', 'auto')))}")
print(f"CFG_AUDIO_DEVICE_NAME={shlex.quote(str(get('audio.device_name', 'MacBook Air Microphone')))}")
print(f"CFG_AUDIO_MAC_NAME={shlex.quote(str(get('audio.mac_name', 'MacBook Air Microphone')))}")
print(f"CFG_AUDIO_IPHONE_NAME={shlex.quote(str(get('audio.iphone_name', '')))}")
print(f"CFG_AUDIO_DEVICE_INDEX={shlex.quote(str(get('audio.device_index', '')) if get('audio.device_index', None) is not None else '')}")
print(f"CFG_POSTPROCESS_ENABLED={shlex.quote('1' if b(get('postprocess.enabled', False), False) else '0')}")
print(f"CFG_POSTPROCESS_LLM={shlex.quote(str(get('postprocess.llm', 'llama3.1-8b')))}")
print(f"CFG_POSTPROCESS_MAX_TOKENS={shlex.quote(str(get('postprocess.max_tokens', '')))}")
print(f"CFG_POSTPROCESS_CHUNK_WORDS={shlex.quote(str(get('postprocess.chunk_words', '')))}")

mode_overrides = get("postprocess.mode_overrides", {}) or {}
llm_parts = []
max_parts = []
chunk_parts = []
if isinstance(mode_overrides, dict):
  for mode, d in mode_overrides.items():
    if not isinstance(d, dict):
      continue
    llm = d.get("llm")
    if isinstance(llm, str) and llm.strip():
      llm_parts.append(f"{mode}={llm.strip()}")
    mt = d.get("max_tokens")
    if isinstance(mt, int):
      max_parts.append(f"{mode}={mt}")
    cw = d.get("chunk_words")
    if isinstance(cw, int):
      chunk_parts.append(f"{mode}={cw}")
print(f"CFG_POSTPROCESS_MODE_LLM_OVERRIDES={shlex.quote(';'.join(sorted(llm_parts)))}")
print(f"CFG_POSTPROCESS_MODE_MAX_TOKENS_OVERRIDES={shlex.quote(';'.join(sorted(max_parts)))}")
print(f"CFG_POSTPROCESS_MODE_CHUNK_WORDS_OVERRIDES={shlex.quote(';'.join(sorted(chunk_parts)))}")
print(f"CFG_INLINE_AUTOSEND={shlex.quote('1' if b(get('inline.autosend', True), True) else '0')}")
print(f"CFG_INLINE_PASTE_TARGET={shlex.quote(str(get('inline.paste_target', 'restore')))}")
print(f"CFG_INLINE_SEND_MODE={shlex.quote(str(get('inline.send_mode', 'enter')))}")
print(f"CFG_AUDIO_SOUNDS_START={shlex.quote(str(get('audio.sounds.start', '')))}")
print(f"CFG_AUDIO_SOUNDS_STOP={shlex.quote(str(get('audio.sounds.stop', '')))}")
print(f"CFG_AUDIO_SOUNDS_PROCESS={shlex.quote(str(get('audio.sounds.process', '')))}")
print(f"CFG_AUDIO_SOUNDS_ERROR={shlex.quote(str(get('audio.sounds.error', '')))}")
print(f"CFG_AUDIO_SOUNDS_ENABLED={shlex.quote('1' if b(get('audio.sounds.enabled', True), True) else '0')}")
print(f"CFG_AUDIO_SOUNDS_START_ENABLED={shlex.quote('1' if b(get('audio.sounds.start_enabled', True), True) else '0')}")
print(f"CFG_AUDIO_SOUNDS_STOP_ENABLED={shlex.quote('1' if b(get('audio.sounds.stop_enabled', True), True) else '0')}")
print(f"CFG_AUDIO_SOUNDS_PROCESS_ENABLED={shlex.quote('1' if b(get('audio.sounds.process_enabled', True), True) else '0')}")
print(f"CFG_AUDIO_SOUNDS_ERROR_ENABLED={shlex.quote('1' if b(get('audio.sounds.error_enabled', True), True) else '0')}")
PYEOF
  )"
  [[ -n "$out" ]] && eval "$out"
}

expand_path() {
  dictate_lib_expand_path "${1:-}"
}

expand_sound_path() {
  dictate_lib_expand_sound_path "${1:-}"
}

clean_fillers() {
  dictate_lib_clean_fillers
}

clean_repeats() {
  local level="${1:-1}"
  dictate_lib_clean_repeats "$level"
}

# Remove known whisper placeholder artefacts (e.g. "[blank audio]") from transcript text.
sanitize_transcript_artifacts() {
  dictate_lib_sanitize_transcript_artifacts
}

auto_paragraphs() {
  local mode="${1:-}"
  local min_words="${2:-${DICTATE_PARAGRAPH_MIN_WORDS:-80}}"
  dictate_lib_auto_paragraphs "$mode" "$min_words"
}

normalize_british_spelling() {
  local enabled="${DICTATE_BRITISH_SPELLING:-1}"
  dictate_lib_normalize_british_spelling "$enabled"
}

apply_vocab_corrections() {
  local mode="${1:-}"
  dictate_lib_apply_vocab_corrections "$mode" "$CONFIG_DIR"
}

sound_path() {
  local event="${1:-}"
  local cfg="${2:-}"

  [[ "${CFG_AUDIO_SOUNDS_ENABLED:-1}" == "1" ]] || return 0
  case "$event" in
    start) [[ "${CFG_AUDIO_SOUNDS_START_ENABLED:-1}" == "1" ]] || return 0 ;;
    stop) [[ "${CFG_AUDIO_SOUNDS_STOP_ENABLED:-1}" == "1" ]] || return 0 ;;
    process) [[ "${CFG_AUDIO_SOUNDS_PROCESS_ENABLED:-1}" == "1" ]] || return 0 ;;
    error) [[ "${CFG_AUDIO_SOUNDS_ERROR_ENABLED:-1}" == "1" ]] || return 0 ;;
  esac

  if [[ -n "$cfg" ]]; then
    cfg="$(expand_sound_path "$cfg")"
  else
    cfg="$DICTATE_SOUNDS_DIR/$event.wav"
  fi

  [[ -f "$cfg" ]] && printf "%s" "$cfg"
}

refresh_swiftbar() {
  # Force SwiftBar to refresh immediately (avoids waiting for the next tick).
  # Falls back silently if SwiftBar isn’t installed or URL scheme is unavailable.
  /usr/bin/open -g "swiftbar://refreshplugin?plugin=${SWIFTBAR_PLUGIN_ID}" 2>/dev/null || true
}

HISTORY_DIR="$CONFIG_DIR/history"
BENCH_FILE="$HISTORY_DIR/bench.tsv"

bench_field() {
  printf "%s" "${1:-}" | tr '\t\r\n' '   '
}

append_bench_entry() {
  local flow="${1:-unknown}"
  local status="${2:-ok}"
  local model="${3:-unknown}"
  local mode="${4:-none}"
  local postprocess="${5:-0}"
  local raw_chars="${6:-0}"
  local out_chars="${7:-0}"
  local record_ms="${8:-0}"
  local transcribe_ms="${9:-0}"
  local clean_ms="${10:-0}"
  local postprocess_ms="${11:-0}"
  local paste_ms="${12:-0}"
  local total_ms="${13:-0}"
  local startup_total_ms="${14:-0}"
  local startup_audio_ms="${15:-0}"
  local startup_ffmpeg_live_ms="${16:-0}"
  local startup_target_ms="${17:-0}"
  local startup_audio_source="${18:-}"

  mkdir -p "$HISTORY_DIR" 2>/dev/null || return 0
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    "$(bench_field "$flow")" \
    "$(bench_field "$status")" \
    "$(bench_field "$model")" \
    "$(bench_field "$mode")" \
    "$(bench_field "$postprocess")" \
    "$(bench_field "$raw_chars")" \
    "$(bench_field "$out_chars")" \
    "$(bench_field "$record_ms")" \
    "$(bench_field "$transcribe_ms")" \
    "$(bench_field "$clean_ms")" \
    "$(bench_field "$postprocess_ms")" \
    "$(bench_field "$paste_ms")" \
    "$(bench_field "$total_ms")" \
    "$(bench_field "$startup_total_ms")" \
    "$(bench_field "$startup_audio_ms")" \
    "$(bench_field "$startup_ffmpeg_live_ms")" \
    "$(bench_field "$startup_target_ms")" \
    "$(bench_field "$startup_audio_source")" >>"$BENCH_FILE" 2>/dev/null || true

  local max_rows rows
  max_rows="${DICTATE_BENCH_MAX_ROWS:-800}"
  if [[ "$max_rows" =~ ^[0-9]+$ ]] && (( max_rows > 0 )) && [[ -f "$BENCH_FILE" ]]; then
    rows="$(wc -l < "$BENCH_FILE" | tr -d ' ' || echo 0)"
    if [[ "$rows" =~ ^[0-9]+$ ]] && (( rows > max_rows )); then
      tail -n "$max_rows" "$BENCH_FILE" > "${BENCH_FILE}.tmp" 2>/dev/null || true
      mv -f "${BENCH_FILE}.tmp" "$BENCH_FILE" 2>/dev/null || true
    fi
  fi
}

# Save a dictation to history (lightweight version for Raycast)
save_history() {
  local raw="$1"
  local processed="$2"
  local mode="${3:-unknown}"
  local app="${4:-unknown}"
  
  mkdir -p "$HISTORY_DIR"
  
  # Clean old entries (7 day retention)
  find "$HISTORY_DIR" -name "*.json" -type f -mtime +7 -delete 2>/dev/null || true
  
  local ts
  ts="$(date '+%Y-%m-%dT%H-%M-%S')"
  local filename="$HISTORY_DIR/${ts}.json"
  
  local raw_escaped processed_escaped mode_escaped app_escaped
  raw_escaped="$(printf '%s' "$raw" | jq -Rs .)"
  processed_escaped="$(printf '%s' "$processed" | jq -Rs .)"
  mode_escaped="$(printf '%s' "$mode" | jq -Rs .)"
  app_escaped="$(printf '%s' "$app" | jq -Rs .)"
  
  cat > "$filename" <<EOF
{
  "timestamp": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "mode": $mode_escaped,
  "app": $app_escaped,
  "raw": $raw_escaped,
  "processed": $processed_escaped
}
EOF
}

resolve_model_path() {
  dictate_lib_resolve_model_path "${1:-}" "${WHISPER_MODELS_DIR:-}"
}

transcribe_whisper_cli() {
  local wav="$1"
  local model_id="${2:-}"
  local language="${3:-en}"
  local threads="${4:-${DICTATE_THREADS:-${CFG_WHISPER_THREADS:-5}}}"
  local beam="${DICTATE_BEAM_SIZE:-${CFG_WHISPER_BEAM_SIZE:-1}}"
  local best_of="${DICTATE_BEST_OF:-${CFG_WHISPER_BEST_OF:-1}}"
  local vad_enabled="${DICTATE_VAD:-${CFG_WHISPER_VAD_ENABLED:-0}}"
  local vad_model="${DICTATE_VAD_MODEL:-${CFG_WHISPER_VAD_MODEL:-}}"
  local vad_threshold="${DICTATE_VAD_THRESHOLD:-${CFG_WHISPER_VAD_THRESHOLD:-0.5}}"
  local vad_min_speech_ms="${DICTATE_VAD_MIN_SPEECH_MS:-${CFG_WHISPER_VAD_MIN_SPEECH_MS:-250}}"
  local vad_min_silence_ms="${DICTATE_VAD_MIN_SILENCE_MS:-${CFG_WHISPER_VAD_MIN_SILENCE_MS:-100}}"
  local vad_speech_pad_ms="${DICTATE_VAD_SPEECH_PAD_MS:-${CFG_WHISPER_VAD_SPEECH_PAD_MS:-30}}"
  local gpu_flag="${DICTATE_GPU:-}"
  local model
  model="$(resolve_model_path "$model_id")"

  local -a args
  args=(whisper-cli -m "$model" -l "$language" -t "$threads" -bs "$beam" -bo "$best_of")

  if [[ "$vad_enabled" == "1" || "$vad_enabled" == "true" || "$vad_enabled" == "on" ]]; then
    if [[ -z "$vad_model" || ! -f "$vad_model" ]]; then
      echo "dictate: whisper.vad enabled but whisper.vad_model is missing; skipping VAD" >>"$LOG"
      vad_enabled="0"
    fi
  fi
  if [[ "$vad_enabled" == "1" || "$vad_enabled" == "true" || "$vad_enabled" == "on" ]]; then
    args+=(--vad -vm "$vad_model")
    [[ -n "$vad_threshold" ]] && args+=(-vt "$vad_threshold")
    [[ -n "$vad_min_speech_ms" ]] && args+=(-vspd "$vad_min_speech_ms")
    [[ -n "$vad_min_silence_ms" ]] && args+=(-vsd "$vad_min_silence_ms")
    [[ -n "$vad_speech_pad_ms" ]] && args+=(-vp "$vad_speech_pad_ms")
    if [[ -z "$gpu_flag" ]]; then
      gpu_flag="-ng"
    fi
  fi

  args+=(-nt -np)
  if [[ -n "$gpu_flag" ]]; then
    local -a gpu_parts
    IFS=' ' read -r -a gpu_parts <<<"$gpu_flag"
    args+=("${gpu_parts[@]}")
  fi
  args+=("$wav")

  "${args[@]}" 2>>"$LOG" \
  | tr '\n' ' ' \
  | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//'
}

transcribe_audio() {
  local wav="$1"
  local model_id="${2:-}"
  local language="${3:-en}"
  local threads="${4:-2}"

  maybe_trim_silence_inplace "$wav"
  transcribe_whisper_cli "$wav" "$model_id" "$language" "$threads"
}

maybe_trim_silence_inplace() {
  local wav="${1:-}"
  [[ -n "$wav" && -f "$wav" ]] || return 0

  if bool_is_on "${DICTATE_RUNTIME_SKIP_SILENCE_TRIM:-0}"; then
    return 0
  fi

  local enabled="${DICTATE_SILENCE_TRIM:-${CFG_AUDIO_SILENCE_TRIM:-0}}"
  bool_is_on "$enabled" || return 0

  command -v ffmpeg >/dev/null 2>&1 || return 0

  local mode="${DICTATE_SILENCE_TRIM_MODE:-${CFG_AUDIO_SILENCE_TRIM_MODE:-edges}}"
  local threshold_db="${DICTATE_SILENCE_THRESHOLD_DB:-${CFG_AUDIO_SILENCE_THRESHOLD_DB:--60}}"
  local min_ms="${DICTATE_SILENCE_MIN_MS:-${CFG_AUDIO_SILENCE_MIN_MS:-250}}"
  local keep_ms="${DICTATE_SILENCE_KEEP_MS:-${CFG_AUDIO_SILENCE_KEEP_MS:-50}}"

  local min_s keep_s threshold_amp
  min_s="$(awk "BEGIN { printf \"%.3f\", (${min_ms:-250})/1000 }")"
  keep_s="$(awk "BEGIN { printf \"%.3f\", (${keep_ms:-50})/1000 }")"
  threshold_amp="$(awk "BEGIN { printf \"%.6f\", 10^((${threshold_db:--60})/20) }")"

  local stop_periods="1"
  if [[ "$mode" == "all" ]]; then
    stop_periods="-1"
  fi

  local tmp="${wav}.trim.wav"
  rm -f "$tmp" 2>/dev/null || true

  printf "[%s] silence_trim: mode=%s threshold_db=%s threshold_amp=%s min_ms=%s keep_ms=%s\n" \
    "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$mode" "$threshold_db" "$threshold_amp" "$min_ms" "$keep_ms" \
    >>"$LOG" 2>/dev/null || true

  set +e
  ffmpeg -hide_banner -loglevel error -y \
    -i "$wav" \
    -af "silenceremove=start_periods=1:start_duration=${min_s}:start_threshold=${threshold_amp}:start_silence=${keep_s}:stop_periods=${stop_periods}:stop_duration=${min_s}:stop_threshold=${threshold_amp}:stop_silence=${keep_s}:detection=peak" \
    -ac 1 -ar 16000 -c:a pcm_s16le \
    "$tmp" >>"$LOG" 2>&1
  local rc=$?
  set -e

  if [[ "$rc" -ne 0 || ! -s "$tmp" ]]; then
    rm -f "$tmp" 2>/dev/null || true
    return 0
  fi

  mv -f "$tmp" "$wav" 2>/dev/null || {
    rm -f "$tmp" 2>/dev/null || true
    return 0
  }
}

if [[ "$TRACE" == "1" ]]; then
  t0="$(now_ms)"
  load_config
  t1="$(now_ms)"
  trace "load_config: $((t1 - t0))ms"
else
  load_config
fi

normalize_inline_paste_target() {
  local val="${1:-restore}"
  case "$val" in
    current) echo "current" ;;
    origin|restore|"") echo "restore" ;;
    *) echo "restore" ;;
  esac
}

normalize_inline_send_mode() {
  local val="${1:-enter}"
  case "$val" in
    enter|"") echo "enter" ;;
    ctrl_j|ctrl-j|ctrlj|ctrl+j) echo "ctrl_j" ;;
    cmd_enter|cmd-enter|cmdenter|cmd+enter) echo "cmd_enter" ;;
    *) echo "enter" ;;
  esac
}

inline_send_mode_desc() {
  local mode
  mode="$(normalize_inline_send_mode "${1:-enter}")"
  case "$mode" in
    ctrl_j) echo "Ctrl+J" ;;
    cmd_enter) echo "Cmd+Enter" ;;
    *) echo "Enter" ;;
  esac
}

resolve_inline_paste_target() {
  normalize_inline_paste_target "${DICTATE_INLINE_PASTE_TARGET:-${CFG_INLINE_PASTE_TARGET:-restore}}"
}

resolve_inline_send_mode() {
  normalize_inline_send_mode "${DICTATE_INLINE_SEND_MODE:-${CFG_INLINE_SEND_MODE:-enter}}"
}

INLINE_PASTE_TARGET="$(resolve_inline_paste_target)"
INLINE_SEND_MODE="$(resolve_inline_send_mode)"

SOUND_START="$(sound_path start "${CFG_AUDIO_SOUNDS_START:-}")"
SOUND_STOP="$(sound_path stop "${CFG_AUDIO_SOUNDS_STOP:-}")"
SOUND_PROCESS="$(sound_path process "${CFG_AUDIO_SOUNDS_PROCESS:-}")"
SOUND_ERROR="$(sound_path error "${CFG_AUDIO_SOUNDS_ERROR:-}")"

detect_audio_index() {
  local source_mode="${1:-auto}"
  local preferred="${2:-}"
  local mac_name="${3:-}"
  local iphone_name="${4:-}"
  dictate_lib_detect_audio_device "$source_mode" "$preferred" "$mac_name" "$iphone_name"
}

normalize_audio_source() {
  local src="${1:-auto}"
  src="$(printf "%s" "$src" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
  case "$src" in
    auto|name|external|mac|iphone) echo "$src" ;;
    *) echo "auto" ;;
  esac
}

if [[ -z "${DICTATE_AUDIO_INDEX:-}" ]]; then
  source_mode="$(normalize_audio_source "${DICTATE_AUDIO_SOURCE:-${CFG_AUDIO_SOURCE:-auto}}")"
  preferred="${DICTATE_AUDIO_NAME:-${CFG_AUDIO_DEVICE_NAME:-MacBook Air Microphone}}"
  mac_name="${CFG_AUDIO_MAC_NAME:-${CFG_AUDIO_DEVICE_NAME:-MacBook Air Microphone}}"
  iphone_name="${CFG_AUDIO_IPHONE_NAME:-}"
  PREFERRED_AUDIO_NAME="$preferred"
  AUDIO_SOURCE_MODE="$source_mode"
  audio_detect_started_ms="$(now_ms)"
  cache_key="source=${source_mode};preferred=${preferred};mac=${mac_name};iphone=${iphone_name}"
  allow_cache="0"
  case "$source_mode" in
    name|mac) allow_cache="1" ;;
  esac

  if [[ "$allow_cache" == "1" ]] && load_audio_index_cache && [[ "${CACHED_AUDIO_KEY:-}" == "$cache_key" ]]; then
    DICTATE_AUDIO_INDEX="$CACHED_AUDIO_INDEX"
    STARTUP_AUDIO_SOURCE="cache:source(${source_mode}):match(${CACHED_AUDIO_MATCH:-cache}):name(${CACHED_AUDIO_NAME:-})"
    trace "audio_index: cached (${DICTATE_AUDIO_INDEX})"
  else
    [[ "$TRACE" == "1" ]] && t0="$(now_ms)"
    detect_meta="$(detect_audio_index "$source_mode" "$preferred" "$mac_name" "$iphone_name" 2>/dev/null || true)"
    IFS=$'\t' read -r DICTATE_AUDIO_INDEX detected_name detected_match <<<"$detect_meta"
    [[ "$TRACE" == "1" ]] && t1="$(now_ms)" && trace "audio_index: detect (${DICTATE_AUDIO_INDEX:-<none>}) $((t1 - t0))ms"
    if [[ -n "$DICTATE_AUDIO_INDEX" ]]; then
      STARTUP_AUDIO_SOURCE="detect:source(${source_mode}):match(${detected_match:-unknown}):name(${detected_name:-})"
      if [[ "$allow_cache" == "1" ]]; then
        write_audio_index_cache "$cache_key" "$DICTATE_AUDIO_INDEX" "$detected_name" "$detected_match"
      fi
    elif [[ -n "${CFG_AUDIO_DEVICE_INDEX:-}" ]]; then
      DICTATE_AUDIO_INDEX="$CFG_AUDIO_DEVICE_INDEX"
      STARTUP_AUDIO_SOURCE="config:audio.device_index"
      trace "audio_index: fallback index (${DICTATE_AUDIO_INDEX})"
    else
      STARTUP_AUDIO_SOURCE="detect:miss:source(${source_mode})"
    fi
  fi
  STARTUP_AUDIO_MS=$(( $(now_ms) - audio_detect_started_ms ))
  export DICTATE_AUDIO_INDEX
else
  STARTUP_AUDIO_SOURCE="env:DICTATE_AUDIO_INDEX"
fi
echo "Audio: index=${DICTATE_AUDIO_INDEX:-<none>} source=${AUDIO_SOURCE_MODE:-${CFG_AUDIO_SOURCE:-auto}}"

WHISPER_MODELS_DIR="${WHISPER_MODELS_DIR:-${CFG_WHISPER_MODELS_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/whisper/models}}"
WHISPER_MODELS_DIR="$(expand_path "$WHISPER_MODELS_DIR")"
export WHISPER_MODELS_DIR

if [[ -z "${DICTATE_MODEL:-}" ]]; then
  export DICTATE_MODEL="${CFG_WHISPER_MODEL:-base}"
fi

# Optional: if you keep secrets in a shell env file, source it here.
# (Intentionally not sourcing .zshrc, which may assume an interactive shell.)

# Canonical mode names for inline UX.
canonical_mode_name() {
  local m="${1:-}"
  case "$m" in
    code) echo "short" ;;
    "") echo "short" ;;
    *) echo "$m" ;;
  esac
}

mode_to_dir_name() {
  local m
  m="$(canonical_mode_name "${1:-}")"
  echo "$m"
}

mode_override_key() {
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

# Detect mode based on frontmost app
detect_mode() {
  local app
  app="$(osascript -e 'tell application "System Events" to get name of first process whose frontmost is true' 2>/dev/null || echo "")"
  [[ -z "$app" ]] && echo "short" && return 0

  for mode_dir in "$CONFIG_DIR/modes"/*/; do
    local mode_name
    mode_name="$(basename "$mode_dir")"
    local apps_file="$mode_dir/apps"
    [[ -f "$apps_file" ]] || continue
    if grep -iq "^${app}$" "$apps_file" 2>/dev/null; then
      normalize_mode_name "$mode_name"
      return 0
    fi
  done
  echo "short"
}

get_current_mode() {
  if [[ -f "$MODE_FILE" ]]; then
    local saved_mode
    saved_mode="$(cat "$MODE_FILE")"
    normalize_mode_name "$saved_mode"
    return 0
  fi
  detect_mode
}

# Build system prompt for mode
build_mode_prompt() {
  local mode
  mode="$(normalize_mode_name "$1")"
  local mode_dir="$CONFIG_DIR/modes/$(mode_to_dir_name "$mode")"
  
  local base_prompt='You are cleaning speech-to-text dictation.

HARD RULES:
- You are a dictation cleaner/editor, not a task-completing assistant.
- Follow the MODE INSTRUCTIONS below.
- You may add minimal structural elements required by the mode (e.g. paragraph breaks, email greeting/subject), but do not add new facts, steps, or deliverables.
- If the dictation asks to create/generate/list items (e.g. "make 10 prompts"), keep it as a request instead of generating the items, unless the MODE INSTRUCTIONS explicitly require generating them.
- Preserve meaning; do not add new information or opinions.
- Remove filler words and obvious false starts.
- Fix obvious transcription errors and apply corrections.
- Output ONLY the final result (no preamble, no explanations).'

  local mode_prompt=""
  [[ -f "$mode_dir/prompt" ]] && mode_prompt="$(cat "$mode_dir/prompt")"
  
  local global_vocab=""
  [[ -f "$CONFIG_DIR/vocab" ]] && global_vocab="$(cat "$CONFIG_DIR/vocab" | tr '\n' ';' | sed 's/;$//')"
  
  local mode_vocab=""
  [[ -f "$mode_dir/vocab" ]] && mode_vocab="$(cat "$mode_dir/vocab" | tr '\n' ';' | sed 's/;$//')"
  
  local full_prompt="$base_prompt"
  [[ -n "$mode_prompt" ]] && full_prompt="${full_prompt}

${mode_prompt}"
  [[ -n "$global_vocab" ]] && full_prompt="${full_prompt}

GLOBAL CORRECTIONS: ${global_vocab}"
  [[ -n "$mode_vocab" ]] && full_prompt="${full_prompt}

MODE CORRECTIONS: ${mode_vocab}"
  
  echo "$full_prompt"
}

# LLM post-processing via Cerebras
postprocess_llm() {
  local input="$1"
  local mode
  mode="$(normalize_mode_name "${2:-}")"
  local mode_key
  mode_key="$(mode_override_key "$mode")"
  
  [[ -z "${CEREBRAS_API_KEY:-}" ]] && echo "$input" && return 0
  
  lookup_override() {
    local list="${1:-}"
    local key="${2:-}"
    [[ -n "$list" && -n "$key" ]] || return 1
    local IFS=';'
    read -r -a pairs <<<"$list"
    local pair
    for pair in "${pairs[@]}"; do
      [[ "$pair" == "$key="* ]] && { echo "${pair#*=}"; return 0; }
    done
    return 1
  }

  lookup_override_for_mode() {
    local list="${1:-}"
    local key="${2:-}"
    lookup_override "$list" "$key" 2>/dev/null || true
  }

  budget_profile_for_input() {
    local text="${1:-}"
    local threshold="${DICTATE_LLM_BUDGET_LONG_WORDS_THRESHOLD:-120}"
    local word_count
    [[ "$threshold" =~ ^[0-9]+$ ]] || threshold="120"
    word_count="$(printf '%s' "$text" | wc -w | tr -d '[:space:]')"
    [[ "$word_count" =~ ^[0-9]+$ ]] || word_count="0"
    if [[ "$word_count" -ge "$threshold" ]]; then
      echo "long"
    else
      echo "short"
    fi
  }

  resolve_budget_override() {
    local list="${1:-}"
    local mode_key="${2:-}"
    local budget_key="${3:-}"
    local val=""
    if [[ -n "$mode_key" && "$mode_key" != "short" && "$mode_key" != "long" ]]; then
      val="$(lookup_override_for_mode "$list" "$mode_key" 2>/dev/null || true)"
      [[ -n "$val" ]] && { echo "$val"; return 0; }
    fi
    lookup_override_for_mode "$list" "$budget_key" 2>/dev/null || true
  }

  local llm_model="llama3.1-8b"
  [[ -n "${CFG_POSTPROCESS_LLM:-}" ]] && llm_model="$CFG_POSTPROCESS_LLM"
  if [[ -n "${DICTATE_LLM_MODEL:-}" ]]; then
    llm_model="$DICTATE_LLM_MODEL"
  else
    local llm_override=""
    llm_override="$(lookup_override_for_mode "${CFG_POSTPROCESS_MODE_LLM_OVERRIDES:-}" "$mode_key" 2>/dev/null || true)"
    [[ -n "$llm_override" ]] && llm_model="$llm_override"
  fi

  local system_prompt
  system_prompt="$(build_mode_prompt "$mode")"

  local max_tokens=""
  local chunk_words=""
  local budget_profile_key
  budget_profile_key="$(budget_profile_for_input "$input")"
  if [[ -n "${DICTATE_LLM_MAX_TOKENS:-}" ]]; then
    max_tokens="$DICTATE_LLM_MAX_TOKENS"
  else
    max_tokens="$(resolve_budget_override "${CFG_POSTPROCESS_MODE_MAX_TOKENS_OVERRIDES:-}" "$mode_key" "$budget_profile_key" 2>/dev/null || true)"
    [[ -z "$max_tokens" ]] && max_tokens="${CFG_POSTPROCESS_MAX_TOKENS:-}"
  fi

  if [[ -n "${DICTATE_LLM_CHUNK_WORDS:-}" ]]; then
    chunk_words="$DICTATE_LLM_CHUNK_WORDS"
  else
    chunk_words="$(resolve_budget_override "${CFG_POSTPROCESS_MODE_CHUNK_WORDS_OVERRIDES:-}" "$mode_key" "$budget_profile_key" 2>/dev/null || true)"
    [[ -z "$chunk_words" ]] && chunk_words="${CFG_POSTPROCESS_CHUNK_WORDS:-}"
  fi
  [[ -z "$chunk_words" ]] && chunk_words="0"

  maybe_reject_llm_output() {
    local input_chunk="$1"
    local output_text="$2"
    local mode="$3"

    local in_trim out_trim
    in_trim="$(printf '%s' "$input_chunk" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
    out_trim="$(printf '%s' "$output_text" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"

    case "$(mode_override_key "$mode")" in
      short)
        if [[ ! "$in_trim" =~ ^[\\{\\[] ]] && [[ "$out_trim" =~ ^[\\{\\[] ]]; then
          if printf '%s' "$out_trim" | grep -Eq '"prompt"[[:space:]]*:'; then
            echo "$input_chunk"
            return 0
          fi
        fi
        if [[ "$out_trim" == '```'* && "$in_trim" != '```'* ]]; then
          echo "$input_chunk"
          return 0
        fi
        ;;
    esac

    echo "$output_text"
  }

  request_llm() {
    local chunk="$1"
    local escaped_input escaped_prompt
    escaped_input="$(printf '%s' "$chunk" | jq -Rs .)"
    escaped_prompt="$(printf '%s' "$system_prompt" | jq -Rs .)"

    local timeout="${DICTATE_LLM_TIMEOUT:-20}"
    local response=""
    local curl_rc=0
    local max_tokens_json=""
    if [[ -n "$max_tokens" ]]; then
      max_tokens_json=", \"max_tokens\": ${max_tokens}"
    fi
    set +e
    response="$(curl -sS --fail-with-body --connect-timeout 3 --max-time "$timeout" https://api.cerebras.ai/v1/chat/completions \
      -H "Authorization: Bearer $CEREBRAS_API_KEY" \
      -H "Content-Type: application/json" \
      -d '{
        "model": "'"$llm_model"'",
        "messages": [
          {"role": "system", "content": '"$escaped_prompt"'},
          {"role": "user", "content": '"$escaped_input"'}
        ],
        "temperature": 0.0'"$max_tokens_json"'
      }' 2>&1)"
    curl_rc=$?
    set -e
    if [[ "$curl_rc" -ne 0 ]]; then
      if [[ -n "${LOG:-}" && "${DICTATE_KEEP_LOGS:-0}" == "1" ]]; then
        printf "[%s] LLM request failed (curl=%s, timeout=%s, mode=%s, model=%s)\n%s\n\n" \
          "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$curl_rc" "$timeout" "$mode" "$llm_model" "$response" \
          >>"$LOG" 2>/dev/null || true
      fi
      echo "$chunk"
      return 0
    fi

    local result
    result="$(printf '%s' "$response" | jq -r '.choices[0].message.content // empty' 2>/dev/null)"

    if [[ -n "$result" && "$result" != "null" ]]; then
      result="$(maybe_reject_llm_output "$chunk" "$result" "$mode")"
      echo "$result"
      return 0
    fi

    local api_error=""
    api_error="$(printf '%s' "$response" | jq -r '.error.message // .error // empty' 2>/dev/null)"
    if [[ -n "$api_error" ]]; then
      if [[ -n "${LOG:-}" && "${DICTATE_KEEP_LOGS:-0}" == "1" ]]; then
        printf "[%s] LLM api error (mode=%s, model=%s): %s\n\n" \
          "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$mode" "$llm_model" "$api_error" \
          >>"$LOG" 2>/dev/null || true
      fi
      echo "$chunk"
      return 0
    fi
    if [[ -n "${LOG:-}" && "${DICTATE_KEEP_LOGS:-0}" == "1" ]]; then
      printf "[%s] LLM response parse/empty (mode=%s, model=%s)\n%s\n\n" \
        "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$mode" "$llm_model" "$response" \
        >>"$LOG" 2>/dev/null || true
    fi
    echo "$chunk"
  }

  if [[ "$chunk_words" =~ ^[0-9]+$ && "$chunk_words" -gt 0 ]]; then
    local chunks
    chunks="$(
      python3 - "$chunk_words" <<'PYEOF'
import re, sys
max_words = int(sys.argv[1])
text = sys.stdin.read()
text = re.sub(r"\s+", " ", text).strip()
if not text:
    print("")
    raise SystemExit(0)
sentences = re.split(r'(?<=[.!?])\s+', text)
chunks = []
cur = []
count = 0
for s in sentences:
    w = len(re.findall(r"\b\w+\b", s))
    if count + w > max_words and cur:
        chunks.append(" ".join(cur).strip())
        cur = [s]
        count = w
    else:
        cur.append(s)
        count += w
if cur:
    chunks.append(" ".join(cur).strip())
print("\n<<DICTATE_CHUNK>>\n".join(chunks))
PYEOF
    <<<"$input")"
    if [[ -n "$chunks" ]]; then
      IFS=$'\n' read -r -d '' -a chunk_list < <(printf '%s' "$chunks" | awk 'BEGIN{RS="<<DICTATE_CHUNK>>"; ORS="\0"} {print}')
      local output="" first="1"
      for c in "${chunk_list[@]}"; do
        c="$(printf "%s" "$c" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
        [[ -z "$c" ]] && continue
        local part
        part="$(request_llm "$c")"
        if [[ "$first" == "1" ]]; then
          output="$part"
          first="0"
        else
          output="${output}"$'\n\n'"$part"
        fi
      done
      echo "$output"
      return 0
    fi
  fi

  request_llm "$input"
}

inline_paste_via_osascript() {
  osascript -e 'tell application "System Events" to keystroke "v" using command down'
}

inline_send_key_via_osascript() {
  local send_mode="${1:-enter}"
  send_mode="$(normalize_inline_send_mode "$send_mode")"
  case "$send_mode" in
    ctrl_j)
      osascript -e 'tell application "System Events" to keystroke "j" using control down'
      ;;
    cmd_enter)
      osascript -e 'tell application "System Events" to key code 36 using command down'
      ;;
    *)
      osascript -e 'tell application "System Events" to key code 36'
      ;;
  esac
}

if [[ -f "$STATE_FILE" ]]; then
  echo "Stopping recording..."
  source "$STATE_FILE"
  saved_paste_target="${paste_target:-}"
  paste_target="$(normalize_inline_paste_target "${saved_paste_target:-$INLINE_PASTE_TARGET}")"
  startup_total_ms="${startup_total_ms:-0}"
  startup_audio_ms="${startup_audio_ms:-0}"
  startup_ffmpeg_live_ms="${startup_ffmpeg_live_ms:-0}"
  startup_target_ms="${startup_target_ms:-0}"
  startup_audio_source="${startup_audio_source:-}"
  bench_flow="raycast-inline"
  bench_model="${DICTATE_MODEL:-${CFG_WHISPER_MODEL:-base}}"
  bench_mode="none"
  bench_postprocess="0"
  do_postprocess="${DICTATE_POSTPROCESS:-${CFG_POSTPROCESS_ENABLED:-0}}"
  if bool_is_on "$do_postprocess" && [[ -n "${CEREBRAS_API_KEY:-}" ]]; then
    do_postprocess="1"
  else
    do_postprocess="0"
  fi
  flow_started_ms="$(now_ms)"
  state_record_started_ms="${record_started_ms:-$flow_started_ms}"
  record_ms=0
  transcribe_ms=0
  clean_ms=0
  postprocess_ms=0
  paste_ms=0
  total_ms=0
  rm -f "$STATE_FILE"
  rm -f "$PROCESSING_LONG_FLAG" 2>/dev/null || true
  refresh_swiftbar

  if kill -0 "$pid" 2>/dev/null; then
    kill -INT "$pid" 2>/dev/null
    # Poll for graceful ffmpeg exit instead of a fixed 300ms delay.
    for _ in {1..25}; do
      if ! kill -0 "$pid" 2>/dev/null; then
        break
      fi
      sleep 0.01
    done
    if kill -0 "$pid" 2>/dev/null; then
      kill -TERM "$pid" 2>/dev/null || true
      for _ in {1..20}; do
        if ! kill -0 "$pid" 2>/dev/null; then
          break
        fi
        sleep 0.01
      done
    fi
  fi
  record_ms=$(( $(now_ms) - state_record_started_ms ))
  (( record_ms < 0 )) && record_ms=0

  if [[ ! -s "$wav" ]]; then
    echo "No audio in $wav"
    rm -f "$wav" 2>/dev/null
    rm -f "$PROCESSING_LONG_FLAG" 2>/dev/null || true
    total_ms=$(( $(now_ms) - flow_started_ms ))
    append_bench_entry "$bench_flow" "record_failed" "$bench_model" "$bench_mode" "$bench_postprocess" "0" "0" "$record_ms" "0" "0" "0" "0" "$total_ms" \
      "$startup_total_ms" "$startup_audio_ms" "$startup_ffmpeg_live_ms" "$startup_target_ms" "$startup_audio_source"
    [[ -n "${SOUND_ERROR:-}" ]] && afplay "$SOUND_ERROR" 2>/dev/null &
    exit 0
  fi

  # Create processing marker (covers transcription + LLM)
  mkdir -p "$PROCESSING_DIR"
  proc_file="$PROCESSING_DIR/inline-$$"
  printf "pid=%s\nkind=raycast-inline\n" "$$" >"$proc_file" 2>/dev/null || true
  trap 'rm -f "$proc_file" "$PROCESSING_LONG_FLAG" 2>/dev/null || true' EXIT

  # Show ⏳ only if processing actually takes longer than the threshold (avoid flicker).
  (
    sleep "$PROCESSING_THRESHOLD_S"
    if [[ -f "$proc_file" ]]; then
      printf "pid=%s\n" "$$" >"$PROCESSING_LONG_FLAG" 2>/dev/null || true
      refresh_swiftbar
    fi
  ) >/dev/null 2>&1 &
  disown

  [[ -n "${SOUND_PROCESS:-}" ]] && afplay "$SOUND_PROCESS" 2>/dev/null &

  runtime_skip_silence_trim="0"
  if [[ "$do_postprocess" == "1" ]] && ! bool_is_on "${DICTATE_TRIM_WITH_POSTPROCESS:-0}"; then
    runtime_skip_silence_trim="1"
  fi
  stage_started_ms="$(now_ms)"
  echo "Transcribing $wav..."
  txt="$(DICTATE_RUNTIME_SKIP_SILENCE_TRIM="$runtime_skip_silence_trim" transcribe_audio "$wav" "$bench_model" "en" "${DICTATE_THREADS:-${CFG_WHISPER_THREADS:-5}}")"
  transcribe_ms=$(( $(now_ms) - stage_started_ms ))
  echo "Transcription (${transcribe_ms}ms): $txt"

  rm -f "$wav"
  stage_started_ms="$(now_ms)"
  txt="$(printf "%s" "$txt" | sanitize_transcript_artifacts)"

  if [[ "${DICTATE_CLEAN:-0}" == "1" ]]; then
    run_repeats="1"
    if [[ "$do_postprocess" == "1" ]] && ! bool_is_on "${DICTATE_REPEATS_WITH_POSTPROCESS:-0}"; then
      run_repeats="0"
    fi
    txt="$(printf "%s" "$txt" | clean_fillers)"
    if [[ "$run_repeats" == "1" ]]; then
      repeats_level="${DICTATE_REPEATS_LEVEL:-${CFG_CLEAN_REPEATS_LEVEL:-1}}"
      if [[ "$repeats_level" != "0" ]]; then
        txt="$(printf "%s" "$txt" | clean_repeats "$repeats_level")"
      fi
    fi
  fi
  clean_ms=$(( $(now_ms) - stage_started_ms ))

  if [[ -z "${txt//[[:space:]]/}" ]]; then
    echo "No speech detected"
    total_ms=$(( $(now_ms) - flow_started_ms ))
    append_bench_entry "$bench_flow" "no_speech" "$bench_model" "$bench_mode" "$bench_postprocess" "0" "0" "$record_ms" "$transcribe_ms" "$clean_ms" "0" "0" "$total_ms" \
      "$startup_total_ms" "$startup_audio_ms" "$startup_ffmpeg_live_ms" "$startup_target_ms" "$startup_audio_source"
    [[ -n "${SOUND_ERROR:-}" ]] && afplay "$SOUND_ERROR" 2>/dev/null &
    exit 0
  fi

  # Save raw transcript for history
  raw_txt="$txt"

  # LLM post-processing if enabled
  current_mode="none"
  if [[ "$do_postprocess" == "1" ]]; then
    stage_started_ms="$(now_ms)"
    echo "Running LLM post-processing..."
    current_mode="$(get_current_mode "${target_app:-}")"
    echo "Mode: $current_mode"
    txt="$(postprocess_llm "$txt" "$current_mode")"
    txt="$(printf "%s" "$txt" | auto_paragraphs "$current_mode")"
    echo "LLM result: $txt"
    postprocess_ms=$(( $(now_ms) - stage_started_ms ))
    bench_postprocess="1"
    bench_mode="$current_mode"
  elif bool_is_on "${DICTATE_VOCAB_CLEAN:-1}"; then
    current_mode="$(get_current_mode "${target_app:-}")"
    txt="$(printf "%s" "$txt" | apply_vocab_corrections "$current_mode")"
    bench_mode="$current_mode"
  fi

  txt="$(printf "%s" "$txt" | normalize_british_spelling)"
  
  # Clean up processing marker and signal completion
  rm -f "$proc_file"
  rm -f "$PROCESSING_LONG_FLAG" 2>/dev/null || true
  touch /tmp/dictate-just-processed
  refresh_swiftbar

  stage_started_ms="$(now_ms)"
  printf "%s" "$txt" | pbcopy
  
  # Determine paste target based on state/config
  # "restore/origin" = use app from recording start (saved in state file)
  # "current" = paste to whatever is frontmost now
  activate_delay_ms="${DICTATE_INLINE_ACTIVATE_DELAY_MS:-90}"
  send_delay_default_ms="35"
  send_delay_ms="${DICTATE_INLINE_SEND_DELAY_MS:-$send_delay_default_ms}"
  inline_send_mode="$(normalize_inline_send_mode "${DICTATE_INLINE_SEND_MODE:-${CFG_INLINE_SEND_MODE:-$INLINE_SEND_MODE}}")"
  [[ "$activate_delay_ms" =~ ^[0-9]+$ ]] || activate_delay_ms=90
  [[ "$send_delay_ms" =~ ^[0-9]+$ ]] || send_delay_ms="$send_delay_default_ms"

  saved_app="${target_app:-}"
  saved_window="${target_window:-}"
  saved_pid="${target_pid:-}"
  
  if [[ "$paste_target" == "restore" && -n "$saved_app" ]]; then
    echo "Copied to clipboard, restoring to: $saved_app (PID: $saved_pid, window: $saved_window)"
    
    # Use PID to target the specific process instance (handles multiple instances of same app)
    if [[ -n "$saved_pid" ]]; then
      osascript -e '
        on run argv
          set targetPID to item 1 of argv as integer
          set winName to item 2 of argv
          tell application "System Events"
            try
              set targetProc to first process whose unix id is targetPID
              set frontmost of targetProc to true
              delay 0.05
              if winName is not "" then
                try
                  tell targetProc
                    set targetWin to first window whose name is winName
                    perform action "AXRaise" of targetWin
                  end tell
                end try
              end if
            on error
              -- Process may have exited; fall back silently
            end try
          end tell
        end run
      ' "$saved_pid" "$saved_window" 2>/dev/null || true
    elif [[ -n "$saved_window" ]]; then
      # Fallback: no PID, try by app name + window
      osascript -e '
        on run argv
          set appName to item 1 of argv
          set winName to item 2 of argv
          tell application "System Events"
            set frontmost of process appName to true
            delay 0.05
            try
              tell process appName
                set targetWin to first window whose name is winName
                perform action "AXRaise" of targetWin
              end tell
            on error
            end try
          end tell
        end run
      ' "$saved_app" "$saved_window" 2>/dev/null || true
    else
      saved_app_escaped="${saved_app//\"/\\\"}"
      osascript -e "tell application \"System Events\" to set frontmost of process \"$saved_app_escaped\" to true" 2>/dev/null || true
    fi
    sleep_ms "$activate_delay_ms"
  else
    echo "Copied to clipboard, pasting to current app"
  fi

  # Check autosend setting
  autosend="${CFG_INLINE_AUTOSEND:-1}"
  if [[ "$autosend" == "1" ]]; then
    inline_paste_via_osascript
    sleep_ms "$send_delay_ms"
    inline_send_key_via_osascript "$inline_send_mode"
    echo "Done! (autosend: $(inline_send_mode_desc "$inline_send_mode"))"
  else
    inline_paste_via_osascript
    echo "Done! (paste only)"
  fi

  paste_ms=$(( $(now_ms) - stage_started_ms ))
  total_ms=$(( $(now_ms) - flow_started_ms ))
  append_bench_entry "$bench_flow" "ok" "$bench_model" "$bench_mode" "$bench_postprocess" "${#raw_txt}" "${#txt}" "$record_ms" "$transcribe_ms" "$clean_ms" "$postprocess_ms" "$paste_ms" "$total_ms" \
    "$startup_total_ms" "$startup_audio_ms" "$startup_ffmpeg_live_ms" "$startup_target_ms" "$startup_audio_source"

  # Save history asynchronously so user-visible paste/send completes sooner.
  history_app="${target_app:-current}"
  ( save_history "$raw_txt" "$txt" "$current_mode" "${history_app:-unknown}" ) >/dev/null 2>&1 &
  
  [[ -n "${SOUND_STOP:-}" ]] && afplay "$SOUND_STOP" 2>/dev/null &
else
  echo "Starting recording..."

  wav="/tmp/dictate-inline-$$.wav"
  ffmpeg_live_started_ms="$(now_ms)"

  start_ffmpeg() {
    ffmpeg -hide_banner -loglevel error \
      -f avfoundation -i ":$DICTATE_AUDIO_INDEX" \
      -ac 1 -ar 16000 -c:a pcm_s16le \
      "$wav" 2>&1 &
  }

  [[ "$TRACE" == "1" ]] && t0="$(now_ms)"
  start_ffmpeg
  [[ "$TRACE" == "1" ]] && t1="$(now_ms)" && trace "ffmpeg spawn: $((t1 - t0))ms"
 
  pid=$!
  echo "ffmpeg pid=$pid, wav=$wav"
  record_started_ms="$(now_ms)"
  STARTUP_TOTAL_MS=$(( record_started_ms - SCRIPT_STARTED_MS ))
  (( STARTUP_TOTAL_MS < 0 )) && STARTUP_TOTAL_MS=0

  # Write state immediately so SwiftBar can reflect recording on the next tick.
  printf 'pid=%s\nwav=%s\ntarget_app=%q\ntarget_window=%q\ntarget_pid=%s\npaste_target=%q\nrecord_started_ms=%s\nstartup_total_ms=%s\nstartup_audio_ms=%s\nstartup_ffmpeg_live_ms=%s\nstartup_target_ms=%s\nstartup_audio_source=%q\n' \
    "$pid" "$wav" "" "" "" "$INLINE_PASTE_TARGET" "$record_started_ms" \
    "$STARTUP_TOTAL_MS" "$STARTUP_AUDIO_MS" "$STARTUP_FFMPEG_LIVE_MS" "$STARTUP_TARGET_MS" "$STARTUP_AUDIO_SOURCE" > "$STATE_FILE"
  rm -f "$PROCESSING_LONG_FLAG" 2>/dev/null || true
  refresh_swiftbar

  # Quick liveness check (avoid noticeable startup delay)
  ok="0"
  [[ "$TRACE" == "1" ]] && t0="$(now_ms)"
  for _ in 1 2 3 4 5 6 7 8; do
    sleep 0.02
    if kill -0 "$pid" 2>/dev/null; then
      ok="1"
      break
    fi
  done
  [[ "$TRACE" == "1" ]] && t1="$(now_ms)" && trace "ffmpeg livecheck: ok=$ok $((t1 - t0))ms"
  if [[ "$ok" != "1" ]]; then
    echo "ERROR: ffmpeg died immediately (audio index: ${DICTATE_AUDIO_INDEX:-<none>})"

    # Retry once by re-detecting the device (cache can go stale when devices connect/disconnect).
    if [[ -n "${PREFERRED_AUDIO_NAME:-}" ]]; then
      echo "Retrying audio device detection for: ${PREFERRED_AUDIO_NAME}"
      clear_audio_index_cache
      retry_audio_started_ms="$(now_ms)"
      retry_meta="$(detect_audio_index "${AUDIO_SOURCE_MODE:-auto}" "$PREFERRED_AUDIO_NAME" "${mac_name:-${CFG_AUDIO_MAC_NAME:-${CFG_AUDIO_DEVICE_NAME:-MacBook Air Microphone}}}" "${iphone_name:-${CFG_AUDIO_IPHONE_NAME:-}}" 2>/dev/null || true)"
      IFS=$'\t' read -r DICTATE_AUDIO_INDEX retry_name retry_match <<<"$retry_meta"
      STARTUP_AUDIO_MS=$(( STARTUP_AUDIO_MS + $(now_ms) - retry_audio_started_ms ))
      if [[ -n "$DICTATE_AUDIO_INDEX" ]]; then
        STARTUP_AUDIO_SOURCE="retry:detect:source(${AUDIO_SOURCE_MODE:-auto}):match(${retry_match:-unknown}):name(${retry_name:-})"
        export DICTATE_AUDIO_INDEX
        if [[ "${allow_cache:-0}" == "1" ]]; then
          write_audio_index_cache "${cache_key:-source=${AUDIO_SOURCE_MODE:-auto};preferred=${PREFERRED_AUDIO_NAME:-}}" "$DICTATE_AUDIO_INDEX" "$retry_name" "$retry_match"
        fi
        start_ffmpeg
        pid=$!
        echo "ffmpeg retry pid=$pid, wav=$wav"
        printf 'pid=%s\nwav=%s\ntarget_app=%q\ntarget_window=%q\ntarget_pid=%s\npaste_target=%q\nrecord_started_ms=%s\nstartup_total_ms=%s\nstartup_audio_ms=%s\nstartup_ffmpeg_live_ms=%s\nstartup_target_ms=%s\nstartup_audio_source=%q\n' \
          "$pid" "$wav" "" "" "" "$INLINE_PASTE_TARGET" "$record_started_ms" \
          "$STARTUP_TOTAL_MS" "$STARTUP_AUDIO_MS" "$STARTUP_FFMPEG_LIVE_MS" "$STARTUP_TARGET_MS" "$STARTUP_AUDIO_SOURCE" > "$STATE_FILE"
        refresh_swiftbar

        ok="0"
        for _ in 1 2 3 4 5 6 7 8; do
          sleep 0.02
          if kill -0 "$pid" 2>/dev/null; then
            ok="1"
            break
          fi
        done
      fi
    fi

    if [[ "$ok" != "1" ]]; then
      rm -f "$STATE_FILE" 2>/dev/null || true
      rm -f "$PROCESSING_LONG_FLAG" 2>/dev/null || true
      refresh_swiftbar
      [[ -n "${SOUND_ERROR:-}" ]] && afplay "$SOUND_ERROR" 2>/dev/null &
      echo "error" > /tmp/dictate-error.flag
      exit 1
    fi
  fi
  STARTUP_FFMPEG_LIVE_MS=$(( $(now_ms) - ffmpeg_live_started_ms ))

  # Audible cue ASAP (recording is live).
  [[ -n "${SOUND_START:-}" ]] && afplay "$SOUND_START" 2>/dev/null &

  # Capture target only for restore/origin behavior.
  target_app=""
  target_window=""
  target_pid=""
  if [[ "$INLINE_PASTE_TARGET" == "restore" ]]; then
    # Capture frontmost app, window, AND PID for paste target (done after recording starts to reduce perceived latency).
    # PID is essential when multiple instances of the same app exist (e.g., two Ghostty processes)
    t0="$(now_ms)"
    target_info="$(osascript -e '
      tell application "System Events"
        set frontApp to first process whose frontmost is true
        set appName to name of frontApp
        set appPID to unix id of frontApp
        try
          set frontWin to first window of frontApp whose focused is true
          set winName to name of frontWin
        on error
          try
            set winName to name of first window of frontApp
          on error
            set winName to ""
          end try
        end try
      end tell
      return appName & "|||" & winName & "|||" & appPID
    ' 2>/dev/null || echo "")"
    [[ "$TRACE" == "1" ]] && t1="$(now_ms)" && trace "target capture: $((t1 - t0))ms"
    STARTUP_TARGET_MS=$(( $(now_ms) - t0 ))

    target_app="${target_info%%|||*}"
    remainder="${target_info#*|||}"
    target_window="${remainder%%|||*}"
    target_pid="${remainder##*|||}"
    echo "Target app: $target_app (PID: $target_pid)"
    echo "Target window: $target_window"
  else
    STARTUP_TARGET_MS=0
    echo "Target capture skipped (inline target=current)"
  fi

  STARTUP_TOTAL_MS=$(( $(now_ms) - SCRIPT_STARTED_MS ))
  (( STARTUP_TOTAL_MS < 0 )) && STARTUP_TOTAL_MS=0
  printf 'pid=%s\nwav=%s\ntarget_app=%q\ntarget_window=%q\ntarget_pid=%s\npaste_target=%q\nrecord_started_ms=%s\nstartup_total_ms=%s\nstartup_audio_ms=%s\nstartup_ffmpeg_live_ms=%s\nstartup_target_ms=%s\nstartup_audio_source=%q\n' \
    "$pid" "$wav" "$target_app" "$target_window" "$target_pid" "$INLINE_PASTE_TARGET" "$record_started_ms" \
    "$STARTUP_TOTAL_MS" "$STARTUP_AUDIO_MS" "$STARTUP_FFMPEG_LIVE_MS" "$STARTUP_TARGET_MS" "$STARTUP_AUDIO_SOURCE" > "$STATE_FILE"
  refresh_swiftbar

  echo "State saved, recording..."
fi
