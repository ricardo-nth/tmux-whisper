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

  chmod +x "$STUB_DIR/ffmpeg" "$STUB_DIR/tmux" "$STUB_DIR/pbcopy" "$STUB_DIR/osascript" "$STUB_DIR/tmux-whisperd"
}

CASE_DIR=""

setup_case() {
  local name="$1"
  CASE_DIR="$TMP_ROOT/$name"
  mkdir -p "$CASE_DIR"/{home,tmp,logs,tmux-jobs,swift-model}
  mkdir -p "$CASE_DIR/config/modes/base" "$CASE_DIR/config/modes/chat" "$CASE_DIR/config/modes/code" "$CASE_DIR/config/modes/long"

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

  export DICTATE_CONFIG_DIR="$CASE_DIR/config"
  export DICTATE_CONFIG_FILE="$CASE_DIR/config/config.toml"
  export DICTATE_LIB_PATH="$ROOT/bin/dictate-lib.sh"
  export DICTATE_STATE_FILE="$CASE_DIR/tmux.state"
  export DICTATE_INLINE_STATE_FILE="$CASE_DIR/inline.state"
  export DICTATE_TMPDIR="$CASE_DIR/tmp"
  export DICTATE_RECORD_LOG="$CASE_DIR/logs/record.log"
  export DICTATE_TRANSCRIBE_LOG="$CASE_DIR/logs/transcribe.log"
  export DICTATE_TMUX_JOBS_DIR="$CASE_DIR/tmux-jobs"
  export DICTATE_TMUX_WHISPERD_BIN="$STUB_DIR/tmux-whisperd"
  export DICTATE_SWIFT_PARAKEET_MODEL_PATH="$CASE_DIR/swift-model"
  export DICTATE_SWIFT_PARAKEET_SOCKET_PATH="$CASE_DIR/tmp/tmux-whisperd.sock"
  export DICTATE_KEEP_LOGS=1
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
run_inline_swift_round
run_inline_swift_superseded_round
run_status_postprocess_round
run_status_model_mode_round
run_status_backend_round

echo "Flow parity tests passed."
