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

if [[ "${DICTATE_TEST_FFMPEG_HOLD:-0}" == "1" && "$out" == *"whisper-dictate-"* ]]; then
  trap 'exit 0' INT TERM
  while :; do sleep 1; done
fi
exit 0
EOF

  cat >"$STUB_DIR/whisper-cli" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "${DICTATE_TEST_WHISPER_TEXT:-stub transcript}"
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

  chmod +x "$STUB_DIR/ffmpeg" "$STUB_DIR/whisper-cli" "$STUB_DIR/tmux" "$STUB_DIR/pbcopy" "$STUB_DIR/osascript"
}

CASE_DIR=""

setup_case() {
  local name="$1"
  CASE_DIR="$TMP_ROOT/$name"
  mkdir -p "$CASE_DIR"/{home,tmp,logs,models,tmux-jobs}
  mkdir -p "$CASE_DIR/config/modes/short" "$CASE_DIR/config/modes/long"

  printf '%s\n' "short" >"$CASE_DIR/config/current-mode"
  : >"$CASE_DIR/config/modes/short/prompt"
  : >"$CASE_DIR/config/modes/long/prompt"
  : >"$CASE_DIR/config/vocab"
  : >"$CASE_DIR/models/ggml-test.bin"

  export HOME="$CASE_DIR/home"
  export XDG_CONFIG_HOME="$CASE_DIR/home/.config"
  export XDG_DATA_HOME="$CASE_DIR/home/.local/share"
  export PATH="$STUB_DIR:/usr/bin:/bin"
  mkdir -p "$HOME/.local/bin"
  ln -sf "$STUB_DIR/ffmpeg" "$HOME/.local/bin/ffmpeg"
  ln -sf "$STUB_DIR/whisper-cli" "$HOME/.local/bin/whisper-cli"
  ln -sf "$STUB_DIR/tmux" "$HOME/.local/bin/tmux"
  ln -sf "$STUB_DIR/pbcopy" "$HOME/.local/bin/pbcopy"
  ln -sf "$STUB_DIR/osascript" "$HOME/.local/bin/osascript"

  export DICTATE_CONFIG_DIR="$CASE_DIR/config"
  export DICTATE_CONFIG_FILE="$CASE_DIR/config/config.toml"
  export DICTATE_LIB_PATH="$ROOT/bin/dictate-lib.sh"
  export DICTATE_STATE_FILE="$CASE_DIR/tmux.state"
  export DICTATE_TMPDIR="$CASE_DIR/tmp"
  export DICTATE_RECORD_LOG="$CASE_DIR/logs/record.log"
  export DICTATE_TRANSCRIBE_LOG="$CASE_DIR/logs/transcribe.log"
  export DICTATE_TMUX_JOBS_DIR="$CASE_DIR/tmux-jobs"
  export DICTATE_KEEP_LOGS=1
  export DICTATE_AUDIO_INDEX=0
  export DICTATE_TMUX_AUTOSEND=1
  export DICTATE_TMUX_SEND_DELAY_MS=0
  export DICTATE_TMUX_CODEX_TAB_DELAY_MS=0
  export DICTATE_INLINE_ACTIVATE_DELAY_MS=0
  export DICTATE_INLINE_SEND_DELAY_MS=0
  export DICTATE_INLINE_PASTE_TARGET=current
  export DICTATE_MODEL="$CASE_DIR/models/ggml-test.bin"
  export DICTATE_TMUX_MODEL="$CASE_DIR/models/ggml-test.bin"

  export DICTATE_TEST_FFMPEG_LOG="$CASE_DIR/logs/ffmpeg.log"
  export DICTATE_TEST_TMUX_LOG="$CASE_DIR/logs/tmux.log"
  export DICTATE_TEST_OSASCRIPT_LOG="$CASE_DIR/logs/osascript.log"
  export DICTATE_TEST_PBCOPY_OUT="$CASE_DIR/logs/pbcopy.txt"
  export DICTATE_TEST_TMUX_PANE="%1"
  export DICTATE_TEST_TMUX_PANE_CMD="bash"
  export DICTATE_TEST_FFMPEG_HOLD=0
  export DICTATE_TEST_WHISPER_TEXT="default transcript"

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
  export DICTATE_TEST_WHISPER_TEXT="tmux round ${mode}"

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
  export DICTATE_TEST_WHISPER_TEXT="codex and tmux"
  export DICTATE_INLINE_SEND_MODE="ctrl_j"
  export DICTATE_AUTOSEND=1

  printf '%s\n' 'codex -> Codex' >"$DICTATE_CONFIG_DIR/vocab"
  printf '%s\n' 'tmux -> Tmux' >"$DICTATE_CONFIG_DIR/modes/short/vocab"

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
  export DICTATE_TEST_WHISPER_TEXT="hello from inline"
  export DICTATE_INLINE_SEND_MODE="cmd_enter"
  export DICTATE_AUTOSEND=1

  local out
  out="$("$DICTATE_BIN" inline)"
  assert_contains "inline_sent_cmd_enter" "$out" "Sent (Cmd+Enter)"
  assert_file_contains "inline_osascript_send_cmd_enter" "$DICTATE_TEST_OSASCRIPT_LOG" "key code 36 using command down"
}

run_status_postprocess_round() {
  setup_case "status-postprocess"
  export DICTATE_POSTPROCESS=1
  export DICTATE_TMUX_POSTPROCESS=1

  local out
  out="$("$DICTATE_BIN" status)"
  assert_contains "status_post_inline_off" "$out" "postprocess.inline: OFF"
  assert_contains "status_post_tmux_off" "$out" "postprocess.tmux: OFF"
  assert_contains "status_post_note" "$out" "postprocess.note: disabled at runtime (CEREBRAS_API_KEY missing)"
}

run_status_model_mode_round() {
  setup_case "status-model-mode"
  export DICTATE_MODEL="small"
  export DICTATE_TMUX_MODEL="turbo"
  export DICTATE_TMUX_MODE="long"

  local out
  out="$("$DICTATE_BIN" status)"
  assert_contains "status_mode_tmux_long" "$out" "mode.tmux: long"
  assert_contains "status_model_inline_small" "$out" "model.inline: small"
  assert_contains "status_model_tmux_turbo" "$out" "model.tmux: turbo"
}

write_stubs
run_tmux_round "enter"
run_tmux_round "codex"
run_inline_vocab_round
run_inline_cmd_enter_round
run_status_postprocess_round
run_status_model_mode_round

echo "Flow parity tests passed."
