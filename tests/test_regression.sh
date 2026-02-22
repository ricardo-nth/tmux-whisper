#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
STUB_BIN="$TMP_ROOT/stub-bin"
mkdir -p "$STUB_BIN"

cat >"$STUB_BIN/osascript" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
chmod +x "$STUB_BIN/osascript"

assert_contains() {
  local name="$1"
  local haystack="$2"
  local needle="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "FAIL: $name" >&2
    echo "Expected to find: $needle" >&2
    exit 1
  fi
  echo "PASS: $name"
}

assert_not_contains() {
  local name="$1"
  local haystack="$2"
  local needle="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    echo "FAIL: $name" >&2
    echo "Expected not to find: $needle" >&2
    exit 1
  fi
  echo "PASS: $name"
}

assert_file_contains() {
  local name="$1"
  local file="$2"
  local needle="$3"
  if ! rg -q --fixed-strings "$needle" "$file"; then
    echo "FAIL: $name" >&2
    echo "Missing pattern in $file: $needle" >&2
    exit 1
  fi
  echo "PASS: $name"
}

assert_file_exists() {
  local name="$1"
  local file="$2"
  if [[ ! -f "$file" ]]; then
    echo "FAIL: $name" >&2
    echo "Expected file to exist: $file" >&2
    exit 1
  fi
  echo "PASS: $name"
}

# --- Regression 1: install-channel detection should work for custom paths. ---
CUSTOM_HOME="$TMP_ROOT/home-custom"
CUSTOM_BIN="$TMP_ROOT/custom-bin"
mkdir -p "$CUSTOM_HOME" "$CUSTOM_BIN"
cp "$ROOT/bin/tmux-whisper" "$CUSTOM_BIN/tmux-whisper"
cp "$ROOT/bin/dictate-lib.sh" "$CUSTOM_BIN/dictate-lib.sh"
chmod +x "$CUSTOM_BIN/tmux-whisper" "$CUSTOM_BIN/dictate-lib.sh"
CUSTOM_DICTATE_CONFIG_DIR="$CUSTOM_HOME/.config/dictate"
CUSTOM_DICTATE_CONFIG_FILE="$CUSTOM_DICTATE_CONFIG_DIR/config.toml"

custom_debug="$(HOME="$CUSTOM_HOME" PATH="$CUSTOM_BIN:/usr/bin:/bin" DICTATE_LIB_PATH= DICTATE_CONFIG_DIR="$CUSTOM_DICTATE_CONFIG_DIR" DICTATE_CONFIG_FILE="$CUSTOM_DICTATE_CONFIG_FILE" "$CUSTOM_BIN/tmux-whisper" debug)"
assert_contains "debug_channel_present" "$custom_debug" "channel: "
assert_contains "debug_paths_section" "$custom_debug" "Paths:"
assert_contains "debug_install_lib_line" "$custom_debug" "lib:"

custom_doctor="$(HOME="$CUSTOM_HOME" PATH="$CUSTOM_BIN:/usr/bin:/bin" DICTATE_LIB_PATH= DICTATE_CONFIG_DIR="$CUSTOM_DICTATE_CONFIG_DIR" DICTATE_CONFIG_FILE="$CUSTOM_DICTATE_CONFIG_FILE" "$CUSTOM_BIN/tmux-whisper" doctor)"
assert_contains "doctor_install_sanity_section" "$custom_doctor" "Install sanity:"
assert_contains "doctor_channel_present" "$custom_doctor" "install channel: "
assert_contains "doctor_schema_ok" "$custom_doctor" "config schema: v1 (expected v1, status=ok)"

# --- Regression 2: install-channel detection should work for local user installs. ---
LOCAL_HOME="$TMP_ROOT/home-local"
LOCAL_BIN="$LOCAL_HOME/.local/bin"
mkdir -p "$LOCAL_BIN"
cp "$ROOT/bin/tmux-whisper" "$LOCAL_BIN/tmux-whisper"
cp "$ROOT/bin/dictate-lib.sh" "$LOCAL_BIN/dictate-lib.sh"
chmod +x "$LOCAL_BIN/tmux-whisper" "$LOCAL_BIN/dictate-lib.sh"
LOCAL_DICTATE_CONFIG_DIR="$LOCAL_HOME/.config/dictate"
LOCAL_DICTATE_CONFIG_FILE="$LOCAL_DICTATE_CONFIG_DIR/config.toml"

local_debug="$(HOME="$LOCAL_HOME" PATH="$LOCAL_BIN:/usr/bin:/bin" DICTATE_LIB_PATH= DICTATE_CONFIG_DIR="$LOCAL_DICTATE_CONFIG_DIR" DICTATE_CONFIG_FILE="$LOCAL_DICTATE_CONFIG_FILE" tmux-whisper debug)"
assert_contains "debug_local_user_channel" "$local_debug" "channel: local-user"

# --- Regression 3: doctor should fail on schema mismatch. ---
MISMATCH_HOME="$TMP_ROOT/home-mismatch"
MISMATCH_BIN="$MISMATCH_HOME/.local/bin"
MISMATCH_CFG="$MISMATCH_HOME/.config/dictate"
mkdir -p "$MISMATCH_BIN" "$MISMATCH_CFG"
cp "$ROOT/bin/tmux-whisper" "$MISMATCH_BIN/tmux-whisper"
cp "$ROOT/bin/dictate-lib.sh" "$MISMATCH_BIN/dictate-lib.sh"
chmod +x "$MISMATCH_BIN/tmux-whisper" "$MISMATCH_BIN/dictate-lib.sh"
cat >"$MISMATCH_CFG/config.toml" <<'EOF'
[meta]
config_version = 0

[audio]
source = "auto"
EOF
mismatch_doctor="$(HOME="$MISMATCH_HOME" PATH="$MISMATCH_BIN:/usr/bin:/bin" DICTATE_LIB_PATH= DICTATE_CONFIG_DIR="$MISMATCH_CFG" DICTATE_CONFIG_FILE="$MISMATCH_CFG/config.toml" tmux-whisper doctor)"
assert_contains "doctor_schema_mismatch_status" "$mismatch_doctor" "config schema: v0 (expected v1, status=mismatch)"
assert_contains "doctor_schema_mismatch_hint" "$mismatch_doctor" "this build requires config schema v1"
assert_contains "doctor_schema_suggested_fixes" "$mismatch_doctor" "Suggested fixes:"
assert_contains "doctor_schema_suggested_install" "$mismatch_doctor" "Refresh defaults from repo: ./install.sh --force"

# --- Regression 4: doctor mode checks should show clear fallbacks + fixes. ---
MODECHECK_HOME="$TMP_ROOT/home-modecheck"
MODECHECK_BIN="$MODECHECK_HOME/.local/bin"
MODECHECK_CFG="$MODECHECK_HOME/.config/dictate"
mkdir -p "$MODECHECK_BIN" "$MODECHECK_CFG/modes/short" "$MODECHECK_CFG/modes/long"
cp "$ROOT/bin/tmux-whisper" "$MODECHECK_BIN/tmux-whisper"
cp "$ROOT/bin/dictate-lib.sh" "$MODECHECK_BIN/dictate-lib.sh"
chmod +x "$MODECHECK_BIN/tmux-whisper" "$MODECHECK_BIN/dictate-lib.sh"
cat >"$MODECHECK_CFG/config.toml" <<'EOF'
[meta]
config_version = 1

[audio]
source = "auto"

[tmux]
mode = "ghost"
EOF
printf '%s\n' "ghost" >"$MODECHECK_CFG/current-mode"
printf '%s\n' "Context: short mode." >"$MODECHECK_CFG/modes/short/prompt"
printf '%s\n' "Context: long mode." >"$MODECHECK_CFG/modes/long/prompt"
modecheck_doctor="$(HOME="$MODECHECK_HOME" PATH="$MODECHECK_BIN:/usr/bin:/bin" DICTATE_LIB_PATH= DICTATE_CONFIG_DIR="$MODECHECK_CFG" DICTATE_CONFIG_FILE="$MODECHECK_CFG/config.toml" tmux-whisper doctor)"
assert_contains "doctor_modecheck_section" "$modecheck_doctor" "Mode/config:"
assert_contains "doctor_modecheck_fixed_invalid" "$modecheck_doctor" "mode.current: ghost (invalid, fallback=code)"
assert_contains "doctor_modecheck_tmux_invalid" "$modecheck_doctor" "tmux.mode: ghost (invalid, fallback=code)"
assert_contains "doctor_modecheck_fix_mode" "$modecheck_doctor" "Set a valid fixed mode: tmux-whisper mode code"
assert_contains "doctor_modecheck_fix_tmux" "$modecheck_doctor" "Set tmux mode to a valid mode: tmux-whisper tmux mode code"

# --- Regression 5: integration scripts keep PATH-based command resolution. ---
assert_file_contains "raycast_inline_lib_resolution" "$ROOT/integrations/raycast/tmux-whisper-inline.sh" "command -v dictate-lib.sh"
assert_file_contains "raycast_toggle_dictate_resolution" "$ROOT/integrations/raycast/tmux-whisper-toggle.sh" "command -v tmux-whisper"
assert_file_contains "swiftbar_dictate_resolution" "$ROOT/integrations/tmux-whisper-status.0.2s.sh" "command -v tmux-whisper"
assert_file_contains "raycast_inline_path_hardening" "$ROOT/integrations/raycast/tmux-whisper-inline.sh" "/usr/local/bin"
assert_file_contains "raycast_toggle_path_hardening" "$ROOT/integrations/raycast/tmux-whisper-toggle.sh" "/usr/local/bin"
assert_file_contains "raycast_cancel_path_hardening" "$ROOT/integrations/raycast/tmux-whisper-cancel.sh" "/usr/local/bin"
assert_file_contains "swiftbar_path_hardening" "$ROOT/integrations/tmux-whisper-status.0.2s.sh" "/usr/local/bin"
assert_file_contains "raycast_inline_dependency_notice" "$ROOT/integrations/raycast/tmux-whisper-inline.sh" 'Missing dependency: $dep'
assert_file_contains "raycast_toggle_binary_notice" "$ROOT/integrations/raycast/tmux-whisper-toggle.sh" "Tmux Whisper binary not found."
assert_file_contains "swiftbar_missing_binary_notice" "$ROOT/integrations/tmux-whisper-status.0.2s.sh" "Tmux Whisper binary not found | color=red"
assert_file_contains "swiftbar_enabled_config_parse" "$ROOT/integrations/tmux-whisper-status.0.2s.sh" "integrations.swiftbar.enabled"

# --- Regression 6: script-level behavior for missing tmux-whisper binary is explicit. ---
TOGGLE_HOME="$TMP_ROOT/home-toggle"
mkdir -p "$TOGGLE_HOME"
toggle_out="$(HOME="$TOGGLE_HOME" PATH="$STUB_BIN:/usr/bin:/bin" DICTATE_BIN="$TMP_ROOT/not-found-dictate" bash "$ROOT/integrations/raycast/tmux-whisper-toggle.sh" 2>&1 || true)"
assert_contains "raycast_toggle_missing_binary_runtime" "$toggle_out" "tmux-whisper-toggle: Tmux Whisper binary not found."

SWIFTBAR_HOME="$TMP_ROOT/home-swiftbar"
mkdir -p "$SWIFTBAR_HOME"
swiftbar_out="$(HOME="$SWIFTBAR_HOME" PATH="$STUB_BIN:/usr/bin:/bin" DICTATE_BIN="$TMP_ROOT/not-found-dictate" bash "$ROOT/integrations/tmux-whisper-status.0.2s.sh")"
assert_contains "swiftbar_missing_binary_runtime" "$swiftbar_out" "Tmux Whisper binary not found"

# --- Regression 7: SwiftBar runtime integration toggle works end-to-end. ---
SWIFTBAR_TOGGLE_HOME="$TMP_ROOT/home-swiftbar-toggle"
SWIFTBAR_TOGGLE_BIN="$SWIFTBAR_TOGGLE_HOME/.local/bin"
SWIFTBAR_TOGGLE_CFG="$SWIFTBAR_TOGGLE_HOME/.config/dictate"
mkdir -p "$SWIFTBAR_TOGGLE_BIN" "$SWIFTBAR_TOGGLE_CFG"
cp "$ROOT/bin/tmux-whisper" "$SWIFTBAR_TOGGLE_BIN/tmux-whisper"
cp "$ROOT/bin/dictate-lib.sh" "$SWIFTBAR_TOGGLE_BIN/dictate-lib.sh"
chmod +x "$SWIFTBAR_TOGGLE_BIN/tmux-whisper" "$SWIFTBAR_TOGGLE_BIN/dictate-lib.sh"
cat >"$SWIFTBAR_TOGGLE_CFG/config.toml" <<'EOF'
[meta]
config_version = 1

[audio]
source = "auto"

[integrations.swiftbar]
enabled = false
EOF

swiftbar_show_off="$(HOME="$SWIFTBAR_TOGGLE_HOME" PATH="$SWIFTBAR_TOGGLE_BIN:/usr/bin:/bin" DICTATE_LIB_PATH= DICTATE_CONFIG_DIR="$SWIFTBAR_TOGGLE_CFG" DICTATE_CONFIG_FILE="$SWIFTBAR_TOGGLE_CFG/config.toml" tmux-whisper swiftbar)"
assert_contains "swiftbar_cli_show_off" "$swiftbar_show_off" "SwiftBar integration: OFF"

swiftbar_cli_on="$(HOME="$SWIFTBAR_TOGGLE_HOME" PATH="$SWIFTBAR_TOGGLE_BIN:/usr/bin:/bin" DICTATE_LIB_PATH= DICTATE_CONFIG_DIR="$SWIFTBAR_TOGGLE_CFG" DICTATE_CONFIG_FILE="$SWIFTBAR_TOGGLE_CFG/config.toml" tmux-whisper swiftbar on)"
assert_contains "swiftbar_cli_on" "$swiftbar_cli_on" "SwiftBar integration: ON"

swiftbar_cli_toggle="$(HOME="$SWIFTBAR_TOGGLE_HOME" PATH="$SWIFTBAR_TOGGLE_BIN:/usr/bin:/bin" DICTATE_LIB_PATH= DICTATE_CONFIG_DIR="$SWIFTBAR_TOGGLE_CFG" DICTATE_CONFIG_FILE="$SWIFTBAR_TOGGLE_CFG/config.toml" tmux-whisper swiftbar toggle)"
assert_contains "swiftbar_cli_toggle" "$swiftbar_cli_toggle" "SwiftBar integration: OFF"

swiftbar_toggle_out="$(HOME="$SWIFTBAR_TOGGLE_HOME" XDG_CONFIG_HOME="$SWIFTBAR_TOGGLE_HOME/.config" PATH="$SWIFTBAR_TOGGLE_BIN:$STUB_BIN:/usr/bin:/bin" SWIFTBAR_PLUGIN_CACHE_PATH="$SWIFTBAR_TOGGLE_HOME/.cache/swiftbar" DICTATE_BIN="$SWIFTBAR_TOGGLE_BIN/tmux-whisper" bash "$ROOT/integrations/tmux-whisper-status.0.2s.sh")"
assert_contains "swiftbar_plugin_off_state" "$swiftbar_toggle_out" "SwiftBar integration: OFF"
assert_contains "swiftbar_plugin_off_enable_action" "$swiftbar_toggle_out" "Enable SwiftBar integration"

# --- Regression 8: vocab import/export/dedupe safety behavior remains stable. ---
VOCAB_HOME="$TMP_ROOT/home-vocab"
VOCAB_BIN="$VOCAB_HOME/.local/bin"
VOCAB_CFG="$VOCAB_HOME/.config/dictate"
mkdir -p "$VOCAB_BIN" "$VOCAB_CFG"
cp "$ROOT/bin/tmux-whisper" "$VOCAB_BIN/tmux-whisper"
cp "$ROOT/bin/dictate-lib.sh" "$VOCAB_BIN/dictate-lib.sh"
chmod +x "$VOCAB_BIN/tmux-whisper" "$VOCAB_BIN/dictate-lib.sh"

IMPORT_FILE="$TMP_ROOT/vocab-import.txt"
cat >"$IMPORT_FILE" <<'EOF'
health lag::help flag
my app -> MyApp
codex → Codex
bad line
EOF

import_out="$(HOME="$VOCAB_HOME" PATH="$VOCAB_BIN:/usr/bin:/bin" DICTATE_LIB_PATH= DICTATE_CONFIG_DIR="$VOCAB_CFG" DICTATE_CONFIG_FILE="$VOCAB_CFG/config.toml" tmux-whisper vocab import "$IMPORT_FILE")"
assert_contains "vocab_import_summary" "$import_out" "Vocab import ($IMPORT_FILE): added=3 duplicate=0 invalid=1"
assert_contains "vocab_import_invalid_preview" "$import_out" "line 4: bad line"

EXPORT_FILE="$TMP_ROOT/vocab-export.txt"
export_out="$(HOME="$VOCAB_HOME" PATH="$VOCAB_BIN:/usr/bin:/bin" DICTATE_LIB_PATH= DICTATE_CONFIG_DIR="$VOCAB_CFG" DICTATE_CONFIG_FILE="$VOCAB_CFG/config.toml" tmux-whisper vocab export "$EXPORT_FILE")"
assert_contains "vocab_export_summary" "$export_out" "Vocab export ($EXPORT_FILE): entries=3 duplicate_skipped=0 invalid_skipped=0"
assert_file_contains "vocab_export_arrow_normalized" "$EXPORT_FILE" "my app → MyApp"

printf '%s\n' 'health lag::help flag' 'still bad' >>"$VOCAB_CFG/vocab"
dedupe_out="$(HOME="$VOCAB_HOME" PATH="$VOCAB_BIN:/usr/bin:/bin" DICTATE_LIB_PATH= DICTATE_CONFIG_DIR="$VOCAB_CFG" DICTATE_CONFIG_FILE="$VOCAB_CFG/config.toml" tmux-whisper vocab dedupe)"
assert_contains "vocab_dedupe_summary" "$dedupe_out" "duplicate_removed=1 invalid_removed=1"
assert_contains "vocab_dedupe_backup_line" "$dedupe_out" "Backup: "
dedupe_backup="$(printf "%s\n" "$dedupe_out" | sed -n 's/^Backup: //p' | head -n 1)"
assert_file_exists "vocab_dedupe_backup_exists" "$dedupe_backup"

# --- Regression 9: bench-matrix UX checks are stable. ---
BENCH_HOME="$TMP_ROOT/home-bench"
BENCH_BIN="$BENCH_HOME/.local/bin"
BENCH_CFG="$BENCH_HOME/.config/dictate"
mkdir -p "$BENCH_BIN" "$BENCH_CFG"
cp "$ROOT/bin/tmux-whisper" "$BENCH_BIN/tmux-whisper"
cp "$ROOT/bin/dictate-lib.sh" "$BENCH_BIN/dictate-lib.sh"
chmod +x "$BENCH_BIN/tmux-whisper" "$BENCH_BIN/dictate-lib.sh"

bench_bad_n_out="$(HOME="$BENCH_HOME" PATH="$BENCH_BIN:/usr/bin:/bin" DICTATE_LIB_PATH= DICTATE_CONFIG_DIR="$BENCH_CFG" DICTATE_CONFIG_FILE="$BENCH_CFG/config.toml" CEREBRAS_API_KEY= tmux-whisper bench-matrix nope 2>&1 || true)"
assert_contains "bench_matrix_invalid_n_usage" "$bench_bad_n_out" "usage: tmux-whisper bench-matrix [N] [phrase_file]"

bench_missing_phrase_out="$(HOME="$BENCH_HOME" PATH="$BENCH_BIN:/usr/bin:/bin" DICTATE_LIB_PATH= DICTATE_CONFIG_DIR="$BENCH_CFG" DICTATE_CONFIG_FILE="$BENCH_CFG/config.toml" CEREBRAS_API_KEY= tmux-whisper bench-matrix 1 "$TMP_ROOT/no-such-phrases.txt" 2>&1 || true)"
assert_contains "bench_matrix_missing_phrase_file" "$bench_missing_phrase_out" "phrase file not found:"

bench_matrix_out="$(HOME="$BENCH_HOME" PATH="$BENCH_BIN:/usr/bin:/bin" DICTATE_LIB_PATH= DICTATE_CONFIG_DIR="$BENCH_CFG" DICTATE_CONFIG_FILE="$BENCH_CFG/config.toml" CEREBRAS_API_KEY= tmux-whisper bench-matrix 1)"
assert_contains "bench_matrix_smoke_header" "$bench_matrix_out" "Tmux Whisper bench-matrix"
assert_contains "bench_matrix_smoke_skip_note" "$bench_matrix_out" "postprocess=on combos skipped"

BENCH_PHRASES_FILE="$TMP_ROOT/bench-phrases.txt"
cat >"$BENCH_PHRASES_FILE" <<'EOF'
# label<TAB>phrase format is supported
ops-check	please check the current install status
just a plain phrase line
EOF

bench_matrix_file_out="$(HOME="$BENCH_HOME" PATH="$BENCH_BIN:/usr/bin:/bin" DICTATE_LIB_PATH= DICTATE_CONFIG_DIR="$BENCH_CFG" DICTATE_CONFIG_FILE="$BENCH_CFG/config.toml" CEREBRAS_API_KEY= DICTATE_BENCH_MATRIX_PROGRESS=0 tmux-whisper bench-matrix 1 "$BENCH_PHRASES_FILE")"
assert_contains "bench_matrix_phrase_file_count" "$bench_matrix_file_out" "Phrases: 2"
assert_contains "bench_matrix_header_llm_model" "$bench_matrix_file_out" "llm_model"
assert_not_contains "bench_matrix_progress_suppressed" "$bench_matrix_file_out" "bench-matrix: combo"

echo "Regression tests passed."
