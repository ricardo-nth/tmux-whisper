#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DICTATE_BIN="$ROOT/bin/tmux-whisper"
TMP_ROOT="$(mktemp -d)"
STUB_DIR="$TMP_ROOT/stubs"
mkdir -p "$STUB_DIR"

cleanup() {
  set +e
  if [[ -d "$TMP_ROOT" ]]; then
    while IFS= read -r sf; do
      [[ -f "$sf" ]] || continue
      unset pid wav
      # shellcheck disable=SC1090
      . "$sf" 2>/dev/null || true
      if [[ -n "${pid:-}" && "$pid" =~ ^[0-9]+$ ]]; then
        local proc_cmd
        proc_cmd="$(/bin/ps -p "$pid" -o command= 2>/dev/null || true)"
        if [[ "$proc_cmd" == *"/ffmpeg"* ]]; then
          kill -INT "$pid" 2>/dev/null || true
        fi
      fi
      [[ -n "${wav:-}" ]] && rm -f "$wav" 2>/dev/null || true
    done < <(find "$TMP_ROOT" -type f -name '*.state' 2>/dev/null || true)
    rm -rf "$TMP_ROOT"
  fi
}
trap cleanup EXIT

pass() {
  echo "PASS: $1"
}

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

assert_contains() {
  local name="$1"
  local haystack="$2"
  local needle="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "Expected to find: $needle" >&2
    echo "In output: $haystack" >&2
    fail "$name"
  fi
  pass "$name"
}

assert_file_contains() {
  local name="$1"
  local file="$2"
  local needle="$3"
  if ! grep -Fq "$needle" "$file"; then
    echo "Missing pattern in $file: $needle" >&2
    fail "$name"
  fi
  pass "$name"
}

assert_file_not_contains() {
  local name="$1"
  local file="$2"
  local needle="$3"
  if grep -Fq "$needle" "$file"; then
    echo "Unexpected pattern in $file: $needle" >&2
    fail "$name"
  fi
  pass "$name"
}

assert_equals() {
  local name="$1"
  local actual="$2"
  local expected="$3"
  if [[ "$actual" != "$expected" ]]; then
    echo "Expected: $expected" >&2
    echo "Actual:   $actual" >&2
    fail "$name"
  fi
  pass "$name"
}

wait_for_file_contains() {
  local file="$1"
  local needle="$2"
  local tries="${3:-120}"
  local i
  for ((i = 0; i < tries; i++)); do
    if [[ -f "$file" ]] && grep -Fq "$needle" "$file"; then
      return 0
    fi
    sleep 0.05
  done
  return 1
}

wait_for_file_not_contains() {
  local file="$1"
  local needle="$2"
  local tries="${3:-120}"
  local i
  for ((i = 0; i < tries; i++)); do
    if [[ -f "$file" ]] && ! grep -Fq "$needle" "$file"; then
      return 0
    fi
    sleep 0.05
  done
  return 1
}

wait_for_matching_file() {
  local dir="$1"
  local pattern="$2"
  local tries="${3:-120}"
  local i
  for ((i = 0; i < tries; i++)); do
    if find "$dir" -name "$pattern" -type f -print -quit 2>/dev/null | grep -q .; then
      return 0
    fi
    sleep 0.05
  done
  return 1
}

wait_for_no_matching_file() {
  local dir="$1"
  local pattern="$2"
  local tries="${3:-120}"
  local i
  for ((i = 0; i < tries; i++)); do
    if [[ ! -d "$dir" ]] || ! find "$dir" -name "$pattern" -type f | grep -q .; then
      return 0
    fi
    sleep 0.05
  done
  return 1
}

wait_for_absent() {
  local path="$1"
  local tries="${2:-120}"
  local i
  for ((i = 0; i < tries; i++)); do
    [[ ! -e "$path" ]] && return 0
    sleep 0.05
  done
  return 1
}

write_stubs() {
  cat >"$STUB_DIR/ffmpeg" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "$*" == *"-list_devices true"* ]]; then
  cat >&2 <<'OUT'
[AVFoundation input device @ 0x0] AVFoundation audio devices:
[AVFoundation input device @ 0x0] [0] MacBook Air Microphone
[AVFoundation input device @ 0x0] AVFoundation video devices:
[AVFoundation input device @ 0x0] [0] FaceTime HD Camera
OUT
  exit 0
fi

if [[ -n "${DICTATE_TEST_FFMPEG_LOG:-}" ]]; then
  printf '%s\n' "$*" >>"$DICTATE_TEST_FFMPEG_LOG"
fi

out="${!#}"
mkdir -p "$(dirname "$out")"
printf '%s\n' "stub-wav" >"$out"

if [[ "${DICTATE_TEST_FFMPEG_HOLD:-0}" == "1" && ( "$out" == *"whisper-dictate-"* || "$out" == *"dictate-inline-"* ) ]]; then
  trap 'exit 0' INT TERM
  while :; do sleep 1; done
fi
exit 0
EOF

  cat >"$STUB_DIR/tmux" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

log="${DICTATE_TEST_TMUX_LOG:-}"
cmd="${1:-}"
[[ -n "$cmd" ]] || exit 0
shift || true

if [[ -n "$log" ]]; then
  printf 'tmux %s' "$cmd" >>"$log"
  for arg in "$@"; do
    printf ' %s' "$arg" >>"$log"
  done
  printf '\n' >>"$log"
fi

case "$cmd" in
  display-message)
    fmt=""
    for arg in "$@"; do
      fmt="$arg"
    done
    case "$fmt" in
      '#{pane_id}')
        printf '%s\n' "${DICTATE_TEST_TMUX_PANE:-%1}"
        ;;
      '#{pane_current_path}')
        printf '%s\n' "${DICTATE_TEST_TMUX_PATH:-/tmp/project}"
        ;;
      '#{pane_title}')
        printf '%s\n' "${DICTATE_TEST_TMUX_TITLE:-main}"
        ;;
      '#{pane_current_command}')
        printf '%s\n' "${DICTATE_TEST_TMUX_PANE_CMD:-bash}"
        ;;
      '#{pane_tty}')
        printf '%s\n' "${DICTATE_TEST_TMUX_TTY:-}"
        ;;
      '#{pane_pid}')
        printf '%s\n' "${DICTATE_TEST_TMUX_PANE_PID:-}"
        ;;
    esac
    ;;
esac
exit 0
EOF

  cat >"$STUB_DIR/pbcopy" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cat >"${DICTATE_TEST_PBCOPY_OUT:-/tmp/dictate-test-pbcopy.out}"
EOF

  cat >"$STUB_DIR/osascript" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
joined="$*"
if [[ -n "${DICTATE_TEST_OSASCRIPT_LOG:-}" ]]; then
  printf '%s\n' "$joined" >>"$DICTATE_TEST_OSASCRIPT_LOG"
fi
if [[ "$joined" == *"get name of first process whose frontmost is true"* ]]; then
  printf '%s\n' "${DICTATE_TEST_FRONT_APP:-Ghostty}"
fi
exit 0
EOF

  cat >"$STUB_DIR/afplay" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ -n "${DICTATE_TEST_SOUND_LOG:-}" ]]; then
  printf '%s\n' "${1:-}" >>"$DICTATE_TEST_SOUND_LOG"
fi
exit 0
EOF

  cat >"$STUB_DIR/tmux-whisperd" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

cmd="${1:-}"
shift || true

case "$cmd" in
  serve)
    socket_path=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --socket)
          socket_path="${2:-}"
          shift 2
          ;;
        *)
          echo "unknown arg: $1" >&2
          exit 2
          ;;
      esac
    done
    [[ -n "$socket_path" ]] || { echo "missing socket path" >&2; exit 2; }
    python3 - "$socket_path" <<'PYEOF'
import json
import os
import socket
import sys

socket_path = sys.argv[1]
os.makedirs(os.path.dirname(socket_path), exist_ok=True)
try:
    os.unlink(socket_path)
except FileNotFoundError:
    pass

server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
server.bind(socket_path)
server.listen(5)
transcribe_count = 0
delay_values = [s.strip() for s in os.environ.get("DICTATE_TEST_SWIFT_DELAY_SEQUENCE", "").split("|")]
text_values = [s for s in os.environ.get("DICTATE_TEST_SWIFT_TEXT_SEQUENCE", "").split("|")]

while True:
    conn, _ = server.accept()
    try:
        data = b""
        while b"\n" not in data:
            chunk = conn.recv(4096)
            if not chunk:
                break
            data += chunk
        if not data:
            continue
        req = json.loads(data.split(b"\n", 1)[0].decode("utf-8"))
        if req.get("op") == "ping":
            resp = {
                "id": req.get("id"),
                "ok": True,
                "engine": "swift_parakeet",
                "message": "ok",
            }
        elif os.environ.get("DICTATE_TEST_SWIFT_DAEMON_FAIL", "0") == "1":
            resp = {
                "id": req.get("id"),
                "ok": False,
                "engine": "swift_parakeet",
                "error_code": "forced_error",
                "message": "forced daemon failure",
            }
        else:
            if req.get("op") == "transcribe" and req.get("flow") != "warmup":
                transcribe_count += 1
                idx = transcribe_count - 1
                if idx < len(delay_values) and delay_values[idx]:
                    try:
                        import time
                        time.sleep(float(delay_values[idx]))
                    except Exception:
                        pass
                text_value = os.environ.get("DICTATE_TEST_SWIFT_TEXT", "swift transcript")
                if idx < len(text_values) and text_values[idx]:
                    text_value = text_values[idx]
            elif req.get("op") == "transcribe":
                text_value = ""
            else:
                text_value = os.environ.get("DICTATE_TEST_SWIFT_TEXT", "swift transcript")
            resp = {
                "id": req.get("id"),
                "ok": True,
                "engine": "swift_parakeet",
                "model": os.path.basename(req.get("model_path") or "parakeet-test"),
                "text": text_value,
                "duration_ms": 7,
            }
        conn.sendall(json.dumps(resp).encode("utf-8") + b"\n")
    finally:
        conn.close()
PYEOF
    ;;
  version|--version)
    printf '%s\n' "tmux-whisperd test-stub"
    ;;
  *)
    echo "unknown command: $cmd" >&2
    exit 2
    ;;
esac
EOF

  chmod +x "$STUB_DIR/ffmpeg" "$STUB_DIR/tmux" "$STUB_DIR/pbcopy" "$STUB_DIR/osascript" "$STUB_DIR/afplay" "$STUB_DIR/tmux-whisperd"
}

CASE_DIR=""

setup_case() {
  local name="$1"
  local socket_tag
  CASE_DIR="$TMP_ROOT/$name"
  mkdir -p "$CASE_DIR"/{home,tmp,logs,tmux-jobs,swift-model}
  mkdir -p "$CASE_DIR/config/modes/base" "$CASE_DIR/config/modes/chat" "$CASE_DIR/config/modes/code" "$CASE_DIR/config/modes/long"

  # Keep the stub daemon socket short enough for macOS AF_UNIX limits.
  socket_tag="$(printf '%s' "$name" | cksum | cut -d' ' -f1)"
  [[ -n "$socket_tag" ]] || socket_tag="dictatetest"

  printf '%s\n' "code" >"$CASE_DIR/config/current-mode"
  : >"$CASE_DIR/config/modes/base/prompt"
  : >"$CASE_DIR/config/modes/chat/prompt"
  : >"$CASE_DIR/config/modes/code/prompt"
  : >"$CASE_DIR/config/modes/long/prompt"
  printf '%s\n' "inline" >"$CASE_DIR/config/modes/base/flows"
  printf '%s\n' "Messages" >"$CASE_DIR/config/modes/chat/apps"
  printf '%s\n' "inline" >"$CASE_DIR/config/modes/chat/flows"
  : >"$CASE_DIR/config/vocab"

  export HOME="$CASE_DIR/home"
  export XDG_CONFIG_HOME="$CASE_DIR/home/.config"
  export XDG_DATA_HOME="$CASE_DIR/home/.local/share"
  export PATH="$STUB_DIR:/usr/bin:/bin"
  mkdir -p "$HOME/.local/bin"
  ln -sf "$STUB_DIR/ffmpeg" "$HOME/.local/bin/ffmpeg"
  ln -sf "$STUB_DIR/tmux" "$HOME/.local/bin/tmux"
  ln -sf "$STUB_DIR/pbcopy" "$HOME/.local/bin/pbcopy"
  ln -sf "$STUB_DIR/osascript" "$HOME/.local/bin/osascript"
  ln -sf "$STUB_DIR/afplay" "$HOME/.local/bin/afplay"
  mkdir -p "$HOME/.local/share/sounds/dictate"
  : >"$HOME/.local/share/sounds/dictate/start.wav"
  : >"$HOME/.local/share/sounds/dictate/stop.wav"
  : >"$HOME/.local/share/sounds/dictate/process.wav"
  : >"$HOME/.local/share/sounds/dictate/error.wav"
  : >"$HOME/.local/share/sounds/dictate/cancel.wav"

  export DICTATE_CONFIG_DIR="$CASE_DIR/config"
  export DICTATE_CONFIG_FILE="$CASE_DIR/config/config.toml"
  export DICTATE_LIB_PATH="$ROOT/bin/dictate-lib.sh"
  export DICTATE_STATE_FILE="$CASE_DIR/tmux.state"
  export DICTATE_INLINE_STATE_FILE="$CASE_DIR/inline.state"
  export DICTATE_PROCESSING_DIR="$CASE_DIR/processing"
  export DICTATE_PROCESSED_FLAG="$CASE_DIR/processed.flag"
  export DICTATE_PROCESSING_LONG_FLAG="$CASE_DIR/processing-long.flag"
  export DICTATE_TMPDIR="$CASE_DIR/tmp"
  export DICTATE_RECORD_LOG="$CASE_DIR/logs/record.log"
  export DICTATE_TRANSCRIBE_LOG="$CASE_DIR/logs/transcribe.log"
  export DICTATE_TMUX_JOBS_DIR="$CASE_DIR/tmux-jobs"
  export DICTATE_TMUX_WHISPERD_BIN="$STUB_DIR/tmux-whisperd"
  export DICTATE_SWIFT_PARAKEET_MODEL_PATH="$CASE_DIR/swift-model"
  export DICTATE_SWIFT_PARAKEET_SOCKET_PATH="$TMP_ROOT/${socket_tag}.sock"
  export DICTATE_KEEP_LOGS=1
  unset DICTATE_HISTORY_AUDIO_RETENTION_DAYS
  export DICTATE_AUDIO_INDEX=0
  export DICTATE_TMUX_AUTOSEND=1
  export DICTATE_TMUX_SEND_DELAY_MS=0
  export DICTATE_TMUX_CODEX_TAB_DELAY_MS=0
  export DICTATE_INLINE_ACTIVATE_DELAY_MS=0
  export DICTATE_INLINE_SEND_DELAY_MS=0
  export DICTATE_INLINE_PASTE_TARGET=current
  unset DICTATE_SWIFT_PARAKEET_MODEL_VERSION

  export DICTATE_TEST_FFMPEG_LOG="$CASE_DIR/logs/ffmpeg.log"
  export DICTATE_TEST_TMUX_LOG="$CASE_DIR/logs/tmux.log"
  export DICTATE_TEST_OSASCRIPT_LOG="$CASE_DIR/logs/osascript.log"
  export DICTATE_TEST_PBCOPY_OUT="$CASE_DIR/logs/pbcopy.txt"
  export DICTATE_TEST_SOUND_LOG="$CASE_DIR/logs/sounds.log"
  export DICTATE_TEST_TMUX_PANE="%1"
  export DICTATE_TEST_TMUX_PANE_CMD="bash"
  export DICTATE_TEST_FFMPEG_HOLD=0
  export DICTATE_TEST_SWIFT_TEXT="default transcript"
  unset DICTATE_TEST_SWIFT_DAEMON_FAIL
  unset DICTATE_TEST_SWIFT_DELAY_SEQUENCE
  unset DICTATE_TEST_SWIFT_TEXT_SEQUENCE

  unset CEREBRAS_API_KEY
  unset TMUX
  unset TMUX_PANE
}

run_tmux_round() {
  local mode="$1"
  setup_case "tmux-${mode}"
  export TMUX="1"
  export TMUX_PANE="%1"
  export DICTATE_TEST_FFMPEG_HOLD=1
  export DICTATE_TMUX_SEND_MODE="$mode"
  export DICTATE_TEST_SWIFT_TEXT="tmux round ${mode}"

  local start_out
  start_out="$("$DICTATE_BIN" toggle)"
  assert_contains "tmux_start_${mode}" "$start_out" "RECORDING"
  wait_for_file_contains "$DICTATE_TEST_FFMPEG_LOG" "aresample=async=1000:first_pts=0" || fail "tmux_capture_async_resampler_${mode}"
  pass "tmux_capture_async_resampler_${mode}"

  # shellcheck disable=SC1090
  . "$DICTATE_STATE_FILE"
  local job_file="$DICTATE_TMUX_JOBS_DIR/$job_id"
  assert_file_contains "tmux_job_recording_${mode}" "$job_file" "status=recording"

  local status_out
  status_out="$("$DICTATE_BIN" status)"
  assert_contains "tmux_queue_status_${mode}" "$status_out" "tmux queue: total=1 recording=1 processing=0"

  local stop_out
  stop_out="$("$DICTATE_BIN" stop)"
  assert_contains "tmux_stop_${mode}" "$stop_out" "STOPPED"

  wait_for_file_contains "$DICTATE_TEST_TMUX_LOG" "tmux delete-buffer" || fail "tmux_background_complete_${mode}"
  wait_for_absent "$job_file" || fail "tmux_job_removed_${mode}"

  assert_file_contains "tmux_paste_${mode}" "$DICTATE_TEST_TMUX_LOG" "tmux paste-buffer"
  assert_file_contains "tmux_send_enter_${mode}" "$DICTATE_TEST_TMUX_LOG" "tmux send-keys -t %1 Enter"
  if [[ "$mode" == "enter" ]]; then
    assert_file_not_contains "tmux_no_codex_tab_${mode}" "$DICTATE_TEST_TMUX_LOG" "tmux send-keys -t %1 C-i"
  else
    assert_file_contains "tmux_codex_tab_${mode}" "$DICTATE_TEST_TMUX_LOG" "tmux send-keys -t %1 C-i"
  fi
}

run_inline_vocab_round() {
  setup_case "inline-vocab"
  export DICTATE_TEST_SWIFT_TEXT="codex and tmux"
  export DICTATE_INLINE_SEND_MODE="ctrl_j"
  export DICTATE_AUTOSEND=1

  printf '%s\n' 'codex -> Codex' >"$DICTATE_CONFIG_DIR/vocab"
  printf '%s\n' 'tmux -> Tmux' >"$DICTATE_CONFIG_DIR/modes/code/vocab"

  local out
  out="$("$DICTATE_BIN" inline)"
  assert_contains "inline_sent_ctrl_j" "$out" "Sent (Ctrl+J)"
  assert_file_contains "inline_osascript_paste" "$DICTATE_TEST_OSASCRIPT_LOG" 'keystroke "v" using command down'
  assert_file_contains "inline_osascript_send_ctrl_j" "$DICTATE_TEST_OSASCRIPT_LOG" 'keystroke "j" using control down'

  local copied
  copied="$(cat "$DICTATE_TEST_PBCOPY_OUT")"
  assert_contains "inline_vocab_corrections" "$copied" "Codex and Tmux"
}

run_inline_cmd_enter_round() {
  setup_case "inline-cmd-enter"
  export DICTATE_TEST_SWIFT_TEXT="hello from inline"
  export DICTATE_INLINE_SEND_MODE="cmd_enter"
  export DICTATE_AUTOSEND=1

  local out
  out="$("$DICTATE_BIN" inline)"
  assert_contains "inline_sent_cmd_enter" "$out" "Sent (Cmd+Enter)"
  assert_file_contains "inline_osascript_send_cmd_enter" "$DICTATE_TEST_OSASCRIPT_LOG" "key code 36 using command down"
}

run_inline_auto_mode_round() {
  setup_case "inline-auto-mode"
  printf '%s\n' "auto" >"$DICTATE_CONFIG_DIR/current-mode"
  printf '%s\n' 'plain dictation -> Plain dictation' >"$DICTATE_CONFIG_DIR/modes/base/vocab"
  printf "%s\n" "what's up -> WhatsApp style" >"$DICTATE_CONFIG_DIR/modes/chat/vocab"
  export DICTATE_AUTOSEND=1
  export DICTATE_TEST_SWIFT_TEXT_SEQUENCE="plain dictation|what's up"

  export DICTATE_TEST_FRONT_APP="Preview"
  local out copied
  out="$("$DICTATE_BIN" inline)"
  assert_contains "inline_auto_base_sent" "$out" "Sent"
  copied="$(cat "$DICTATE_TEST_PBCOPY_OUT")"
  assert_contains "inline_auto_base_vocab" "$copied" "Plain dictation"

  export DICTATE_TEST_FRONT_APP="Messages"
  out="$("$DICTATE_BIN" inline)"
  assert_contains "inline_auto_chat_sent" "$out" "Sent"
  copied="$(cat "$DICTATE_TEST_PBCOPY_OUT")"
  assert_contains "inline_auto_chat_vocab" "$copied" "WhatsApp style"
}

run_inline_toggle_round() {
  setup_case "inline-toggle"
  export DICTATE_TEST_FFMPEG_HOLD=1
  export DICTATE_TEST_SWIFT_TEXT="inline background transcript"
  export DICTATE_AUTOSEND=1

  local start_out
  start_out="$("$DICTATE_BIN" inline toggle)"
  assert_contains "inline_toggle_start" "$start_out" "RECORDING"
  wait_for_file_contains "$DICTATE_TEST_FFMPEG_LOG" "aresample=async=1000:first_pts=0" || fail "inline_toggle_async_resampler"
  pass "inline_toggle_async_resampler"

  [[ -f "$DICTATE_INLINE_STATE_FILE" ]] || fail "inline_toggle_state_created"
  pass "inline_toggle_state_created"

  local stop_out
  stop_out="$("$DICTATE_BIN" inline toggle)"
  assert_contains "inline_toggle_stop" "$stop_out" "STOPPED"

  wait_for_absent "$DICTATE_INLINE_STATE_FILE" || fail "inline_toggle_state_removed"
  wait_for_file_contains "$DICTATE_TEST_PBCOPY_OUT" "inline background transcript" || fail "inline_toggle_background_complete"
  wait_for_file_contains "$DICTATE_TEST_OSASCRIPT_LOG" 'keystroke "v" using command down' || fail "inline_toggle_osascript_paste"
  pass "inline_toggle_osascript_paste"
  wait_for_file_contains "$DICTATE_TEST_OSASCRIPT_LOG" 'key code 36' || fail "inline_toggle_send_enter"
  pass "inline_toggle_send_enter"
}

run_inline_toggle_grace_override_round() {
  setup_case "inline-toggle-grace-override"
  export DICTATE_TEST_FFMPEG_HOLD=1
  export DICTATE_TEST_SWIFT_TEXT="inline grace override transcript"
  export DICTATE_STOP_GRACE_MS=5
  export DICTATE_INLINE_STOP_GRACE_MS=123
  export DICTATE_AUTOSEND=1

  local start_out stop_out inline_record_log
  inline_record_log="$CASE_DIR/tmp/whisper-dictate-inline.record.log"

  start_out="$("$DICTATE_BIN" inline toggle)"
  assert_contains "inline_toggle_grace_start" "$start_out" "RECORDING"

  stop_out="$("$DICTATE_BIN" inline toggle)"
  assert_contains "inline_toggle_grace_stop" "$stop_out" "STOPPED"

  assert_file_contains "inline_toggle_grace_record_log" "$inline_record_log" "grace_ms=123"
}

run_inline_toggle_process_sound_immediate_round() {
  setup_case "inline-toggle-process-sound"
  export DICTATE_TEST_FFMPEG_HOLD=1
  export DICTATE_TEST_SWIFT_TEXT="inline process sound transcript"
  export DICTATE_AUTOSEND=1

  local start_out stop_out inline_record_log
  inline_record_log="$CASE_DIR/tmp/whisper-dictate-inline.record.log"

  start_out="$("$DICTATE_BIN" inline toggle)"
  assert_contains "inline_toggle_process_sound_start" "$start_out" "RECORDING"

  stop_out="$("$DICTATE_BIN" inline toggle)"
  assert_contains "inline_toggle_process_sound_stop" "$stop_out" "STOPPED"

  wait_for_file_contains "$DICTATE_TEST_SOUND_LOG" "process.wav" || fail "inline_toggle_process_sound_logged"
  assert_file_contains "inline_toggle_process_sound_record_log" "$inline_record_log" "inline_process_sound: immediate_on_stop"

  local process_line stop_line
  process_line="$(grep -n 'inline_process_sound: immediate_on_stop' "$inline_record_log" | head -n 1 | cut -d: -f1)"
  stop_line="$(grep -n 'stop_recording:' "$inline_record_log" | head -n 1 | cut -d: -f1)"
  [[ -n "$process_line" && -n "$stop_line" && "$process_line" -lt "$stop_line" ]] || fail "inline_toggle_process_sound_before_grace"
  pass "inline_toggle_process_sound_before_grace"
}

run_inline_processing_marker_until_paste_round() {
  setup_case "inline-processing-marker-until-paste"
  export DICTATE_TEST_FFMPEG_HOLD=1
  export DICTATE_TEST_SWIFT_TEXT="inline marker transcript"
  export DICTATE_TEST_SWIFT_DELAY_SEQUENCE="1.5"
  export DICTATE_AUTOSEND=1

  local start_out stop_out marker marker_pid swiftbar_out
  start_out="$("$DICTATE_BIN" inline toggle)"
  assert_contains "inline_processing_marker_start" "$start_out" "RECORDING"

  stop_out="$("$DICTATE_BIN" inline toggle)"
  assert_contains "inline_processing_marker_stop" "$stop_out" "STOPPED"

  wait_for_matching_file "$DICTATE_PROCESSING_DIR" 'inline-*' || fail "inline_processing_marker_created"
  marker="$(find "$DICTATE_PROCESSING_DIR" -name 'inline-*' -type f | head -n 1)"
  assert_file_contains "inline_processing_marker_kind" "$marker" "kind=inline"
  marker_pid="$(sed -n 's/^pid=//p' "$marker" | head -n 1)"
  [[ "$marker_pid" =~ ^[0-9]+$ ]] || fail "inline_processing_marker_pid_present"
  kill -0 "$marker_pid" 2>/dev/null || fail "inline_processing_marker_pid_live"
  pass "inline_processing_marker_pid_live"
  swiftbar_out="$(DICTATE_BIN="$DICTATE_BIN" bash "$ROOT/integrations/tmux-whisper-status.0.2s.sh")"
  assert_contains "inline_processing_marker_swiftbar_state" "$swiftbar_out" "Processing (1)"

  wait_for_file_contains "$DICTATE_TEST_PBCOPY_OUT" "inline marker transcript" 240 || fail "inline_processing_marker_paste_done"
  wait_for_no_matching_file "$DICTATE_PROCESSING_DIR" 'inline-*' || fail "inline_processing_marker_removed_after_paste"
  [[ -f "$DICTATE_PROCESSED_FLAG" ]] || fail "inline_processing_marker_processed_flag"
  pass "inline_processing_marker_processed_flag"
}

run_inline_processing_marker_immediate_after_stop_round() {
  setup_case "inline-processing-marker-immediate"
  export DICTATE_TEST_FFMPEG_HOLD=1
  export DICTATE_TEST_SWIFT_TEXT="inline immediate marker transcript"
  export DICTATE_TEST_SWIFT_DELAY_SEQUENCE="0.35"
  export DICTATE_INLINE_STOP_GRACE_MS=1200
  export DICTATE_AUTOSEND=1

  local start_out stop_out_file stop_pid marker marker_pid swiftbar_out
  stop_out_file="$CASE_DIR/logs/stop.out"
  start_out="$("$DICTATE_BIN" inline toggle)"
  assert_contains "inline_processing_immediate_start" "$start_out" "RECORDING"

  "$DICTATE_BIN" inline toggle >"$stop_out_file" 2>&1 &
  stop_pid="$!"

  wait_for_absent "$DICTATE_INLINE_STATE_FILE" || fail "inline_processing_immediate_state_removed"
  wait_for_matching_file "$DICTATE_PROCESSING_DIR" 'inline-*' || fail "inline_processing_immediate_marker_created"
  marker="$(find "$DICTATE_PROCESSING_DIR" -name 'inline-*' -type f | head -n 1)"
  assert_file_contains "inline_processing_immediate_marker_kind" "$marker" "kind=inline"
  marker_pid="$(sed -n 's/^pid=//p' "$marker" | head -n 1)"
  [[ "$marker_pid" =~ ^[0-9]+$ ]] || fail "inline_processing_immediate_marker_pid_present"
  kill -0 "$marker_pid" 2>/dev/null || fail "inline_processing_immediate_marker_pid_live"
  pass "inline_processing_immediate_marker_pid_live"
  swiftbar_out="$(DICTATE_BIN="$DICTATE_BIN" bash "$ROOT/integrations/tmux-whisper-status.0.2s.sh")"
  assert_contains "inline_processing_immediate_swiftbar_state" "$swiftbar_out" "Processing"

  wait "$stop_pid"
  assert_file_contains "inline_processing_immediate_stop_output" "$stop_out_file" "STOPPED"
  wait_for_file_contains "$DICTATE_TEST_PBCOPY_OUT" "inline immediate marker transcript" || fail "inline_processing_immediate_paste_done"
}

run_inline_audio_cache_note_round() {
  setup_case "inline-audio-cache"
  export DICTATE_TEST_FFMPEG_HOLD=1
  export DICTATE_TEST_SWIFT_TEXT="inline audio cache transcript"
  export DICTATE_AUTOSEND=1
  unset DICTATE_AUDIO_INDEX

  cat >"$CASE_DIR/config/config.toml" <<'EOF'
[meta]
config_version = 1

[audio]
source = "mac"
mac_name = "MacBook Air Microphone"
EOF

  mkdir -p "$CASE_DIR/config/.cache"
  cat >"$CASE_DIR/config/.cache/audio-index.sh" <<'EOF'
CACHED_AUDIO_KEY=source=mac\;preferred=MacBook\ Air\ Microphone\;mac=MacBook\ Air\ Microphone\;iphone=
CACHED_AUDIO_NAME=MacBook\ Air\ Microphone
CACHED_AUDIO_MATCH=mac
CACHED_AUDIO_INDEX=1
CACHED_AUDIO_AT=2026-03-20T08:47:56Z
EOF
  touch -t 202603200847 "$CASE_DIR/config/.cache/audio-index.sh" 2>/dev/null || true

  local start_out stop_out inline_record_log
  inline_record_log="$CASE_DIR/tmp/whisper-dictate-inline.record.log"

  start_out="$("$DICTATE_BIN" inline toggle)"
  assert_contains "inline_audio_cache_start" "$start_out" "RECORDING"

  stop_out="$("$DICTATE_BIN" inline toggle)"
  assert_contains "inline_audio_cache_stop" "$stop_out" "STOPPED"

  assert_file_contains "inline_audio_cache_log_note" "$inline_record_log" "audio cache: stale cache invalidated: cached idx=1 name=MacBook Air Microphone match=mac at=2026-03-20T08:47:56Z; re-resolved idx=0 match=mac name=MacBook Air Microphone"
}

run_inline_audio_cache_refresh_round() {
  setup_case "inline-audio-cache-refresh"
  export DICTATE_TEST_FFMPEG_HOLD=1
  export DICTATE_TEST_SWIFT_TEXT="inline audio cache refresh transcript"
  export DICTATE_AUTOSEND=1
  unset DICTATE_AUDIO_INDEX

  cat >"$CASE_DIR/config/config.toml" <<'EOF'
[meta]
config_version = 1

[audio]
source = "mac"
mac_name = "MacBook Air Microphone"
EOF

  mkdir -p "$CASE_DIR/config/.cache"
  cat >"$CASE_DIR/config/.cache/audio-index.sh" <<'EOF'
CACHED_AUDIO_KEY=source=mac\;preferred=MacBook\ Air\ Microphone\;mac=MacBook\ Air\ Microphone\;iphone=
CACHED_AUDIO_NAME=MacBook\ Air\ Microphone
CACHED_AUDIO_MATCH=mac
CACHED_AUDIO_INDEX=0
CACHED_AUDIO_AT=2026-03-20T08:47:56Z
EOF

  local start_out stop_out inline_record_log cache_file
  inline_record_log="$CASE_DIR/tmp/whisper-dictate-inline.record.log"
  cache_file="$CASE_DIR/config/.cache/audio-index.sh"

  start_out="$("$DICTATE_BIN" inline toggle)"
  assert_contains "inline_audio_cache_refresh_start" "$start_out" "RECORDING"
  assert_file_not_contains "inline_audio_cache_refresh_no_stale_note" "$inline_record_log" "stale cache invalidated"
  assert_file_contains "inline_audio_cache_refresh_index" "$cache_file" "CACHED_AUDIO_INDEX=0"
  wait_for_file_not_contains "$cache_file" "CACHED_AUDIO_AT=2026-03-20T08:47:56Z" || fail "inline_audio_cache_refresh_timestamp_rewritten"
  pass "inline_audio_cache_refresh_timestamp_rewritten"

  stop_out="$("$DICTATE_BIN" inline toggle)"
  assert_contains "inline_audio_cache_refresh_stop" "$stop_out" "STOPPED"
}

run_inline_keep_logs_archive_round() {
  setup_case "inline-keep-logs-archive"
  export DICTATE_TEST_FFMPEG_HOLD=1
  export DICTATE_TEST_SWIFT_TEXT="inline archive transcript"
  export DICTATE_AUTOSEND=1

  local start_out stop_out archive_dir wav_archive meta_archive transcribe_archive
  archive_dir="$CASE_DIR/config/history/inline-debug"

  start_out="$("$DICTATE_BIN" inline toggle)"
  assert_contains "inline_archive_start" "$start_out" "RECORDING"

  stop_out="$("$DICTATE_BIN" inline toggle)"
  assert_contains "inline_archive_stop" "$stop_out" "STOPPED"

  wait_for_file_contains "$DICTATE_TEST_PBCOPY_OUT" "inline archive transcript" || fail "inline_archive_complete"
  wait_for_matching_file "$archive_dir" '*.meta' || fail "inline_archive_meta_ready"

  wav_archive="$(find "$archive_dir" -name '*.wav' -type f | head -n 1)"
  meta_archive="$(find "$archive_dir" -name '*.meta' -type f | head -n 1)"
  transcribe_archive="$(find "$archive_dir" -name '*.transcribe.log' -type f | head -n 1)"

  [[ -n "$wav_archive" && -f "$wav_archive" ]] || fail "inline_archive_wav_exists"
  pass "inline_archive_wav_exists"
  [[ -n "$meta_archive" && -f "$meta_archive" ]] || fail "inline_archive_meta_exists"
  pass "inline_archive_meta_exists"
  [[ -n "$transcribe_archive" && -f "$transcribe_archive" ]] || fail "inline_archive_transcribe_exists"
  pass "inline_archive_transcribe_exists"
  assert_file_contains "inline_archive_meta_status" "$meta_archive" "status=ok"
  assert_file_contains "inline_archive_meta_stop_grace" "$meta_archive" "stop_grace_ms="
  assert_file_contains "inline_archive_meta_capture_bytes" "$meta_archive" "capture_wav_bytes="
  assert_file_contains "inline_archive_meta_archive_bytes" "$meta_archive" "archive_wav_bytes="
  assert_file_contains "inline_archive_meta_retention_days" "$meta_archive" "wav_retention_days=2"
  assert_file_contains "inline_archive_meta_retention_note" "$meta_archive" "retention_note="
  assert_file_contains "inline_archive_record_snapshot" "${meta_archive%.meta}.record.log" "inline_capture_snapshot:"
  assert_file_contains "inline_archive_stop_after_grace_logged" "${meta_archive%.meta}.record.log" "after_grace"
}

run_inline_audio_retention_round() {
  setup_case "inline-audio-retention"
  export DICTATE_TEST_FFMPEG_HOLD=1
  export DICTATE_TEST_SWIFT_TEXT="inline retention transcript"
  export DICTATE_AUTOSEND=1
  export DICTATE_HISTORY_AUDIO_RETENTION_DAYS=0

  local start_out stop_out archive_dir wav_archive meta_archive history_file
  archive_dir="$CASE_DIR/config/history/inline-debug"

  start_out="$("$DICTATE_BIN" inline toggle)"
  assert_contains "inline_audio_retention_start" "$start_out" "RECORDING"

  stop_out="$("$DICTATE_BIN" inline toggle)"
  assert_contains "inline_audio_retention_stop" "$stop_out" "STOPPED"

  wait_for_file_contains "$DICTATE_TEST_PBCOPY_OUT" "inline retention transcript" || fail "inline_audio_retention_complete"
  wait_for_matching_file "$archive_dir" '*.meta' || fail "inline_audio_retention_meta_ready"
  wait_for_matching_file "$CASE_DIR/config/history" '*.json' || fail "inline_audio_retention_history_ready"

  wav_archive="$(find "$archive_dir" -name '*.wav' -type f | head -n 1)"
  [[ -z "$wav_archive" ]] || fail "inline_audio_retention_wav_pruned"
  pass "inline_audio_retention_wav_pruned"

  meta_archive="$(find "$archive_dir" -name '*.meta' -type f | head -n 1)"
  assert_file_contains "inline_audio_retention_meta_kept" "$meta_archive" "wav_retention_days=0"
  assert_file_contains "inline_audio_retention_meta_archive_bytes" "$meta_archive" "archive_wav_bytes="

  history_file="$(find "$CASE_DIR/config/history" -maxdepth 1 -name '*.json' -type f | head -n 1)"
  wait_for_file_contains "$history_file" "\"audio\": {" || fail "inline_audio_retention_history_audio_ready"
  pass "inline_audio_retention_history_audio_ready"
  assert_file_contains "inline_audio_retention_history_audio" "$history_file" "\"audio\": {"
  assert_file_contains "inline_audio_retention_history_retention" "$history_file" "\"wav_retention_days\": 0"
  assert_file_contains "inline_audio_retention_history_record_ms" "$history_file" "\"record_ms\":"
}

run_inline_swift_round() {
  setup_case "inline-swift"
  export DICTATE_TEST_SWIFT_TEXT="swift backend transcript"
  export DICTATE_AUTOSEND=1

  local out
  out="$("$DICTATE_BIN" inline)"
  assert_contains "inline_swift_sent" "$out" "Sent"

  local copied
  copied="$(cat "$DICTATE_TEST_PBCOPY_OUT")"
  assert_contains "inline_swift_transcript" "$copied" "swift backend transcript"
  assert_file_contains "inline_swift_async_resampler" "$DICTATE_TEST_FFMPEG_LOG" "aresample=async=1000:first_pts=0"
  assert_file_contains "inline_swift_tail_pad_ffmpeg" "$DICTATE_TEST_FFMPEG_LOG" "anullsrc=r=16000:cl=mono"
}

run_inline_swift_superseded_round() {
  setup_case "inline-swift-superseded"
  export DICTATE_SWIFT_PARAKEET_SOCKET_PATH="$TMP_ROOT/iss.sock"
  export DICTATE_TEST_FFMPEG_HOLD=1
  export DICTATE_AUTOSEND=1
  export DICTATE_TEST_SWIFT_TEXT_SEQUENCE="first cold transcript|second fresh transcript"
  export DICTATE_TEST_SWIFT_DELAY_SEQUENCE="0.35|0"

  local out
  out="$("$DICTATE_BIN" inline toggle)"
  assert_contains "inline_swift_superseded_start_first" "$out" "RECORDING"
  out="$("$DICTATE_BIN" inline toggle)"
  assert_contains "inline_swift_superseded_stop_first" "$out" "STOPPED"

  out="$("$DICTATE_BIN" inline toggle)"
  assert_contains "inline_swift_superseded_start_second" "$out" "RECORDING"
  out="$("$DICTATE_BIN" inline toggle)"
  assert_contains "inline_swift_superseded_stop_second" "$out" "STOPPED"

  wait_for_file_contains "$DICTATE_TEST_PBCOPY_OUT" "second fresh transcript" || fail "inline_swift_superseded_second_complete"
  sleep 0.5

  local copied paste_count send_count
  copied="$(cat "$DICTATE_TEST_PBCOPY_OUT")"
  assert_contains "inline_swift_superseded_final_clipboard" "$copied" "second fresh transcript"
  if [[ "$copied" == *"first cold transcript"* ]]; then
    fail "inline_swift_superseded_old_clipboard_suppressed"
  fi
  pass "inline_swift_superseded_old_clipboard_suppressed"

  paste_count="$(grep -c 'keystroke "v" using command down' "$DICTATE_TEST_OSASCRIPT_LOG" 2>/dev/null || true)"
  send_count="$(grep -c 'key code 36' "$DICTATE_TEST_OSASCRIPT_LOG" 2>/dev/null || true)"
  assert_equals "inline_swift_superseded_single_paste" "$paste_count" "1"
  assert_equals "inline_swift_superseded_single_send" "$send_count" "1"
}

run_tmux_audio_cache_note_round() {
  setup_case "tmux-audio-cache"
  export TMUX="1"
  export TMUX_PANE="%1"
  export DICTATE_TEST_FFMPEG_HOLD=1
  unset DICTATE_AUDIO_INDEX

  cat >"$CASE_DIR/config/config.toml" <<'EOF'
[meta]
config_version = 1

[audio]
source = "mac"
mac_name = "MacBook Air Microphone"
EOF

  mkdir -p "$CASE_DIR/config/.cache"
  cat >"$CASE_DIR/config/.cache/audio-index.sh" <<'EOF'
CACHED_AUDIO_KEY=source=mac\;preferred=MacBook\ Air\ Microphone\;mac=MacBook\ Air\ Microphone\;iphone=
CACHED_AUDIO_NAME=MacBook\ Air\ Microphone
CACHED_AUDIO_MATCH=mac
CACHED_AUDIO_INDEX=1
CACHED_AUDIO_AT=2026-03-20T08:47:56Z
EOF

  local start_out stop_out
  start_out="$("$DICTATE_BIN" toggle)"
  assert_contains "tmux_audio_cache_start" "$start_out" "RECORDING"
  assert_file_contains "tmux_audio_cache_log_note" "$DICTATE_RECORD_LOG" "audio cache: stale cache invalidated: cached idx=1 name=MacBook Air Microphone match=mac at=2026-03-20T08:47:56Z; re-resolved idx=0 match=mac name=MacBook Air Microphone"
  assert_file_contains "tmux_audio_cache_rewritten_index" "$CASE_DIR/config/.cache/audio-index.sh" "CACHED_AUDIO_INDEX=0"

  stop_out="$("$DICTATE_BIN" stop)"
  assert_contains "tmux_audio_cache_stop" "$stop_out" "STOPPED"
}

run_status_postprocess_round() {
  setup_case "status-postprocess"
  export DICTATE_POSTPROCESS=1
  export DICTATE_TMUX_POSTPROCESS=1

  local out
  out="$("$DICTATE_BIN" status)"
  assert_contains "status_summary_ready" "$out" "state: ready"
  assert_contains "status_summary_backend_cold" "$out" "backend_readiness: cold"
  assert_contains "status_post_inline_off" "$out" "postprocess.inline: OFF"
  assert_contains "status_post_tmux_off" "$out" "postprocess.tmux: OFF"
  assert_contains "status_mode_prompt_inline_inactive" "$out" "mode_prompt.inline: inactive"
  assert_contains "status_mode_prompt_tmux_inactive" "$out" "mode_prompt.tmux: inactive"
  assert_contains "status_budget_profile_short" "$out" "budget_profile.short:"
  assert_contains "status_budget_auto_threshold" "$out" "budget.auto_long_words_threshold:"
  assert_contains "status_post_note" "$out" "postprocess.note: disabled at runtime (CEREBRAS_API_KEY missing)"
}

run_status_model_mode_round() {
  setup_case "status-model-mode"
  export DICTATE_TMUX_MODE="long"

  local out
  out="$("$DICTATE_BIN" status)"
  assert_contains "status_backend_swift" "$out" "backend: swift_parakeet"
  assert_contains "status_mode_tmux_long" "$out" "mode.tmux: long"
  assert_contains "status_model_swift_path" "$out" "swift_parakeet.model: $CASE_DIR/swift-model (v3)"
}

run_status_backend_round() {
  setup_case "status-backend"
  local out
  out="$("$DICTATE_BIN" status)"
  assert_contains "status_backend_summary_headline" "$out" "headline: Dictation is ready, but the backend is cold."
  assert_contains "status_backend_requested" "$out" "backend: swift_parakeet"
  assert_contains "status_backend_model" "$out" "swift_parakeet.model: $CASE_DIR/swift-model (v3)"
}

write_stubs
run_tmux_round "enter"
run_tmux_round "codex"
run_inline_vocab_round
run_inline_cmd_enter_round
run_inline_auto_mode_round
run_inline_toggle_round
run_inline_toggle_grace_override_round
run_inline_toggle_process_sound_immediate_round
run_inline_processing_marker_immediate_after_stop_round
run_inline_processing_marker_until_paste_round
run_inline_audio_cache_note_round
run_inline_audio_cache_refresh_round
run_inline_keep_logs_archive_round
run_inline_audio_retention_round
run_inline_swift_round
run_inline_swift_superseded_round
run_tmux_audio_cache_note_round
run_status_postprocess_round
run_status_model_mode_round
run_status_backend_round

echo "Flow parity tests passed."
