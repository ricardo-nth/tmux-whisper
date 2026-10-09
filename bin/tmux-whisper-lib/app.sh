#!/usr/bin/env bash

# Back-end commands for the native menu-bar app. The app owns the hotkey,
# capture, sounds and paste/send; these commands give it settings and run the
# exact inline processing pipeline (transcription, cleanup, history, usage)
# without delivering the text.

app_delivery_settings_env() {
  local autosend="${DICTATE_AUTOSEND:-${CFG_INLINE_AUTOSEND:-1}}"
  local send_mode paste_target activate_delay_ms send_delay_ms
  send_mode="$(normalize_inline_send_mode "${DICTATE_INLINE_SEND_MODE:-${CFG_INLINE_SEND_MODE:-enter}}")"
  paste_target="$(normalize_inline_paste_target "${DICTATE_INLINE_PASTE_TARGET:-${CFG_INLINE_PASTE_TARGET:-restore}}")"
  activate_delay_ms="${DICTATE_INLINE_ACTIVATE_DELAY_MS:-90}"
  send_delay_ms="${DICTATE_INLINE_SEND_DELAY_MS:-35}"
  [[ "$activate_delay_ms" =~ ^[0-9]+$ ]] || activate_delay_ms=90
  [[ "$send_delay_ms" =~ ^[0-9]+$ ]] || send_delay_ms=35
  printf 'APP_AUTOSEND=%q\nAPP_SEND_MODE=%q\nAPP_PASTE_TARGET=%q\nAPP_ACTIVATE_DELAY_MS=%q\nAPP_SEND_DELAY_MS=%q\n' \
    "$autosend" "$send_mode" "$paste_target" "$activate_delay_ms" "$send_delay_ms"
}

# Cleanup settings exactly as the CLI resolves them (env, ~/.zshenv, config),
# kept as raw strings so the app can interpret them with the CLI's own rules.
# Prints one JSON object (the "cleanup" section of app-config).
app_cleanup_settings_json() {
  APPCLEAN_CONFIG_DIR="$DICTATE_CONFIG_DIR" \
  APPCLEAN_CLEAN="${DICTATE_CLEAN:-0}" \
  APPCLEAN_REPEATS_LEVEL="${DICTATE_REPEATS_LEVEL:-${CFG_CLEAN_REPEATS_LEVEL:-1}}" \
  APPCLEAN_VOCAB_CLEAN="${DICTATE_VOCAB_CLEAN:-1}" \
  APPCLEAN_BRITISH_SPELLING="${DICTATE_BRITISH_SPELLING:-1}" \
  APPCLEAN_CODE_PARAGRAPH_MIN_WORDS="${DICTATE_CODE_PARAGRAPH_MIN_WORDS:-70}" \
  APPCLEAN_LONG_PARAGRAPH_MIN_WORDS="${DICTATE_LONG_PARAGRAPH_MIN_WORDS:-55}" \
  APPCLEAN_FORCE_MODE="${DICTATE_FORCE_MODE:-}" \
  APPCLEAN_POSTPROCESS="$(resolve_inline_postprocess_effective)" \
  python3 - <<'PYEOF'
import json, os
e = os.environ
print(json.dumps({
    "config_dir": e["APPCLEAN_CONFIG_DIR"],
    "clean": e["APPCLEAN_CLEAN"],
    "repeats_level": e["APPCLEAN_REPEATS_LEVEL"],
    "vocab_clean": e["APPCLEAN_VOCAB_CLEAN"],
    "british_spelling": e["APPCLEAN_BRITISH_SPELLING"],
    "code_paragraph_min_words": e["APPCLEAN_CODE_PARAGRAPH_MIN_WORDS"],
    "long_paragraph_min_words": e["APPCLEAN_LONG_PARAGRAPH_MIN_WORDS"],
    "force_mode": e["APPCLEAN_FORCE_MODE"] or None,
    "postprocess": e["APPCLEAN_POSTPROCESS"] == "1",
}))
PYEOF
}

# tmux-whisper app-config --json
app_config_json() {
  [[ "${1:-}" == "--json" || -z "${1:-}" ]] || die "usage: tmux-whisper app-config --json"
  need python3
  eval "$(app_delivery_settings_env)"
  local event
  local -a sound_env=()
  for event in start stop process error cancel; do
    sound_env+=("APPCFG_SOUND_${event}_PATH=$(dictate_sound_path "$event" 2>/dev/null || true)")
    if sound_enabled "$event"; then
      sound_env+=("APPCFG_SOUND_${event}_ENABLED=1")
    else
      sound_env+=("APPCFG_SOUND_${event}_ENABLED=0")
    fi
  done

  env "${sound_env[@]}" \
    APPCFG_CLI_VERSION="$TMUX_WHISPER_CLI_VERSION" \
    APPCFG_HOTKEY="${DICTATE_APP_HOTKEY:-${CFG_APP_HOTKEY:-ctrl+option+space}}" \
    APPCFG_AUTOSEND="$APP_AUTOSEND" \
    APPCFG_SEND_MODE="$APP_SEND_MODE" \
    APPCFG_PASTE_TARGET="$APP_PASTE_TARGET" \
    APPCFG_ACTIVATE_DELAY_MS="$APP_ACTIVATE_DELAY_MS" \
    APPCFG_SEND_DELAY_MS="$APP_SEND_DELAY_MS" \
    APPCFG_PROCESS_SOUND="${CFG_INLINE_PROCESS_SOUND:-1}" \
    APPCFG_CLEANUP_JSON="$(app_cleanup_settings_json)" \
    python3 - <<'PYEOF'
import json, os
e = os.environ
def flag(name):
    return e.get(name, "0") == "1"
sounds = {}
for event in ("start", "stop", "process", "error", "cancel"):
    path = e.get(f"APPCFG_SOUND_{event}_PATH", "")
    sounds[event] = {"enabled": flag(f"APPCFG_SOUND_{event}_ENABLED") and bool(path), "path": path or None}
print(json.dumps({
    "schema_version": 1,
    "cli_version": e["APPCFG_CLI_VERSION"],
    "hotkey": e["APPCFG_HOTKEY"],
    "sounds": sounds,
    "inline": {
        "autosend": flag("APPCFG_AUTOSEND"),
        "send_mode": e["APPCFG_SEND_MODE"],
        "paste_target": e["APPCFG_PASTE_TARGET"],
        "process_sound": flag("APPCFG_PROCESS_SOUND"),
        "activate_delay_ms": int(e["APPCFG_ACTIVATE_DELAY_MS"]),
        "send_delay_ms": int(e["APPCFG_SEND_DELAY_MS"]),
    },
    "cleanup": json.loads(e["APPCFG_CLEANUP_JSON"]),
}))
PYEOF
}

# tmux-whisper inline process <wav> [--app NAME] [--record-ms N]
#   [--startup-ms N] [--started-at-ms EPOCH_MS] --json
# Prints one JSON object: {ok, status, text, raw_text, mode, message,
# delivery: {...}, timings: {...}}. Human progress goes to the log, never
# stdout. The caller owns the WAV file.
inline_process_json() {
  local wav="" app="" record_ms="0" startup_ms="0" started_at_ms=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json) ;;
      --app) [[ $# -ge 2 ]] || die "inline process: --app requires a value"; app="$2"; shift ;;
      --record-ms) [[ $# -ge 2 ]] || die "inline process: --record-ms requires a value"; record_ms="$2"; shift ;;
      --startup-ms) [[ $# -ge 2 ]] || die "inline process: --startup-ms requires a value"; startup_ms="$2"; shift ;;
      --started-at-ms) [[ $# -ge 2 ]] || die "inline process: --started-at-ms requires a value"; started_at_ms="$2"; shift ;;
      -*) die "inline process: unknown option: $1" ;;
      *) [[ -z "$wav" ]] || die "inline process: only one WAV file"; wav="$1" ;;
    esac
    shift
  done
  [[ -n "$wav" ]] || die "usage: tmux-whisper inline process <wav> [--app NAME] [--record-ms N] --json"
  [[ -f "$wav" ]] || die "inline process: not a file: $wav"
  [[ "$record_ms" =~ ^[0-9]+$ ]] || record_ms=0
  [[ "$startup_ms" =~ ^[0-9]+$ ]] || startup_ms=0
  [[ "$started_at_ms" =~ ^[0-9]+$ ]] || started_at_ms=""
  need python3

  local log work_wav rc=0
  log="$(mktemp "${TMPDIR:-/tmp}/tmux-whisper-app-process.XXXXXX")" || die "inline process: cannot create a temporary file"
  # The pipeline pads/trims its WAV in place and removes it afterwards; work
  # on a private copy so the caller's file is left alone.
  work_wav="$(mktemp "${TMPDIR:-/tmp}/tmux-whisper-app-take.XXXXXX")" || die "inline process: cannot create a temporary file"
  # This runs as its own CLI process, so an EXIT trap also covers early exits.
  # shellcheck disable=SC2064
  trap "rm -f '$log' '$work_wav'" EXIT
  cp "$wav" "$work_wav" || die "inline process: cannot read $wav"
  INLINE_DELIVERY_MODE="external"
  INLINE_EXTERNAL_TEXT=""
  INLINE_EXTERNAL_RAW_TEXT=""
  INLINE_EXTERNAL_MODE=""
  INLINE_EXTERNAL_TIMINGS=""
  # An empty session id is never "superseded" by CLI inline recordings.
  process_inline_recording "$work_wav" "$app" "$(current_transcribe_model_label)" "$record_ms" \
    "$startup_ms" "0" "0" "0" "app:avaudioengine" "" "" "self" "$started_at_ms" >"$log" 2>&1 || rc=$?

  eval "$(app_delivery_settings_env)"
  APPPROC_RC="$rc" \
  APPPROC_TEXT="$INLINE_EXTERNAL_TEXT" \
  APPPROC_RAW="$INLINE_EXTERNAL_RAW_TEXT" \
  APPPROC_MODE="$INLINE_EXTERNAL_MODE" \
  APPPROC_TIMINGS="$INLINE_EXTERNAL_TIMINGS" \
  APPPROC_LOG="$log" \
  APPPROC_AUTOSEND="$APP_AUTOSEND" \
  APPPROC_SEND_MODE="$APP_SEND_MODE" \
  APPPROC_PASTE_TARGET="$APP_PASTE_TARGET" \
  APPPROC_ACTIVATE_DELAY_MS="$APP_ACTIVATE_DELAY_MS" \
  APPPROC_SEND_DELAY_MS="$APP_SEND_DELAY_MS" \
  python3 - <<'PYEOF'
import json, os
e = os.environ
lines = [l.strip() for l in open(e["APPPROC_LOG"], encoding="utf-8", errors="replace") if l.strip()]
text = e.get("APPPROC_TEXT", "")
ok = e.get("APPPROC_RC") == "0" and bool(text.strip())
if ok:
    status = "ok"
elif any("No speech detected" in l for l in lines):
    status = "no_speech"
elif any(l.startswith("Skipping stale inline result") for l in lines):
    status = "superseded"
else:
    status = "failed"
timings = {}
for part in e.get("APPPROC_TIMINGS", "").split():
    key, _, value = part.partition("=")
    if value.isdigit():
        timings[key] = int(value)
message = None if ok else (next((l for l in reversed(lines) if not l.startswith("⏳")), None) or "processing failed")
print(json.dumps({
    "ok": ok,
    "status": status,
    "text": text if ok else "",
    "raw_text": e.get("APPPROC_RAW", "") if ok else "",
    "mode": e.get("APPPROC_MODE") or None,
    "message": message,
    "delivery": {
        "autosend": e.get("APPPROC_AUTOSEND") == "1",
        "send_mode": e["APPPROC_SEND_MODE"],
        "paste_target": e["APPPROC_PASTE_TARGET"],
        "activate_delay_ms": int(e["APPPROC_ACTIVATE_DELAY_MS"]),
        "send_delay_ms": int(e["APPPROC_SEND_DELAY_MS"]),
    },
    "timings": timings,
}, ensure_ascii=False))
PYEOF
  rm -f "$log" "$work_wav" 2>/dev/null || true
  return 0
}

# tmux-whisper inline cleanup [--app NAME] --json   (transcript on stdin)
# Runs only the deterministic text cleanup of an inline take (artefacts,
# fillers/repeats, mode, vocab, paragraphs, British spelling), never the LLM.
# Used to generate Lowkey's TextPipeline parity fixtures and for shadow
# compares. Prints {ok, status, raw_text, text, mode, cleanup}.
inline_cleanup_json() {
  local app=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json) ;;
      --app) [[ $# -ge 2 ]] || die "inline cleanup: --app requires a value"; app="$2"; shift ;;
      *) die "usage: tmux-whisper inline cleanup [--app NAME] --json < transcript" ;;
    esac
    shift
  done
  need python3

  local raw txt="" final="" mode="" status="no_speech"
  # $(...) drops trailing newlines, like the transcription capture does.
  raw="$(cat)"
  txt="$(cleanup_raw_transcript "$raw" "0")"
  if [[ -n "${txt//[[:space:]]/}" ]]; then
    status="ok"
    mode="$(resolve_inline_mode "$app")"
    final="$(finish_transcript_text "$txt" "$mode" "0")"
  fi

  APPCLEANUP_STATUS="$status" \
  APPCLEANUP_RAW="$txt" \
  APPCLEANUP_TEXT="$final" \
  APPCLEANUP_MODE="$mode" \
  APPCLEANUP_SETTINGS="$(app_cleanup_settings_json)" \
  python3 - <<'PYEOF'
import json, os
e = os.environ
ok = e["APPCLEANUP_STATUS"] == "ok"
print(json.dumps({
    "ok": ok,
    "status": e["APPCLEANUP_STATUS"],
    "raw_text": e["APPCLEANUP_RAW"] if ok else "",
    "text": e["APPCLEANUP_TEXT"] if ok else "",
    "mode": e["APPCLEANUP_MODE"] if ok else None,
    "cleanup": json.loads(e["APPCLEANUP_SETTINGS"]),
}))
PYEOF
}
