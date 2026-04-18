#!/usr/bin/env bash

detect_install_channel() {
  local bin_path="${1:-}"
  case "$bin_path" in
    /opt/homebrew/*|/usr/local/Homebrew/*|/usr/local/opt/*|/usr/local/bin/*)
      echo "homebrew"
      ;;
    "$HOME/.local/bin/"*)
      echo "local-user"
      ;;
    *)
      echo "custom"
      ;;
  esac
}

debug() {
  echo "Tmux Whisper debug"
  echo ""

  load_backend_runtime_cache >/dev/null 2>&1 || true

  local dictate_bin ffmpeg_bin whisper_bin python_bin swift_bin install_channel
  dictate_bin="$(command -v tmux-whisper 2>/dev/null || true)"
  ffmpeg_bin="$(command -v ffmpeg 2>/dev/null || true)"
  whisper_bin="$(command -v whisper-cli 2>/dev/null || true)"
  python_bin="$(command -v python3 2>/dev/null || true)"
  swift_bin="$(command -v swift 2>/dev/null || true)"
  install_channel="$(detect_install_channel "$dictate_bin")"

  echo "Binaries:"
  echo "  tmux-whisper: ${dictate_bin:-'(not found)'}"
  echo "  ffmpeg:  ${ffmpeg_bin:-'(not found)'}"
  echo "  whisper-cli (legacy): ${whisper_bin:-'(not found, optional)'}"
  echo "  python3: ${python_bin:-'(not found)'}"
  echo "  swift:   ${swift_bin:-'(not found)'}"
  echo "  channel: $install_channel"
  echo "  lib:     $DICTATE_LIB_PATH $([[ -r "$DICTATE_LIB_PATH" ]] && echo '(ok)' || echo '(missing)')"
  echo "  internal_lib: $DICTATE_INTERNAL_LIB_DIR $([[ -d "$DICTATE_INTERNAL_LIB_DIR" ]] && echo '(ok)' || echo '(missing)')"
  echo ""

  local models_dir backend_requested swift_model_path swift_model_version swift_socket_path swift_root swift_binary swift_models_dir
  models_dir="$(expand_path "${CFG_WHISPER_MODELS_DIR:-$DEFAULT_WHISPER_MODELS_DIR}")"
  swift_models_dir="$(expand_path "$DEFAULT_SWIFT_PARAKEET_MODELS_DIR")"
  backend_requested="$(resolve_transcribe_backend)"
  swift_model_path="$(resolve_swift_parakeet_model_path 2>/dev/null || true)"
  swift_model_version="$(resolve_swift_parakeet_model_version "${swift_model_path:-}")"
  swift_socket_path="$(resolve_swift_parakeet_socket_path)"
  swift_root="$(resolve_tmux_whisperd_root 2>/dev/null || true)"
  swift_binary="${DICTATE_TMUX_WHISPERD_BIN:-${swift_root:+$swift_root/.build/release/tmux-whisperd}}"
  local model_count="0"
  local show_legacy_runtime="0"
  if [[ -d "$models_dir" ]]; then
    model_count="$(find "$models_dir" -maxdepth 1 -type f -name 'ggml-*.bin' | wc -l | tr -d ' ')"
  fi
  if [[ "$backend_requested" != "swift_parakeet" ]]; then
    show_legacy_runtime="1"
  else
    local legacy_override
    for legacy_override in \
      DICTATE_MODEL DICTATE_TMUX_MODEL \
      DICTATE_THREADS DICTATE_BEAM_SIZE DICTATE_BEST_OF DICTATE_GPU \
      DICTATE_VAD DICTATE_VAD_MODEL DICTATE_VAD_THRESHOLD \
      DICTATE_VAD_MIN_SPEECH_MS DICTATE_VAD_MIN_SILENCE_MS DICTATE_VAD_SPEECH_PAD_MS
    do
      if [[ -n "${!legacy_override-}" ]]; then
        show_legacy_runtime="1"
        break
      fi
    done
  fi

  echo "Paths:"
  echo "  config_dir:   $DICTATE_CONFIG_DIR $([[ -d "$DICTATE_CONFIG_DIR" ]] && echo '(ok)' || echo '(missing)')"
  echo "  config_file:  $DICTATE_CONFIG_FILE $([[ -f "$DICTATE_CONFIG_FILE" ]] && echo '(ok)' || echo '(missing)')"
  echo "  modes_dir:    $DICTATE_CONFIG_DIR/modes $([[ -d "$DICTATE_CONFIG_DIR/modes" ]] && echo '(ok)' || echo '(missing)')"
  echo "  vocab_file:   $DICTATE_CONFIG_DIR/vocab $([[ -f "$DICTATE_CONFIG_DIR/vocab" ]] && echo '(ok)' || echo '(missing)')"
  echo "  legacy_models_dir: $models_dir ($model_count models)"
  echo "  parakeet_dir: $swift_models_dir"
  echo "  backend:      $backend_requested"
  echo "  whisperd_src: ${swift_root:-<none>} $([[ -n "$swift_root" && -f "$swift_root/Package.swift" ]] && echo '(ok)' || echo '(missing)')"
  echo "  whisperd_bin: ${swift_binary:-<none>} $([[ -n "$swift_binary" && -x "$swift_binary" ]] && echo '(ok)' || echo '(not built)')"
  echo "  whisperd_sock:${swift_socket_path:-<none>} $([[ -S "$swift_socket_path" ]] && echo '(live)' || echo '(offline)')"
  echo "  parakeet_mod: ${swift_model_path:-<none>} $([[ -n "$swift_model_path" && -d "$swift_model_path" ]] && echo "(ok, ${swift_model_version})" || echo '(missing)')"
  echo "  raycast_dir:  $DICTATE_CONFIG_DIR/integrations/raycast $([[ -d "$DICTATE_CONFIG_DIR/integrations/raycast" ]] && echo '(ok)' || echo '(missing)')"
  echo "  swiftbar_plg: $HOME/.config/swiftbar/plugins/tmux-whisper-status.0.2s.sh $([[ -f "$HOME/.config/swiftbar/plugins/tmux-whisper-status.0.2s.sh" ]] && echo '(ok)' || echo '(missing)')"
  echo "  backend.last: requested=${DICTATE_LAST_BACKEND_REQUESTED:-<none>} used=${DICTATE_LAST_BACKEND_USED:-<none>} model=${DICTATE_LAST_BACKEND_MODEL:-<none>}"
  [[ -n "${DICTATE_LAST_BACKEND_FALLBACK_REASON:-}" ]] && echo "  backend.note: ${DICTATE_LAST_BACKEND_FALLBACK_REASON}"
  echo ""

  echo "Env overrides:"
  echo "  DICTATE_AUDIO_SOURCE=${DICTATE_AUDIO_SOURCE:-}"
  echo "  DICTATE_AUDIO_INDEX=${DICTATE_AUDIO_INDEX:-}"
  echo "  DICTATE_AUDIO_NAME=${DICTATE_AUDIO_NAME:-}"
  echo "  DICTATE_BACKEND=${DICTATE_BACKEND:-}"
  echo "  DICTATE_SILENCE_TRIM=${DICTATE_SILENCE_TRIM:-}"
  echo "  DICTATE_TRIM_WITH_POSTPROCESS=${DICTATE_TRIM_WITH_POSTPROCESS:-}"
  echo "  DICTATE_REPEATS_LEVEL=${DICTATE_REPEATS_LEVEL:-}"
  echo "  DICTATE_REPEATS_WITH_POSTPROCESS=${DICTATE_REPEATS_WITH_POSTPROCESS:-}"
  echo "  DICTATE_POSTPROCESS=${DICTATE_POSTPROCESS:-}"
  echo "  DICTATE_VOCAB_CLEAN=${DICTATE_VOCAB_CLEAN:-}"
  echo "  DICTATE_TMUX_POSTPROCESS=${DICTATE_TMUX_POSTPROCESS:-}"
  echo "  DICTATE_TMUX_AUTOSEND=${DICTATE_TMUX_AUTOSEND:-}"
  echo "  DICTATE_TMUX_PASTE_TARGET=${DICTATE_TMUX_PASTE_TARGET:-}"
  echo "  DICTATE_TMUX_SEND_MODE=${DICTATE_TMUX_SEND_MODE:-}"
  echo "  DICTATE_TMUX_SEND_DELAY_MS=${DICTATE_TMUX_SEND_DELAY_MS:-}"
  echo "  DICTATE_TMUX_CODEX_TAB_DELAY_MS=${DICTATE_TMUX_CODEX_TAB_DELAY_MS:-}"
  echo "  DICTATE_INLINE_PROCESS_SOUND=${DICTATE_INLINE_PROCESS_SOUND:-}"
  echo "  DICTATE_INLINE_PASTE_TARGET=${DICTATE_INLINE_PASTE_TARGET:-}"
  echo "  DICTATE_INLINE_ACTIVATE_DELAY_MS=${DICTATE_INLINE_ACTIVATE_DELAY_MS:-}"
  echo "  DICTATE_INLINE_SEND_DELAY_MS=${DICTATE_INLINE_SEND_DELAY_MS:-}"
  echo "  DICTATE_INLINE_SEND_MODE=${DICTATE_INLINE_SEND_MODE:-}"
  echo "  DICTATE_TMUX_PROCESS_SOUND=${DICTATE_TMUX_PROCESS_SOUND:-}"
  echo "  DICTATE_TMUX_MODE=${DICTATE_TMUX_MODE:-}"
  echo "  DICTATE_TMUX_MODEL=${DICTATE_TMUX_MODEL:-}"
  echo "  DICTATE_SWIFT_PARAKEET_MODEL_PATH=${DICTATE_SWIFT_PARAKEET_MODEL_PATH:-}"
  echo "  DICTATE_SWIFT_PARAKEET_MODEL_VERSION=${DICTATE_SWIFT_PARAKEET_MODEL_VERSION:-}"
  echo "  DICTATE_SWIFT_PARAKEET_SOCKET_PATH=${DICTATE_SWIFT_PARAKEET_SOCKET_PATH:-}"
  echo "  DICTATE_LLM_MAX_TOKENS=${DICTATE_LLM_MAX_TOKENS:-}"
  echo "  DICTATE_LLM_CHUNK_WORDS=${DICTATE_LLM_CHUNK_WORDS:-}"
  echo "  DICTATE_BRITISH_SPELLING=${DICTATE_BRITISH_SPELLING:-}"
  echo "  DICTATE_GPU=${DICTATE_GPU:-}"
  echo "  DICTATE_KEEP_LOGS=${DICTATE_KEEP_LOGS:-}"
  echo "  DICTATE_TARGET_APP=${DICTATE_TARGET_APP:-}"
  echo "  DICTATE_TARGET_PANE=${DICTATE_TARGET_PANE:-}"
  echo ""

  echo "Config:"
  echo "  audio.source=${CFG_AUDIO_SOURCE:-auto}"
  echo "  audio.device_name=${CFG_AUDIO_DEVICE_NAME:-}"
  echo "  audio.mac_name=${CFG_AUDIO_MAC_NAME:-}"
  echo "  audio.iphone_name=${CFG_AUDIO_IPHONE_NAME:-}"
  echo "  audio.device_index=${CFG_AUDIO_DEVICE_INDEX:-}"
  echo "  audio.silence_trim=${CFG_AUDIO_SILENCE_TRIM:-0}"
  echo "  audio.silence_trim_mode=${CFG_AUDIO_SILENCE_TRIM_MODE:-edges}"
  echo "  audio.silence_threshold_db=${CFG_AUDIO_SILENCE_THRESHOLD_DB:--60}"
  echo "  audio.silence_min_ms=${CFG_AUDIO_SILENCE_MIN_MS:-250}"
  echo "  audio.silence_keep_ms=${CFG_AUDIO_SILENCE_KEEP_MS:-50}"
  echo "  clean.repeats_level=${CFG_CLEAN_REPEATS_LEVEL:-1}"
  local cfg_schema_status cfg_schema_version
  cfg_schema_status="$(config_schema_status)"
  cfg_schema_version="$(config_schema_version_label)"
  echo "  meta.config_version=${cfg_schema_version} (expected v${DICTATE_CONFIG_SCHEMA_VERSION}, status=${cfg_schema_status})"
  if [[ "$show_legacy_runtime" == "1" ]]; then
    echo "  whisper.backend=${CFG_WHISPER_BACKEND:-swift_parakeet}"
    echo "  whisper.threads=${CFG_WHISPER_THREADS:-5}"
    echo "  whisper.beam_size=${CFG_WHISPER_BEAM_SIZE:-1}"
    echo "  whisper.best_of=${CFG_WHISPER_BEST_OF:-1}"
    echo "  whisper.vad=${CFG_WHISPER_VAD_ENABLED:-0}"
    echo "  whisper.vad_model=${CFG_WHISPER_VAD_MODEL:-}"
    echo "  whisper.vad_threshold=${CFG_WHISPER_VAD_THRESHOLD:-0.5}"
    echo "  whisper.vad_min_speech_ms=${CFG_WHISPER_VAD_MIN_SPEECH_MS:-250}"
    echo "  whisper.vad_min_silence_ms=${CFG_WHISPER_VAD_MIN_SILENCE_MS:-100}"
    echo "  whisper.vad_speech_pad_ms=${CFG_WHISPER_VAD_SPEECH_PAD_MS:-30}"
  fi
  echo "  swift_parakeet.model_path=${CFG_SWIFT_PARAKEET_MODEL_PATH:-}"
  echo "  swift_parakeet.model_version=${CFG_SWIFT_PARAKEET_MODEL_VERSION:-}"
  echo "  swift_parakeet.socket_path=${CFG_SWIFT_PARAKEET_SOCKET_PATH:-$DICTATE_CONFIG_DIR/.cache/tmux-whisperd.sock}"
  echo "  postprocess.enabled=${CFG_POSTPROCESS_ENABLED:-0}"
  echo "  postprocess.llm=${CFG_POSTPROCESS_LLM:-}"
  echo "  postprocess.max_tokens=${CFG_POSTPROCESS_MAX_TOKENS:-}"
  echo "  postprocess.chunk_words=${CFG_POSTPROCESS_CHUNK_WORDS:-}"
  echo "  postprocess.budget_long_words_threshold=${CFG_POSTPROCESS_BUDGET_LONG_WORDS_THRESHOLD:-120}"
  echo "  inline.autosend=${CFG_INLINE_AUTOSEND:-1}"
  echo "  inline.process_sound=${CFG_INLINE_PROCESS_SOUND:-1}"
  echo "  inline.paste_target=$(inline_paste_target_label "${CFG_INLINE_PASTE_TARGET:-restore}")"
  echo "  inline.send_mode=$(inline_send_mode_label "${CFG_INLINE_SEND_MODE:-enter}")"
  echo "  tmux.autosend=${CFG_TMUX_AUTOSEND:-1}"
  echo "  tmux.paste_target=${CFG_TMUX_PASTE_TARGET:-origin}"
  echo "  tmux.postprocess=${CFG_TMUX_POSTPROCESS:-0}"
  echo "  tmux.process_sound=${CFG_TMUX_PROCESS_SOUND:-0}"
  echo "  tmux.mode=${CFG_TMUX_MODE:-code}"
  if [[ "$show_legacy_runtime" == "1" ]]; then
    echo "  tmux.model=${CFG_TMUX_MODEL:-base}"
  fi
  echo "  tmux.send_mode=${CFG_TMUX_SEND_MODE:-auto}"
  echo "  integrations.swiftbar.enabled=${CFG_SWIFTBAR_ENABLED:-1}"
  echo "  debug.keep_logs=${CFG_DEBUG_KEEP_LOGS:-0}"
  echo ""

  echo "ffmpeg devices (trimmed):"
  if [[ -n "$ffmpeg_bin" ]]; then
    devices
  else
    echo "  ffmpeg not found; skipping device enumeration."
  fi
  echo ""

  local src="(none)"
  local idx="${DICTATE_AUDIO_INDEX:-}"
  if [[ -n "$idx" ]]; then
    src="env:DICTATE_AUDIO_INDEX"
  elif [[ -n "${CFG_AUDIO_DEVICE_INDEX:-}" ]]; then
    idx="$CFG_AUDIO_DEVICE_INDEX"
    src="config:audio.device_index"
  else
    if [[ -n "$ffmpeg_bin" && -n "$python_bin" ]]; then
      local detect_meta detect_src
      detect_meta="$(detect_audio_index 2>/dev/null || true)"
      IFS=$'\t' read -r idx detect_src _ <<<"$detect_meta"
      if [[ -n "$idx" ]]; then
        src="${detect_src:-detect:source(${CFG_AUDIO_SOURCE:-auto})}"
      fi
    else
      src="detect skipped (missing ffmpeg/python3)"
    fi
  fi

  echo "Resolved audio index: ${idx:-<none>} (source: $src)"
  if [[ -z "$idx" ]]; then
    echo ""
    echo "Tip: If you see 'Input/output error' above, macOS is blocking device access for the app launching ffmpeg."
    echo "Grant Microphone permission to that app (System Settings → Privacy & Security → Microphone)."
  fi
}

doctor() {
  echo "Tmux Whisper doctor"
  echo ""

  load_backend_runtime_cache >/dev/null 2>&1 || true

  local issues=0
  local warnings=0
  local suggestions=()
  local backend_requested backend_last_used
  backend_requested="$(resolve_transcribe_backend)"
  backend_last_used="${DICTATE_LAST_BACKEND_USED:-}"

  local add_suggestion
  add_suggestion() {
    local suggestion="${1:-}"
    [[ -n "$suggestion" ]] || return 0
    local existing
    for existing in "${suggestions[@]-}"; do
      [[ "$existing" == "$suggestion" ]] && return 0
    done
    suggestions+=("$suggestion")
  }

  local check_required_dep
  check_required_dep() {
    local dep="$1"
    if command -v "$dep" >/dev/null 2>&1; then
      echo "  - $dep: ok"
    else
      echo "  - $dep: missing"
      issues=$((issues + 1))
      case "$dep" in
        python3) add_suggestion "Install python3: brew install python" ;;
        ffmpeg) add_suggestion "Install ffmpeg: brew install ffmpeg" ;;
        whisper-cli) add_suggestion "Install whisper-cli legacy fallback: brew install whisper-cpp" ;;
      esac
    fi
  }

  local check_optional_dep
  check_optional_dep() {
    local dep="$1"
    if command -v "$dep" >/dev/null 2>&1; then
      echo "  - $dep: ok"
    else
      echo "  - $dep: missing (optional)"
      warnings=$((warnings + 1))
      case "$dep" in
        tmux) add_suggestion "Install tmux (optional, recommended): brew install tmux" ;;
        swift) add_suggestion "Install Swift/Xcode so tmux-whisperd can be built" ;;
      esac
    fi
  }

  local check_compat_dep
  check_compat_dep() {
    local dep="$1"
    if command -v "$dep" >/dev/null 2>&1; then
      echo "  - $dep: ok (legacy compatibility)"
    else
      echo "  - $dep: not installed (optional legacy compatibility)"
    fi
  }

  echo "Dependencies:"
  check_required_dep python3
  check_required_dep ffmpeg
  if [[ "$backend_requested" == "whisper_cpp" ]]; then
    check_required_dep whisper-cli
  else
    check_compat_dep whisper-cli
  fi
  check_optional_dep tmux
  check_optional_dep swift
  echo ""

  echo "Install sanity:"
  local dictate_bin install_channel
  dictate_bin="$(command -v tmux-whisper 2>/dev/null || true)"
  install_channel="$(detect_install_channel "$dictate_bin")"
  echo "  - tmux-whisper binary: ${dictate_bin:-missing}"
  if [[ -z "$dictate_bin" ]]; then
    issues=$((issues + 1))
    add_suggestion "Install Tmux Whisper from this repo: ./install.sh --force"
  fi
  echo "  - install channel: $install_channel"
  echo "  - shared library: $DICTATE_LIB_PATH $([[ -r "$DICTATE_LIB_PATH" ]] && echo '(ok)' || echo '(missing)')"
  if [[ ! -r "$DICTATE_LIB_PATH" ]]; then
    issues=$((issues + 1))
    add_suggestion "Repair Tmux Whisper install: ./install.sh --force"
  fi
  echo "  - internal library dir: $DICTATE_INTERNAL_LIB_DIR $([[ -d "$DICTATE_INTERNAL_LIB_DIR" ]] && echo '(ok)' || echo '(missing)')"
  if [[ ! -r "$DICTATE_INTERNAL_LIB_DIR/history.sh" || ! -r "$DICTATE_INTERNAL_LIB_DIR/diagnostics.sh" ]]; then
    issues=$((issues + 1))
    add_suggestion "Repair internal runtime modules: ./install.sh --force"
  fi
  echo "  - config file: $DICTATE_CONFIG_FILE $([[ -f "$DICTATE_CONFIG_FILE" ]] && echo '(ok)' || echo '(missing)')"
  if [[ ! -f "$DICTATE_CONFIG_FILE" ]]; then
    warnings=$((warnings + 1))
    add_suggestion "Create default config: ./install.sh --force"
  fi
  local cfg_schema_status cfg_schema_version
  cfg_schema_status="$(config_schema_status)"
  cfg_schema_version="$(config_schema_version_label)"
  echo "  - config schema: ${cfg_schema_version} (expected v${DICTATE_CONFIG_SCHEMA_VERSION}, status=${cfg_schema_status})"
  case "$cfg_schema_status" in
    mismatch)
      issues=$((issues + 1))
      echo "  - hint: this build requires config schema v${DICTATE_CONFIG_SCHEMA_VERSION}. Update or replace ~/.config/dictate/config.toml, then run ./install.sh --force to reinstall scripts."
      add_suggestion "Replace config with repo defaults (manual): cp config/config.toml ~/.config/dictate/config.toml"
      add_suggestion "Or refresh via bootstrap: curl -fsSL https://raw.githubusercontent.com/ricardo-nth/tmux-whisper/main/bootstrap.sh | bash -s -- --force"
      ;;
  esac
  echo "  - raycast inline: $DICTATE_CONFIG_DIR/integrations/raycast/tmux-whisper-inline.sh $([[ -f "$DICTATE_CONFIG_DIR/integrations/raycast/tmux-whisper-inline.sh" ]] && echo '(ok)' || echo '(missing)')"
  local swiftbar_plugin swiftbar_enabled swiftbar_state
  swiftbar_plugin="$HOME/.config/swiftbar/plugins/tmux-whisper-status.0.2s.sh"
  swiftbar_enabled="${CFG_SWIFTBAR_ENABLED:-1}"
  if [[ "$swiftbar_enabled" == "1" ]]; then
    if [[ -f "$swiftbar_plugin" ]]; then
      swiftbar_state="ok, enabled"
    else
      swiftbar_state="missing, enabled"
      warnings=$((warnings + 1))
      add_suggestion "Install SwiftBar plugin: ./install.sh --force"
      add_suggestion "Or disable SwiftBar integration: tmux-whisper swiftbar off"
    fi
  else
    if [[ -f "$swiftbar_plugin" ]]; then
      swiftbar_state="ok, disabled"
    else
      swiftbar_state="missing, disabled"
    fi
  fi
  echo "  - swiftbar plugin: $swiftbar_plugin ($swiftbar_state)"
  local swift_root swift_binary swift_socket_path swift_model_path swift_model_version swift_models_dir
  swift_root="$(resolve_tmux_whisperd_root 2>/dev/null || true)"
  swift_binary="${DICTATE_TMUX_WHISPERD_BIN:-${swift_root:+$swift_root/.build/release/tmux-whisperd}}"
  swift_socket_path="$(resolve_swift_parakeet_socket_path)"
  swift_model_path="$(resolve_swift_parakeet_model_path 2>/dev/null || true)"
  swift_model_version="$(resolve_swift_parakeet_model_version "${swift_model_path:-}")"
  swift_models_dir="$(expand_path "$DEFAULT_SWIFT_PARAKEET_MODELS_DIR")"
  echo "  - backend requested: $backend_requested"
  echo "  - backend last used: ${backend_last_used:-<none>}"
  [[ -n "${DICTATE_LAST_BACKEND_FALLBACK_REASON:-}" ]] && echo "  - backend last fallback: ${DICTATE_LAST_BACKEND_FALLBACK_REASON}"
  if [[ "$backend_requested" == "swift_parakeet" && "$backend_last_used" == "whisper_cpp" ]]; then
    warnings=$((warnings + 1))
    echo "  - backend runtime note: recent dictation used legacy whisper.cpp fallback"
    add_suggestion "Run tmux-whisper warmup to verify the native Parakeet backend"
    add_suggestion "Check swift_parakeet.model_path in ~/.config/dictate/config.toml"
  fi
  if [[ "$backend_requested" == "swift_parakeet" ]]; then
    echo "  - tmux-whisperd source: ${swift_root:-missing}"
    if [[ -z "$swift_root" ]]; then
      issues=$((issues + 1))
      add_suggestion "Reinstall native backend sources: ./install.sh --force"
    fi
    echo "  - tmux-whisperd binary: ${swift_binary:-missing} $([[ -n "$swift_binary" && -x "$swift_binary" ]] && echo '(ok)' || echo '(build needed)')"
    if [[ -z "$(command -v swift 2>/dev/null || true)" && ( -z "$swift_binary" || ! -x "$swift_binary" ) ]]; then
      issues=$((issues + 1))
      add_suggestion "Install Swift/Xcode so tmux-whisperd can be built"
    fi
    echo "  - tmux-whisperd socket: $swift_socket_path $([[ -S "$swift_socket_path" ]] && echo '(live)' || echo '(offline)')"
    echo "  - preferred parakeet dir: $swift_models_dir"
    echo "  - parakeet model: ${swift_model_path:-missing}"
    if [[ -z "$swift_model_path" || ! -d "$swift_model_path" ]]; then
      issues=$((issues + 1))
      add_suggestion "Set swift_parakeet.model_path in ~/.config/dictate/config.toml to your local CoreML Parakeet model directory"
    else
      echo "  - parakeet model version: $swift_model_version"
      if [[ "$swift_model_path" == "$HOME/Library/Application Support/FluidAudio/Models/"* ]]; then
        add_suggestion "Move or copy the Parakeet model into $swift_models_dir so tmux-whisper does not depend on Spokenly/FluidAudio being installed"
      fi
    fi
  fi
  echo ""

  echo "Mode/config:"
  local fixed_mode_raw fixed_mode
  if [[ -f "$MODE_FILE" ]]; then
    fixed_mode_raw="$(head -n 1 "$MODE_FILE" 2>/dev/null | tr -d '\r' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
    if [[ -z "$fixed_mode_raw" ]]; then
      fixed_mode="$(default_inline_mode)"
      warnings=$((warnings + 1))
      echo "  - mode.current: <empty> (invalid, fallback=auto)"
      add_suggestion "Set inline mode policy: tmux-whisper mode auto"
    elif [[ "$fixed_mode_raw" == "auto" ]]; then
      fixed_mode="$(get_current_mode 2>/dev/null || true)"
      [[ -n "$fixed_mode" ]] || fixed_mode="$(default_inline_mode)"
      echo "  - mode.current: auto (app-detect, current=$(mode_display_name "$fixed_mode"))"
    elif [[ -d "$DICTATE_CONFIG_DIR/modes/$(mode_to_dir_name "$fixed_mode_raw")" ]]; then
      fixed_mode="$(canonical_mode_name "$fixed_mode_raw")"
      echo "  - mode.current: $(mode_display_name "$fixed_mode") (fixed)"
    else
      fixed_mode="$(default_inline_mode)"
      warnings=$((warnings + 1))
      echo "  - mode.current: $fixed_mode_raw (invalid, fallback=auto)"
      add_suggestion "Set inline mode policy: tmux-whisper mode auto"
      add_suggestion "Or create the missing mode: tmux-whisper mode create \"$fixed_mode_raw\""
    fi
  else
    fixed_mode="$(get_current_mode 2>/dev/null || true)"
    [[ -n "$fixed_mode" ]] || fixed_mode="$(default_inline_mode)"
    echo "  - mode.current: $(mode_display_name "$fixed_mode") (auto-detect)"
  fi

  local tmux_mode_raw tmux_mode
  tmux_mode_raw="${DICTATE_TMUX_MODE:-${CFG_TMUX_MODE:-code}}"
  tmux_mode="$(canonical_mode_name "$tmux_mode_raw")"
  if [[ -d "$DICTATE_CONFIG_DIR/modes/$(mode_to_dir_name "$tmux_mode")" ]]; then
    echo "  - tmux.mode: $(mode_display_name "$tmux_mode") (ok)"
  else
    warnings=$((warnings + 1))
    echo "  - tmux.mode: $tmux_mode_raw (invalid, fallback=code)"
    add_suggestion "Set tmux mode to a valid mode: tmux-whisper tmux mode code"
  fi

  local required_mode required_prompt required_mode_label any_modes_present
  any_modes_present="0"
  while IFS= read -r required_mode; do
    [[ -n "$required_mode" ]] || continue
    any_modes_present="1"
    required_prompt="$DICTATE_CONFIG_DIR/modes/$(mode_to_dir_name "$required_mode")/prompt"
    required_mode_label="$(mode_display_name "$required_mode")"
    if [[ -s "$required_prompt" ]]; then
      echo "  - mode.$required_mode.prompt: ok"
    elif [[ -f "$required_prompt" ]]; then
      warnings=$((warnings + 1))
      echo "  - mode.$required_mode.prompt: empty"
      add_suggestion "Populate $required_mode_label prompt: tmux-whisper mode edit $required_mode_label"
    else
      warnings=$((warnings + 1))
      echo "  - mode.$required_mode.prompt: missing"
      add_suggestion "Repair mode defaults: ./install.sh --force"
    fi
  done < <(list_modes "")
  if [[ "$any_modes_present" != "1" ]]; then
    warnings=$((warnings + 1))
    echo "  - modes: none found in $DICTATE_CONFIG_DIR/modes"
    add_suggestion "Repair mode defaults: ./install.sh --force"
  fi
  echo ""

  echo "Legacy compatibility:"
  local models_dir
  models_dir="$(expand_path "${CFG_WHISPER_MODELS_DIR:-$DEFAULT_WHISPER_MODELS_DIR}")"
  local model_count=0
  local whisper_bin
  whisper_bin="$(command -v whisper-cli 2>/dev/null || true)"
  if [[ -d "$models_dir" ]]; then
    model_count="$(find "$models_dir" -maxdepth 1 -type f -name 'ggml-*.bin' | wc -l | tr -d ' ')"
  fi
  echo "  - whisper-cli: ${whisper_bin:-not installed (optional)}"
  echo "  - dir: $models_dir"
  echo "  - ggml models: $model_count"
  if [[ "$backend_requested" == "whisper_cpp" ]]; then
    echo "  - status: active by request"
    if [[ -z "$whisper_bin" ]]; then
      issues=$((issues + 1))
      add_suggestion "Install whisper-cli legacy fallback: brew install whisper-cpp"
    fi
    if [[ "$model_count" -eq 0 ]]; then
      issues=$((issues + 1))
      echo "  - hint: whisper.cpp needs local GGML model files when you force the legacy backend"
      echo "  - hint: place ggml-*.bin models in the models dir, then run: tmux-whisper model"
      echo "  - sources:"
      echo "      https://huggingface.co/ggerganov/whisper.cpp/tree/main"
      echo "      https://ggml.ggerganov.com/"
      add_suggestion "Add at least one ggml model to $models_dir (for example ggml-base.en.bin)"
    fi
  elif [[ -n "$whisper_bin" || "$model_count" -gt 0 || "$backend_last_used" == "whisper_cpp" ]]; then
    echo "  - status: available for legacy fallback/testing"
  else
    echo "  - status: not installed (healthy for a Parakeet-first setup)"
  fi
  echo ""

  local _age_s
  _age_s() {
    local f="${1:-}"
    [[ -f "$f" ]] || { echo "-"; return 0; }
    local now mtime
    now="$(date +%s)"
    mtime="$(stat -f %m "$f" 2>/dev/null || true)"
    [[ "$mtime" =~ ^[0-9]+$ ]] || mtime="$(stat -c %Y "$f" 2>/dev/null || true)"
    [[ "$mtime" =~ ^[0-9]+$ ]] || mtime=0
    if [[ "$mtime" -le 0 ]]; then
      echo "?"
      return 0
    fi
    echo $((now - mtime))
  }

  echo "State files:"
  local state_files=(
    "$STATE_FILE"
    "$INLINE_STATE_FILE"
  )
  local sf
  local stale_state_files=()
  for sf in "${state_files[@]}"; do
    if [[ ! -f "$sf" ]]; then
      echo "  - $(basename "$sf"): absent"
      continue
    fi
    local sf_pid sf_target sf_mode
    sf_pid="$( ( source "$sf" 2>/dev/null || true; printf "%s" "${pid:-}" ) 2>/dev/null || true)"
    sf_target="$( ( source "$sf" 2>/dev/null || true; printf "%s" "${target_pane:-${target_app:-}}" ) 2>/dev/null || true)"
    sf_mode="$( ( source "$sf" 2>/dev/null || true; printf "%s" "${model_id:-}" ) 2>/dev/null || true)"
    local age
    age="$(_age_s "$sf")"
    if [[ -n "$sf_pid" ]] && kill -0 "$sf_pid" 2>/dev/null; then
      echo "  - $(basename "$sf"): active pid=$sf_pid age=${age}s target=${sf_target:-n/a} model=${sf_mode:-n/a}"
    else
      echo "  - $(basename "$sf"): stale (pid=${sf_pid:-none}, age=${age}s)"
      warnings=$((warnings + 1))
      stale_state_files+=("$sf")
    fi
  done
  if [[ "${#stale_state_files[@]}" -gt 0 ]]; then
    add_suggestion "Clean stale state files: rm -f ${stale_state_files[*]}"
  fi
  echo ""

  echo "Processing markers:"
  local proc_dir="/tmp/dictate-processing"
  local proc_total=0
  local proc_live=0
  local proc_stale=0
  if [[ -d "$proc_dir" ]]; then
    local pf
    for pf in "$proc_dir"/*; do
      [[ -f "$pf" ]] || continue
      proc_total=$((proc_total + 1))
      local marker_pid line
      marker_pid=""
      line="$(head -n 1 "$pf" 2>/dev/null || true)"
      if [[ "$line" =~ ^pid=([0-9]+)$ ]]; then
        marker_pid="${BASH_REMATCH[1]}"
      elif [[ "$line" =~ ^[0-9]+$ ]]; then
        marker_pid="$line"
      fi
      if [[ -n "$marker_pid" ]] && kill -0 "$marker_pid" 2>/dev/null; then
        proc_live=$((proc_live + 1))
      else
        proc_stale=$((proc_stale + 1))
      fi
    done
  fi
  echo "  - total: $proc_total"
  echo "  - live: $proc_live"
  echo "  - stale: $proc_stale"
  if [[ "$proc_stale" -gt 0 ]]; then
    warnings=$((warnings + 1))
    add_suggestion "Clean stale processing markers: rm -rf $proc_dir"
  fi
  echo ""

  echo "tmux queue:"
  local tmux_total=0
  local tmux_rec=0
  local tmux_proc=0
  local jf st marker_pid now mtime age
  now="$(date +%s)"
  if [[ -d "$TMUX_JOBS_DIR" ]]; then
    for jf in "$TMUX_JOBS_DIR"/*; do
      [[ -f "$jf" ]] || continue
      st="$(sed -n 's/^status=//p' "$jf" 2>/dev/null | head -n 1 || true)"
      marker_pid="$(sed -n 's/^pid=//p' "$jf" 2>/dev/null | head -n 1 || true)"
      mtime="$(stat -f %m "$jf" 2>/dev/null || true)"
      [[ "$mtime" =~ ^[0-9]+$ ]] || mtime="$(stat -c %Y "$jf" 2>/dev/null || true)"
      [[ "$mtime" =~ ^[0-9]+$ ]] || mtime=0
      age=$((now - mtime))
        case "$st" in
          recording|processing)
            if [[ -z "$marker_pid" || ! "$marker_pid" =~ ^[0-9]+$ ]]; then
              warnings=$((warnings + 1))
              echo "  - stale job: $(basename "$jf") status=${st:-unknown} age=${age}s pid=${marker_pid:-none}"
              add_suggestion "Clean stale tmux job markers: rm -rf $TMUX_JOBS_DIR"
              continue
            fi
            if ! kill -0 "$marker_pid" 2>/dev/null; then
              warnings=$((warnings + 1))
              echo "  - stale job: $(basename "$jf") status=${st:-unknown} age=${age}s pid=${marker_pid:-none}"
              add_suggestion "Clean stale tmux job markers: rm -rf $TMUX_JOBS_DIR"
              continue
            fi
            ;;
        esac
      tmux_total=$((tmux_total + 1))
      case "$st" in
        recording) tmux_rec=$((tmux_rec + 1)) ;;
        processing) tmux_proc=$((tmux_proc + 1)) ;;
      esac
    done
  fi
  echo "  - total: $tmux_total"
  echo "  - recording: $tmux_rec"
  echo "  - processing: $tmux_proc"
  echo ""

  echo "Summary:"
  echo "  issues: $issues"
  echo "  warnings: $warnings"
  if [[ "$issues" -eq 0 && "$warnings" -eq 0 ]]; then
    echo "  status: healthy"
  elif [[ "$issues" -eq 0 ]]; then
    echo "  status: ok with warnings"
  else
    echo "  status: needs attention"
  fi

  if [[ "${#suggestions[@]}" -gt 0 ]]; then
    echo ""
    echo "Suggested fixes:"
    local suggestion
    for suggestion in "${suggestions[@]}"; do
      echo "  - $suggestion"
    done
  fi
}

status() {
  load_backend_runtime_cache >/dev/null 2>&1 || true
  local inline_state="$INLINE_STATE_FILE"
  local proc_dir="/tmp/dictate-processing"

  onoff() {
    [[ "${1:-0}" == "1" ]] && echo "ON" || echo "OFF"
  }

  age_s() {
    local f="${1:-}"
    [[ -f "$f" ]] || { echo "-"; return 0; }
    local now mtime
    now="$(date +%s)"
    mtime="$(stat -f %m "$f" 2>/dev/null || true)"
    [[ "$mtime" =~ ^[0-9]+$ ]] || mtime="$(stat -c %Y "$f" 2>/dev/null || true)"
    [[ "$mtime" =~ ^[0-9]+$ ]] || mtime=0
    [[ "$mtime" -gt 0 ]] || { echo "?"; return 0; }
    echo $((now - mtime))
  }

  resolve_model_label() {
    local id="${1:-base}"
    local path rc
    set +e
    path="$(resolve_model_path "$id" 2>/dev/null)"
    rc=$?
    set -e
    if [[ "$rc" -eq 0 && -n "$path" ]]; then
      basename "$path"
    else
      echo "$id"
    fi
  }

  count_processing_markers() {
    local total=0 live=0 stale=0
    local pf marker_pid line
    if [[ -d "$proc_dir" ]]; then
      for pf in "$proc_dir"/*; do
        [[ -f "$pf" ]] || continue
        total=$((total + 1))
        marker_pid=""
        line="$(head -n 1 "$pf" 2>/dev/null || true)"
        if [[ "$line" =~ ^pid=([0-9]+)$ ]]; then
          marker_pid="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^[0-9]+$ ]]; then
          marker_pid="$line"
        fi
        if [[ -n "$marker_pid" ]] && kill -0 "$marker_pid" 2>/dev/null; then
          live=$((live + 1))
        else
          stale=$((stale + 1))
        fi
      done
    fi
    echo "$total $live $stale"
  }

  count_tmux_jobs_snapshot() {
    local total=0 rec=0 proc=0
    local jf st marker_pid now mtime age
    now="$(date +%s)"
    if [[ -d "$TMUX_JOBS_DIR" ]]; then
      for jf in "$TMUX_JOBS_DIR"/*; do
        [[ -f "$jf" ]] || continue
        st="$(sed -n 's/^status=//p' "$jf" 2>/dev/null | head -n 1 || true)"
        marker_pid="$(sed -n 's/^pid=//p' "$jf" 2>/dev/null | head -n 1 || true)"
        mtime="$(stat -f %m "$jf" 2>/dev/null || true)"
        [[ "$mtime" =~ ^[0-9]+$ ]] || mtime="$(stat -c %Y "$jf" 2>/dev/null || true)"
        [[ "$mtime" =~ ^[0-9]+$ ]] || mtime=0
        age=$((now - mtime))
        if [[ "$age" -gt 1800 ]]; then
          rm -f "$jf" 2>/dev/null || true
          continue
        fi
        case "$st" in
          recording|processing)
            if [[ -z "$marker_pid" || ! "$marker_pid" =~ ^[0-9]+$ ]]; then
              rm -f "$jf" 2>/dev/null || true
              continue
            fi
            if ! kill -0 "$marker_pid" 2>/dev/null; then
              rm -f "$jf" 2>/dev/null || true
              continue
            fi
            ;;
        esac
        total=$((total + 1))
        case "$st" in
          recording) rec=$((rec + 1)) ;;
          processing) proc=$((proc + 1)) ;;
        esac
      done
    fi
    echo "$total $rec $proc"
  }

  describe_state_file() {
    local label="${1:-}"
    local file="${2:-}"
    [[ -n "$label" && -n "$file" ]] || return 0
    if [[ ! -f "$file" ]]; then
      echo "  $label: idle"
      return 0
    fi

    local st_pid st_target st_app st_model st_lang st_age st_label
    st_pid="$( ( source "$file" 2>/dev/null || true; printf "%s" "${pid:-}" ) 2>/dev/null || true)"
    st_target="$( ( source "$file" 2>/dev/null || true; printf "%s" "${target_pane:-}" ) 2>/dev/null || true)"
    st_app="$( ( source "$file" 2>/dev/null || true; printf "%s" "${target_app:-}" ) 2>/dev/null || true)"
    st_model="$( ( source "$file" 2>/dev/null || true; printf "%s" "${model_id:-}" ) 2>/dev/null || true)"
    st_lang="$( ( source "$file" 2>/dev/null || true; printf "%s" "${language:-}" ) 2>/dev/null || true)"
    st_age="$(age_s "$file")"

    if [[ "$label" == "tmux" ]]; then
      st_label="$st_target"
      [[ -n "$st_target" ]] && st_label="$(tmux_describe_pane "$st_target")"
    else
      st_label="${st_app:-n/a}"
    fi

    if [[ -n "$st_pid" ]] && kill -0 "$st_pid" 2>/dev/null; then
      echo "  $label: active pid=$st_pid age=${st_age}s target=${st_label:-n/a} model=${st_model:-n/a} lang=${st_lang:-en}"
    else
      echo "  $label: stale state file (pid=${st_pid:-none}, age=${st_age}s)"
    fi
  }

  local inline_mode_setting mode_inline mode_inline_source
  if [[ -f "$MODE_FILE" ]]; then
    inline_mode_setting="$(head -n 1 "$MODE_FILE" 2>/dev/null | tr -d '\r' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
  else
    inline_mode_setting="auto"
  fi
  if [[ -z "$inline_mode_setting" || "$inline_mode_setting" == "auto" ]]; then
    mode_inline_source="auto"
  else
    mode_inline_source="fixed"
  fi
  mode_inline="$(canonical_mode_name "$(get_current_mode)")"
  if ! mode_exists "$mode_inline"; then
    mode_inline="$(default_inline_mode)"
  fi

  local mode_tmux_raw mode_tmux
  mode_tmux_raw="${DICTATE_TMUX_MODE:-${CFG_TMUX_MODE:-code}}"
  mode_tmux="$(canonical_mode_name "$mode_tmux_raw")"
  if ! mode_exists "$mode_tmux" || ! mode_allows_flow "$mode_tmux" "tmux"; then
    mode_tmux="$(first_mode_for_flow "tmux")"
  fi

  local model_inline_id model_inline_label
  model_inline_id="${DICTATE_MODEL:-${CFG_WHISPER_MODEL:-base}}"
  model_inline_label="$(resolve_model_label "$model_inline_id")"

  local model_tmux_id model_tmux_label
  model_tmux_id="${DICTATE_TMUX_MODEL:-${CFG_TMUX_MODEL:-$model_inline_id}}"
  model_tmux_label="$(resolve_model_label "$model_tmux_id")"
  local backend_requested swift_model_path swift_model_version swift_socket_path
  backend_requested="$(resolve_transcribe_backend)"
  swift_model_path="$(resolve_swift_parakeet_model_path 2>/dev/null || true)"
  swift_model_version="$(resolve_swift_parakeet_model_version "${swift_model_path:-}")"
  swift_socket_path="$(resolve_swift_parakeet_socket_path)"

  local post_inline post_inline_requested post_tmux post_tmux_requested
  post_inline_requested="${DICTATE_POSTPROCESS:-${CFG_POSTPROCESS_ENABLED:-0}}"
  if bool_is_on "$post_inline_requested"; then
    post_inline_requested="1"
  else
    post_inline_requested="0"
  fi
  post_inline="$post_inline_requested"
  post_tmux_requested="$(resolve_tmux_postprocess_requested)"
  post_tmux="$(resolve_tmux_postprocess_effective)"
  local cerebras_key_set="0"
  [[ -n "${CEREBRAS_API_KEY:-}" ]] && cerebras_key_set="1"
  if [[ "$cerebras_key_set" != "1" ]]; then
    post_inline="0"
  fi

  local inline_autosend inline_process_sound inline_target inline_send_mode tmux_autosend tmux_target tmux_process_sound
  inline_autosend="${DICTATE_AUTOSEND:-${CFG_INLINE_AUTOSEND:-1}}"
  inline_process_sound="${DICTATE_INLINE_PROCESS_SOUND:-${CFG_INLINE_PROCESS_SOUND:-1}}"
  inline_target="$(inline_paste_target_label "${DICTATE_INLINE_PASTE_TARGET:-${CFG_INLINE_PASTE_TARGET:-restore}}")"
  inline_send_mode="$(inline_send_mode_label "${DICTATE_INLINE_SEND_MODE:-${CFG_INLINE_SEND_MODE:-enter}}")"
  tmux_autosend="${DICTATE_TMUX_AUTOSEND:-${CFG_TMUX_AUTOSEND:-1}}"
  tmux_target="${DICTATE_TMUX_PASTE_TARGET:-${CFG_TMUX_PASTE_TARGET:-origin}}"
  tmux_process_sound="${DICTATE_TMUX_PROCESS_SOUND:-${CFG_TMUX_PROCESS_SOUND:-0}}"
  local tmux_send_mode keep_logs_val
  tmux_send_mode="${DICTATE_TMUX_SEND_MODE:-${CFG_TMUX_SEND_MODE:-auto}}"
  case "$tmux_send_mode" in
    auto|enter|codex) ;;
    *) tmux_send_mode="auto" ;;
  esac
  keep_logs_val="${DICTATE_KEEP_LOGS:-${CFG_DEBUG_KEEP_LOGS:-0}}"

  local clean_enabled repeats_level silence_trim
  clean_enabled="${DICTATE_CLEAN:-0}"
  repeats_level="${DICTATE_REPEATS_LEVEL:-${CFG_CLEAN_REPEATS_LEVEL:-1}}"
  silence_trim="${DICTATE_SILENCE_TRIM:-${CFG_AUDIO_SILENCE_TRIM:-0}}"
  local vocab_clean
  vocab_clean="${DICTATE_VOCAB_CLEAN:-1}"
  if bool_is_on "$vocab_clean"; then
    vocab_clean="1"
  else
    vocab_clean="0"
  fi

  local llm_model llm_max_tokens llm_chunk_words
  llm_model="${DICTATE_LLM_MODEL:-${CFG_POSTPROCESS_LLM:-llama3.1-8b}}"
  llm_max_tokens="${DICTATE_LLM_MAX_TOKENS:-${CFG_POSTPROCESS_MAX_TOKENS:-}}"
  llm_chunk_words="${DICTATE_LLM_CHUNK_WORDS:-${CFG_POSTPROCESS_CHUNK_WORDS:-}}"

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
    local mode="${2:-}"
    local key value
    key="$(mode_override_key "$mode")"
    value="$(lookup_override "$list" "$key" 2>/dev/null || true)"
    [[ -n "$value" ]] && echo "$value"
  }

  local budget_short_llm budget_short_max budget_short_chunk
  local budget_long_llm budget_long_max budget_long_chunk
  budget_short_llm="$(lookup_override_for_mode "${CFG_POSTPROCESS_BUDGET_PROFILE_LLM_OVERRIDES:-}" "short" 2>/dev/null || true)"
  budget_short_max="$(lookup_override_for_mode "${CFG_POSTPROCESS_BUDGET_PROFILE_MAX_TOKENS_OVERRIDES:-}" "short" 2>/dev/null || true)"
  budget_short_chunk="$(lookup_override_for_mode "${CFG_POSTPROCESS_BUDGET_PROFILE_CHUNK_WORDS_OVERRIDES:-}" "short" 2>/dev/null || true)"
  budget_long_llm="$(lookup_override_for_mode "${CFG_POSTPROCESS_BUDGET_PROFILE_LLM_OVERRIDES:-}" "long" 2>/dev/null || true)"
  budget_long_max="$(lookup_override_for_mode "${CFG_POSTPROCESS_BUDGET_PROFILE_MAX_TOKENS_OVERRIDES:-}" "long" 2>/dev/null || true)"
  budget_long_chunk="$(lookup_override_for_mode "${CFG_POSTPROCESS_BUDGET_PROFILE_CHUNK_WORDS_OVERRIDES:-}" "long" 2>/dev/null || true)"

  local audio_name audio_idx audio_src audio_source_mode
  audio_source_mode="$(normalize_audio_source "${DICTATE_AUDIO_SOURCE:-${CFG_AUDIO_SOURCE:-auto}}")"
  audio_name="${DICTATE_AUDIO_NAME:-${CFG_AUDIO_DEVICE_NAME:-}}"
  audio_idx="${DICTATE_AUDIO_INDEX:-}"
  audio_src="(none)"
  if [[ -n "$audio_idx" ]]; then
      audio_src="env:DICTATE_AUDIO_INDEX"
  elif [[ -n "${CFG_AUDIO_DEVICE_INDEX:-}" ]]; then
    audio_idx="${CFG_AUDIO_DEVICE_INDEX}"
    audio_src="config:audio.device_index"
  else
    if command -v ffmpeg >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
      local detect_meta detect_src
      detect_meta="$(detect_audio_index 2>/dev/null || true)"
      IFS=$'\t' read -r audio_idx detect_src _ <<<"$detect_meta"
      if [[ -n "$audio_idx" ]]; then
        audio_src="${detect_src:-detect:source(${audio_source_mode})}"
      fi
    else
      audio_src="detect skipped (missing ffmpeg/python3)"
    fi
  fi

  local key_status="UNSET"
  [[ -n "${CEREBRAS_API_KEY:-}" ]] && key_status="SET"

  local proc_total proc_live proc_stale
  read -r proc_total proc_live proc_stale < <(count_processing_markers)

  local tmux_total tmux_rec tmux_proc
  read -r tmux_total tmux_rec tmux_proc < <(count_tmux_jobs_snapshot)

  echo "Tmux Whisper status"
  echo ""
  echo "Runtime:"
  describe_state_file "tmux" "$STATE_FILE"
  describe_state_file "inline" "$inline_state"
  echo "  processing markers: total=${proc_total:-0} live=${proc_live:-0} stale=${proc_stale:-0}"
  echo "  tmux queue: total=${tmux_total:-0} recording=${tmux_rec:-0} processing=${tmux_proc:-0}"

  echo ""
  echo "Effective settings:"
  echo "  backend.requested: $backend_requested"
  echo "  backend.last_used: ${DICTATE_LAST_BACKEND_USED:-<none>}"
  if [[ -n "${DICTATE_LAST_BACKEND_FALLBACK_REASON:-}" ]]; then
    echo "  backend.last_fallback: ${DICTATE_LAST_BACKEND_FALLBACK_REASON}"
  fi
  echo "  mode.inline: $(mode_display_name "$mode_inline") ($mode_inline_source)"
  echo "  mode.tmux: $(mode_display_name "$mode_tmux")"
  local backend_effective
  backend_effective="${DICTATE_LAST_BACKEND_USED:-$backend_requested}"
  if [[ "$backend_effective" == "swift_parakeet" ]]; then
    echo "  swift_parakeet.model: ${swift_model_path:-<missing>} (${swift_model_version})"
    echo "  swift_parakeet.socket: $swift_socket_path"
  else
    echo "  model.inline: $model_inline_id ($model_inline_label)"
    echo "  model.tmux: $model_tmux_id ($model_tmux_label)"
    echo "  whisper.threads/beam/best_of: ${DICTATE_THREADS:-${CFG_WHISPER_THREADS:-5}}/${DICTATE_BEAM_SIZE:-${CFG_WHISPER_BEAM_SIZE:-1}}/${DICTATE_BEST_OF:-${CFG_WHISPER_BEST_OF:-1}}"
  fi
  echo "  language: ${DICTATE_LANGUAGE:-en}"
  echo "  postprocess.inline: $(onoff "$post_inline")"
  echo "  postprocess.tmux: $(onoff "$post_tmux")"
  if [[ "$post_inline" == "1" ]]; then
    echo "  mode_prompt.inline: active"
  else
    echo "  mode_prompt.inline: inactive (postprocess not active)"
  fi
  if [[ "$post_tmux" == "1" ]]; then
    echo "  mode_prompt.tmux: active"
  else
    echo "  mode_prompt.tmux: inactive (postprocess not active)"
  fi
  if [[ "$cerebras_key_set" != "1" && ( "$post_inline_requested" == "1" || "$post_tmux_requested" == "1" ) ]]; then
    echo "  postprocess.note: disabled at runtime (CEREBRAS_API_KEY missing)"
  fi
  echo "  llm: $llm_model"
  [[ -n "$llm_max_tokens" ]] && echo "  llm.max_tokens: $llm_max_tokens"
  [[ -n "$llm_chunk_words" ]] && echo "  llm.chunk_words: $llm_chunk_words"
  echo "  budget.auto_long_words_threshold: ${CFG_POSTPROCESS_BUDGET_LONG_WORDS_THRESHOLD:-120}"
  echo "  budget.auto_numeric_sizing: dynamic (max_tokens/chunk_words interpolate short->long by transcript words; clamp at threshold)"
  echo "  budget_profile.short: llm=${budget_short_llm:-${CFG_POSTPROCESS_LLM:-llama3.1-8b}} max_tokens=${budget_short_max:-${CFG_POSTPROCESS_MAX_TOKENS:-<unset>}} chunk_words=${budget_short_chunk:-${CFG_POSTPROCESS_CHUNK_WORDS:-<unset>}}"
  echo "  budget_profile.long: llm=${budget_long_llm:-${CFG_POSTPROCESS_LLM:-llama3.1-8b}} max_tokens=${budget_long_max:-${CFG_POSTPROCESS_MAX_TOKENS:-<unset>}} chunk_words=${budget_long_chunk:-${CFG_POSTPROCESS_CHUNK_WORDS:-<unset>}}"
  echo "  british_spelling: $(onoff "${DICTATE_BRITISH_SPELLING:-1}")"
  echo "  clean.regex: $(onoff "$clean_enabled")"
  echo "  clean.repeats_level: $repeats_level"
  echo "  clean.vocab_only_when_postprocess_off: $(onoff "$vocab_clean")"
  echo "  silence_trim: $(onoff "$silence_trim") (${CFG_AUDIO_SILENCE_TRIM_MODE:-edges})"
  echo "  inline.autosend: $(onoff "$inline_autosend")"
  echo "  inline.process_sound: $(onoff "$inline_process_sound")"
  echo "  inline.target: $inline_target"
  echo "  inline.send_mode: $inline_send_mode"
  echo "  tmux.autosend: $(onoff "$tmux_autosend")"
  echo "  tmux.target: $tmux_target"
  echo "  tmux.process_sound: $(onoff "$tmux_process_sound")"
  echo "  tmux.send_mode: $tmux_send_mode"
  echo "  integrations.swiftbar.enabled: $(onoff "${CFG_SWIFTBAR_ENABLED:-1}")"
  echo "  debug.keep_logs: $(onoff "$keep_logs_val")"
  echo "  audio.source: ${audio_source_mode}"
  echo "  audio.device_name: ${audio_name:-<none>}"
  echo "  audio.mac_name: ${CFG_AUDIO_MAC_NAME:-<none>}"
  echo "  audio.iphone_name: ${CFG_AUDIO_IPHONE_NAME:-<none>}"
  echo "  audio.device_index_fallback: ${CFG_AUDIO_DEVICE_INDEX:-<none>}"
  echo "  audio.index_resolved: ${audio_idx:-<none>} (source: $audio_src)"
  echo "  sounds: master=$(onoff "${CFG_AUDIO_SOUNDS_ENABLED:-1}") start=$(onoff "${CFG_AUDIO_SOUNDS_START_ENABLED:-1}") stop=$(onoff "${CFG_AUDIO_SOUNDS_STOP_ENABLED:-1}") process=$(onoff "${CFG_AUDIO_SOUNDS_PROCESS_ENABLED:-1}") error=$(onoff "${CFG_AUDIO_SOUNDS_ERROR_ENABLED:-1}") cancel=$(onoff "${CFG_AUDIO_SOUNDS_CANCEL_ENABLED:-1}")"
  echo "  cerebras_api_key: $key_status"

  echo ""
  echo "Active env overrides:"
  local override_vars=(
    DICTATE_AUDIO_SOURCE DICTATE_AUDIO_INDEX DICTATE_AUDIO_NAME
    DICTATE_BACKEND
    DICTATE_MODEL DICTATE_TMUX_MODEL
    DICTATE_TMUX_MODE
    DICTATE_SWIFT_PARAKEET_MODEL_PATH DICTATE_SWIFT_PARAKEET_MODEL_VERSION DICTATE_SWIFT_PARAKEET_SOCKET_PATH
    DICTATE_POSTPROCESS DICTATE_TMUX_POSTPROCESS DICTATE_VOCAB_CLEAN
    DICTATE_AUTOSEND DICTATE_TMUX_AUTOSEND
    DICTATE_INLINE_PASTE_TARGET DICTATE_INLINE_SEND_MODE
    DICTATE_INLINE_ACTIVATE_DELAY_MS DICTATE_INLINE_SEND_DELAY_MS
    DICTATE_TMUX_PASTE_TARGET DICTATE_TMUX_PROCESS_SOUND
    DICTATE_TMUX_SEND_MODE
    DICTATE_TMUX_SEND_DELAY_MS DICTATE_TMUX_CODEX_TAB_DELAY_MS
    DICTATE_CLEAN DICTATE_REPEATS_LEVEL DICTATE_SILENCE_TRIM
    DICTATE_TRIM_WITH_POSTPROCESS DICTATE_REPEATS_WITH_POSTPROCESS
    DICTATE_LLM_MODEL DICTATE_LLM_MAX_TOKENS DICTATE_LLM_CHUNK_WORDS DICTATE_BRITISH_SPELLING
    DICTATE_THREADS DICTATE_BEAM_SIZE DICTATE_BEST_OF DICTATE_GPU
    DICTATE_LANGUAGE
    DICTATE_TARGET_APP DICTATE_TARGET_PANE
    DICTATE_KEEP_LOGS
    CEREBRAS_API_KEY
  )
  local shown=0 var val
  for var in "${override_vars[@]}"; do
    val="${!var-}"
    [[ -n "$val" ]] || continue
    if [[ "$var" == "CEREBRAS_API_KEY" ]]; then
      echo "  $var=<set>"
    else
      echo "  $var=$val"
    fi
    shown=$((shown + 1))
  done
  if [[ "$shown" -eq 0 ]]; then
    echo "  (none)"
  fi

  echo ""
  echo "More detail: tmux-whisper debug   |   tmux-whisper doctor   |   tmux-whisper logs"
}
