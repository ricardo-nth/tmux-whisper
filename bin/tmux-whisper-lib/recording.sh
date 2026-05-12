#!/usr/bin/env bash

# Recording helpers own the shared startup facts used by tmux and inline
# capture paths: resolved device, selector strategy, timing, and stop behavior.

recording_reset_audio_context() {
  RECORDING_AUDIO_INDEX=""
  RECORDING_AUDIO_SOURCE="(none)"
  RECORDING_AUDIO_MS="0"
  RECORDING_AUDIO_CACHE_NOTE=""
  RECORDING_AUDIO_SELECTOR=""
  RECORDING_AUDIO_SELECTOR_KIND="index"
  RECORDING_PREFERRED_AUDIO_NAME=""
}

recording_resolve_audio_context() {
  local flow="${1:-tmux}"
  local fast_cache="${2:-0}"
  recording_reset_audio_context

  local configured_audio_source mac_audio_name preferred_audio_name
  configured_audio_source="$(normalize_audio_source "${DICTATE_AUDIO_SOURCE:-${CFG_AUDIO_SOURCE:-auto}}")"
  mac_audio_name="${CFG_AUDIO_MAC_NAME:-${CFG_AUDIO_DEVICE_NAME:-MacBook Air Microphone}}"
  preferred_audio_name="${DICTATE_AUDIO_NAME:-${CFG_AUDIO_DEVICE_NAME:-MacBook Air Microphone}}"
  RECORDING_PREFERRED_AUDIO_NAME="$preferred_audio_name"

  local audio_index="${DICTATE_AUDIO_INDEX:-}"
  if [[ -n "$audio_index" ]]; then
    RECORDING_AUDIO_SOURCE="env:DICTATE_AUDIO_INDEX"
  else
    local detect_meta detect_src detect_ms audio_cache_note
    detect_meta=""
    detect_src=""
    detect_ms="0"
    audio_cache_note=""
    if bool_is_on "$fast_cache"; then
      detect_meta="$(DICTATE_AUDIO_CACHE_SKIP_VALIDATE=1 detect_audio_index 2>/dev/null || true)"
    else
      detect_meta="$(detect_audio_index 2>/dev/null || true)"
    fi
    IFS=$'\t' read -r audio_index detect_src detect_ms audio_cache_note <<<"$detect_meta"
    RECORDING_AUDIO_MS="${detect_ms:-0}"
    RECORDING_AUDIO_SOURCE="${detect_src:-detect:source(${CFG_AUDIO_SOURCE:-auto})}"
    RECORDING_AUDIO_CACHE_NOTE="${audio_cache_note:-}"
  fi

  if [[ -z "$audio_index" && -n "${CFG_AUDIO_DEVICE_INDEX:-}" ]]; then
    audio_index="$CFG_AUDIO_DEVICE_INDEX"
    RECORDING_AUDIO_SOURCE="config:audio.device_index"
  fi
  [[ -n "$audio_index" ]] || die "no audio device found. Run: tmux-whisper debug"

  RECORDING_AUDIO_INDEX="$audio_index"
  RECORDING_AUDIO_SELECTOR="$audio_index"
  RECORDING_AUDIO_SELECTOR_KIND="index"

  if [[ "$flow" == "inline" && -z "${DICTATE_AUDIO_INDEX:-}" ]]; then
    case "$configured_audio_source" in
      mac)
        if [[ -n "$mac_audio_name" ]]; then
          RECORDING_AUDIO_SELECTOR="$mac_audio_name"
          RECORDING_AUDIO_SELECTOR_KIND="name"
        fi
        ;;
      name)
        if [[ -n "$preferred_audio_name" ]]; then
          RECORDING_AUDIO_SELECTOR="$preferred_audio_name"
          RECORDING_AUDIO_SELECTOR_KIND="name"
        fi
        ;;
    esac
  fi
}

recording_retry_audio_index() {
  local preferred_audio_name="${1:-}"
  [[ -n "$preferred_audio_name" ]] || return 1

  local retry_meta retry_index retry_src retry_ms retry_note
  retry_meta="$(DICTATE_AUDIO_NAME="$preferred_audio_name" detect_audio_index 2>/dev/null || true)"
  IFS=$'\t' read -r retry_index retry_src retry_ms retry_note <<<"$retry_meta"
  [[ -n "$retry_index" ]] || return 1

  RECORDING_AUDIO_INDEX="$retry_index"
  RECORDING_AUDIO_SELECTOR="$retry_index"
  RECORDING_AUDIO_SELECTOR_KIND="index"
  RECORDING_AUDIO_MS=$(( ${RECORDING_AUDIO_MS:-0} + ${retry_ms:-0} ))
  RECORDING_AUDIO_SOURCE="retry:${retry_src:-detect:source(${CFG_AUDIO_SOURCE:-auto})}"
  RECORDING_AUDIO_CACHE_NOTE="${retry_note:-}"
  return 0
}

recording_log_tail_hint() {
  local record_log_path="${1:-}"
  [[ -n "$record_log_path" && -s "$record_log_path" ]] || return 0
  tail -n 2 "$record_log_path" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//'
}

recording_pid_is_active() {
  local target_pid="${1:-}"
  [[ -n "$target_pid" && "$target_pid" =~ ^[0-9]+$ ]] || return 1
  kill -0 "$target_pid" 2>/dev/null || return 1

  local stat
  stat="$(ps -o stat= -p "$target_pid" 2>/dev/null | tr -d '[:space:]' || true)"
  [[ "$stat" == *Z* ]] && return 1
  return 0
}

start_recording_control_fifo() {
  local prefix="${1:-${TMPDIR:-/tmp}/tmux-whisper-recording-$$}"
  RECORDING_CONTROL_FIFO=""
  RECORDING_CONTROL_KEEPER_PID=""

  local fifo
  fifo="${prefix}.control"
  rm -f "$fifo" 2>/dev/null || true
  mkfifo "$fifo" 2>/dev/null || return 1

  (
    trap '' HUP
    while :; do sleep 3600; done
  ) >"$fifo" 2>/dev/null &
  RECORDING_CONTROL_KEEPER_PID="$!"
  RECORDING_CONTROL_FIFO="$fifo"
  return 0
}

cleanup_recording_control_fifo() {
  local fifo="${1:-}"
  local keeper_pid="${2:-}"
  if [[ -n "$keeper_pid" && "$keeper_pid" =~ ^[0-9]+$ ]]; then
    kill "$keeper_pid" 2>/dev/null || true
  fi
  [[ -n "$fifo" ]] && rm -f "$fifo" 2>/dev/null || true
}

send_recording_quit() {
  local fifo="${1:-}"
  [[ -n "$fifo" && -p "$fifo" ]] || return 1

  (
    printf q >"$fifo"
  ) 2>/dev/null &
  local writer_pid="$!"
  local attempt
  for ((attempt=1; attempt<=10; attempt++)); do
    kill -0 "$writer_pid" 2>/dev/null || return 0
    sleep 0.02
  done
  kill "$writer_pid" 2>/dev/null || true
  return 1
}

terminate_recording_pid() {
  local target_pid="${1:-}"
  local requested_stop_grace_ms="${2:-}"
  local record_log_path="${3:-${RECORD_LOG:-/dev/null}}"
  local control_fifo="${4:-}"
  local control_keeper_pid="${5:-}"
  local attempt
  local stop_grace_ms
  local quit_wait_attempts="60"
  local int_wait_attempts="60"
  local term_wait_attempts="40"
  local stop_begin_ms alive_before_grace alive_after_grace signal_sent_ms exit_ms
  [[ -n "$target_pid" && "$target_pid" =~ ^[0-9]+$ ]] || return 0
  stop_grace_ms="$(resolve_stop_grace_ms "$requested_stop_grace_ms" "700")"
  stop_begin_ms="$(now_ms)"
  alive_before_grace="0"
  recording_pid_is_active "$target_pid" && alive_before_grace="1"

  if keep_logs_enabled; then
    printf "[%s] stop_recording: pid=%s grace_ms=%s quit_wait_ms=%s int_wait_ms=%s term_wait_ms=%s stop_begin_ms=%s alive_before_grace=%s control_fifo=%s\n" \
      "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$target_pid" "$stop_grace_ms" \
      "$(( quit_wait_attempts * 50 ))" "$(( int_wait_attempts * 50 ))" "$(( term_wait_attempts * 50 ))" \
      "$stop_begin_ms" "$alive_before_grace" "${control_fifo:-}" \
      >>"$record_log_path" 2>/dev/null || true
  fi

  # This grace window makes hotkey stop feel less hard cut when the user
  # finishes the last word right as they trigger stop.
  sleep_ms "$stop_grace_ms"

  alive_after_grace="0"
  recording_pid_is_active "$target_pid" && alive_after_grace="1"
  if keep_logs_enabled; then
    printf "[%s] stop_recording: after_grace pid=%s alive_after_grace=%s elapsed_ms=%s\n" \
      "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$target_pid" "$alive_after_grace" "$(( $(now_ms) - stop_begin_ms ))" \
      >>"$record_log_path" 2>/dev/null || true
  fi
  if [[ "$alive_after_grace" != "1" ]]; then
    cleanup_recording_control_fifo "$control_fifo" "$control_keeper_pid"
    return 0
  fi

  if [[ -n "$control_fifo" && -p "$control_fifo" ]]; then
    signal_sent_ms="$(now_ms)"
    if send_recording_quit "$control_fifo"; then
      if keep_logs_enabled; then
        printf "[%s] stop_recording: q_sent pid=%s fifo=%s elapsed_ms=%s\n" \
          "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$target_pid" "$control_fifo" "$(( signal_sent_ms - stop_begin_ms ))" \
          >>"$record_log_path" 2>/dev/null || true
      fi
      for ((attempt=1; attempt<=quit_wait_attempts; attempt++)); do
        if ! recording_pid_is_active "$target_pid"; then
          if keep_logs_enabled; then
            exit_ms="$(now_ms)"
            printf "[%s] stop_recording: exit_after_q pid=%s wait_ms=%s total_ms=%s\n" \
              "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$target_pid" "$(( exit_ms - signal_sent_ms ))" "$(( exit_ms - stop_begin_ms ))" \
              >>"$record_log_path" 2>/dev/null || true
          fi
          cleanup_recording_control_fifo "$control_fifo" "$control_keeper_pid"
          return 0
        fi
        sleep 0.05
      done
      if keep_logs_enabled; then
        printf "[%s] stop_recording: int_after_q_timeout pid=%s elapsed_ms=%s\n" \
          "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$target_pid" "$(( $(now_ms) - stop_begin_ms ))" \
          >>"$record_log_path" 2>/dev/null || true
      fi
    elif keep_logs_enabled; then
      printf "[%s] stop_recording: q_send_failed pid=%s fifo=%s elapsed_ms=%s\n" \
        "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$target_pid" "$control_fifo" "$(( $(now_ms) - stop_begin_ms ))" \
        >>"$record_log_path" 2>/dev/null || true
    fi
  fi

  kill -INT "$target_pid" 2>/dev/null || true
  signal_sent_ms="$(now_ms)"
  for ((attempt=1; attempt<=int_wait_attempts; attempt++)); do
    if ! recording_pid_is_active "$target_pid"; then
      if keep_logs_enabled; then
        exit_ms="$(now_ms)"
        printf "[%s] stop_recording: exit_after_int pid=%s wait_ms=%s total_ms=%s\n" \
          "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$target_pid" "$(( exit_ms - signal_sent_ms ))" "$(( exit_ms - stop_begin_ms ))" \
          >>"$record_log_path" 2>/dev/null || true
      fi
      cleanup_recording_control_fifo "$control_fifo" "$control_keeper_pid"
      return 0
    fi
    sleep 0.05
  done

  kill -TERM "$target_pid" 2>/dev/null || true
  signal_sent_ms="$(now_ms)"
  if keep_logs_enabled; then
    printf "[%s] stop_recording: term_after_int_timeout pid=%s elapsed_ms=%s\n" \
      "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$target_pid" "$(( signal_sent_ms - stop_begin_ms ))" \
      >>"$record_log_path" 2>/dev/null || true
  fi
  for ((attempt=1; attempt<=term_wait_attempts; attempt++)); do
    if ! recording_pid_is_active "$target_pid"; then
      if keep_logs_enabled; then
        exit_ms="$(now_ms)"
        printf "[%s] stop_recording: exit_after_term pid=%s wait_ms=%s total_ms=%s\n" \
          "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$target_pid" "$(( exit_ms - signal_sent_ms ))" "$(( exit_ms - stop_begin_ms ))" \
          >>"$record_log_path" 2>/dev/null || true
      fi
      cleanup_recording_control_fifo "$control_fifo" "$control_keeper_pid"
      return 0
    fi
    sleep 0.05
  done

  if keep_logs_enabled; then
    printf "[%s] stop_recording: kill_after_term_timeout pid=%s elapsed_ms=%s\n" \
      "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$target_pid" "$(( $(now_ms) - stop_begin_ms ))" \
      >>"$record_log_path" 2>/dev/null || true
  fi
  kill -KILL "$target_pid" 2>/dev/null || true
  cleanup_recording_control_fifo "$control_fifo" "$control_keeper_pid"
}
