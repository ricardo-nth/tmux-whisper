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
cp "$ROOT/bin/dictate" "$CUSTOM_BIN/dictate"
cp "$ROOT/bin/dictate-lib.sh" "$CUSTOM_BIN/dictate-lib.sh"
chmod +x "$CUSTOM_BIN/dictate" "$CUSTOM_BIN/dictate-lib.sh"
CUSTOM_DICTATE_CONFIG_DIR="$CUSTOM_HOME/.config/dictate"
CUSTOM_DICTATE_CONFIG_FILE="$CUSTOM_DICTATE_CONFIG_DIR/config.toml"

custom_debug="$(HOME="$CUSTOM_HOME" PATH="$CUSTOM_BIN:/usr/bin:/bin" DICTATE_LIB_PATH= DICTATE_CONFIG_DIR="$CUSTOM_DICTATE_CONFIG_DIR" DICTATE_CONFIG_FILE="$CUSTOM_DICTATE_CONFIG_FILE" "$CUSTOM_BIN/dictate" debug)"
assert_contains "debug_channel_present" "$custom_debug" "channel: "
assert_contains "debug_paths_section" "$custom_debug" "Paths:"
assert_contains "debug_install_lib_line" "$custom_debug" "lib:"

custom_doctor="$(HOME="$CUSTOM_HOME" PATH="$CUSTOM_BIN:/usr/bin:/bin" DICTATE_LIB_PATH= DICTATE_CONFIG_DIR="$CUSTOM_DICTATE_CONFIG_DIR" DICTATE_CONFIG_FILE="$CUSTOM_DICTATE_CONFIG_FILE" "$CUSTOM_BIN/dictate" doctor)"
assert_contains "doctor_install_sanity_section" "$custom_doctor" "Install sanity:"
assert_contains "doctor_channel_present" "$custom_doctor" "install channel: "
assert_contains "doctor_schema_ok" "$custom_doctor" "config schema: v1 (expected v1, status=ok)"

# --- Regression 2: install-channel detection should work for local user installs. ---
LOCAL_HOME="$TMP_ROOT/home-local"
LOCAL_BIN="$LOCAL_HOME/.local/bin"
mkdir -p "$LOCAL_BIN"
cp "$ROOT/bin/dictate" "$LOCAL_BIN/dictate"
cp "$ROOT/bin/dictate-lib.sh" "$LOCAL_BIN/dictate-lib.sh"
chmod +x "$LOCAL_BIN/dictate" "$LOCAL_BIN/dictate-lib.sh"
LOCAL_DICTATE_CONFIG_DIR="$LOCAL_HOME/.config/dictate"
LOCAL_DICTATE_CONFIG_FILE="$LOCAL_DICTATE_CONFIG_DIR/config.toml"

local_debug="$(HOME="$LOCAL_HOME" PATH="$LOCAL_BIN:/usr/bin:/bin" DICTATE_LIB_PATH= DICTATE_CONFIG_DIR="$LOCAL_DICTATE_CONFIG_DIR" DICTATE_CONFIG_FILE="$LOCAL_DICTATE_CONFIG_FILE" dictate debug)"
assert_contains "debug_local_user_channel" "$local_debug" "channel: local-user"

# --- Regression 3: doctor should fail on schema mismatch. ---
MISMATCH_HOME="$TMP_ROOT/home-mismatch"
MISMATCH_BIN="$MISMATCH_HOME/.local/bin"
MISMATCH_CFG="$MISMATCH_HOME/.config/dictate"
mkdir -p "$MISMATCH_BIN" "$MISMATCH_CFG"
cp "$ROOT/bin/dictate" "$MISMATCH_BIN/dictate"
cp "$ROOT/bin/dictate-lib.sh" "$MISMATCH_BIN/dictate-lib.sh"
chmod +x "$MISMATCH_BIN/dictate" "$MISMATCH_BIN/dictate-lib.sh"
cat >"$MISMATCH_CFG/config.toml" <<'EOF'
[meta]
config_version = 0

[audio]
source = "auto"
EOF
mismatch_doctor="$(HOME="$MISMATCH_HOME" PATH="$MISMATCH_BIN:/usr/bin:/bin" DICTATE_LIB_PATH= DICTATE_CONFIG_DIR="$MISMATCH_CFG" DICTATE_CONFIG_FILE="$MISMATCH_CFG/config.toml" dictate doctor)"
assert_contains "doctor_schema_mismatch_status" "$mismatch_doctor" "config schema: v0 (expected v1, status=mismatch)"
assert_contains "doctor_schema_mismatch_hint" "$mismatch_doctor" "this build requires config schema v1"
assert_contains "doctor_schema_suggested_fixes" "$mismatch_doctor" "Suggested fixes:"
assert_contains "doctor_schema_suggested_install" "$mismatch_doctor" "Refresh defaults from repo: ./install.sh --force"

# --- Regression 4: doctor mode checks should show clear fallbacks + fixes. ---
MODECHECK_HOME="$TMP_ROOT/home-modecheck"
MODECHECK_BIN="$MODECHECK_HOME/.local/bin"
MODECHECK_CFG="$MODECHECK_HOME/.config/dictate"
mkdir -p "$MODECHECK_BIN" "$MODECHECK_CFG/modes/short" "$MODECHECK_CFG/modes/long"
cp "$ROOT/bin/dictate" "$MODECHECK_BIN/dictate"
cp "$ROOT/bin/dictate-lib.sh" "$MODECHECK_BIN/dictate-lib.sh"
chmod +x "$MODECHECK_BIN/dictate" "$MODECHECK_BIN/dictate-lib.sh"
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
modecheck_doctor="$(HOME="$MODECHECK_HOME" PATH="$MODECHECK_BIN:/usr/bin:/bin" DICTATE_LIB_PATH= DICTATE_CONFIG_DIR="$MODECHECK_CFG" DICTATE_CONFIG_FILE="$MODECHECK_CFG/config.toml" dictate doctor)"
assert_contains "doctor_modecheck_section" "$modecheck_doctor" "Mode/config:"
assert_contains "doctor_modecheck_fixed_invalid" "$modecheck_doctor" "mode.current: ghost (invalid, fallback=short)"
assert_contains "doctor_modecheck_tmux_invalid" "$modecheck_doctor" "tmux.mode: ghost (invalid, fallback=short)"
assert_contains "doctor_modecheck_fix_mode" "$modecheck_doctor" "Set a valid fixed mode: dictate mode short"
assert_contains "doctor_modecheck_fix_tmux" "$modecheck_doctor" "Set tmux mode to a valid mode: dictate tmux mode short"

# --- Regression 5: integration scripts keep PATH-based command resolution. ---
assert_file_contains "raycast_inline_lib_resolution" "$ROOT/integrations/raycast/dictate-inline.sh" "command -v dictate-lib.sh"
assert_file_contains "raycast_toggle_dictate_resolution" "$ROOT/integrations/raycast/dictate-toggle.sh" "command -v dictate"
assert_file_contains "swiftbar_dictate_resolution" "$ROOT/integrations/dictate-status.0.2s.sh" "command -v dictate"
assert_file_contains "raycast_inline_path_hardening" "$ROOT/integrations/raycast/dictate-inline.sh" "/usr/local/bin"
assert_file_contains "raycast_toggle_path_hardening" "$ROOT/integrations/raycast/dictate-toggle.sh" "/usr/local/bin"
assert_file_contains "raycast_cancel_path_hardening" "$ROOT/integrations/raycast/dictate-cancel.sh" "/usr/local/bin"
assert_file_contains "swiftbar_path_hardening" "$ROOT/integrations/dictate-status.0.2s.sh" "/usr/local/bin"
assert_file_contains "raycast_inline_dependency_notice" "$ROOT/integrations/raycast/dictate-inline.sh" 'Missing dependency: $dep'
assert_file_contains "raycast_toggle_binary_notice" "$ROOT/integrations/raycast/dictate-toggle.sh" "Dictate binary not found."
assert_file_contains "swiftbar_missing_binary_notice" "$ROOT/integrations/dictate-status.0.2s.sh" "Dictate binary not found | color=red"
assert_file_contains "swiftbar_enabled_config_parse" "$ROOT/integrations/dictate-status.0.2s.sh" "integrations.swiftbar.enabled"

# --- Regression 6: script-level behavior for missing dictate binary is explicit. ---
TOGGLE_HOME="$TMP_ROOT/home-toggle"
mkdir -p "$TOGGLE_HOME"
toggle_out="$(HOME="$TOGGLE_HOME" PATH="$STUB_BIN:/usr/bin:/bin" DICTATE_BIN="$TMP_ROOT/not-found-dictate" bash "$ROOT/integrations/raycast/dictate-toggle.sh" 2>&1 || true)"
assert_contains "raycast_toggle_missing_binary_runtime" "$toggle_out" "dictate-toggle: Dictate binary not found."

SWIFTBAR_HOME="$TMP_ROOT/home-swiftbar"
mkdir -p "$SWIFTBAR_HOME"
swiftbar_out="$(HOME="$SWIFTBAR_HOME" PATH="$STUB_BIN:/usr/bin:/bin" DICTATE_BIN="$TMP_ROOT/not-found-dictate" bash "$ROOT/integrations/dictate-status.0.2s.sh")"
assert_contains "swiftbar_missing_binary_runtime" "$swiftbar_out" "Dictate binary not found"

# --- Regression 7: SwiftBar runtime integration toggle works end-to-end. ---
SWIFTBAR_TOGGLE_HOME="$TMP_ROOT/home-swiftbar-toggle"
SWIFTBAR_TOGGLE_BIN="$SWIFTBAR_TOGGLE_HOME/.local/bin"
SWIFTBAR_TOGGLE_CFG="$SWIFTBAR_TOGGLE_HOME/.config/dictate"
mkdir -p "$SWIFTBAR_TOGGLE_BIN" "$SWIFTBAR_TOGGLE_CFG"
cp "$ROOT/bin/dictate" "$SWIFTBAR_TOGGLE_BIN/dictate"
cp "$ROOT/bin/dictate-lib.sh" "$SWIFTBAR_TOGGLE_BIN/dictate-lib.sh"
chmod +x "$SWIFTBAR_TOGGLE_BIN/dictate" "$SWIFTBAR_TOGGLE_BIN/dictate-lib.sh"
cat >"$SWIFTBAR_TOGGLE_CFG/config.toml" <<'EOF'
[meta]
config_version = 1

[audio]
source = "auto"

[integrations.swiftbar]
enabled = false
EOF

swiftbar_show_off="$(HOME="$SWIFTBAR_TOGGLE_HOME" PATH="$SWIFTBAR_TOGGLE_BIN:/usr/bin:/bin" DICTATE_LIB_PATH= DICTATE_CONFIG_DIR="$SWIFTBAR_TOGGLE_CFG" DICTATE_CONFIG_FILE="$SWIFTBAR_TOGGLE_CFG/config.toml" dictate swiftbar)"
assert_contains "swiftbar_cli_show_off" "$swiftbar_show_off" "SwiftBar integration: OFF"

swiftbar_cli_on="$(HOME="$SWIFTBAR_TOGGLE_HOME" PATH="$SWIFTBAR_TOGGLE_BIN:/usr/bin:/bin" DICTATE_LIB_PATH= DICTATE_CONFIG_DIR="$SWIFTBAR_TOGGLE_CFG" DICTATE_CONFIG_FILE="$SWIFTBAR_TOGGLE_CFG/config.toml" dictate swiftbar on)"
assert_contains "swiftbar_cli_on" "$swiftbar_cli_on" "SwiftBar integration: ON"

swiftbar_cli_toggle="$(HOME="$SWIFTBAR_TOGGLE_HOME" PATH="$SWIFTBAR_TOGGLE_BIN:/usr/bin:/bin" DICTATE_LIB_PATH= DICTATE_CONFIG_DIR="$SWIFTBAR_TOGGLE_CFG" DICTATE_CONFIG_FILE="$SWIFTBAR_TOGGLE_CFG/config.toml" dictate swiftbar toggle)"
assert_contains "swiftbar_cli_toggle" "$swiftbar_cli_toggle" "SwiftBar integration: OFF"

swiftbar_toggle_out="$(HOME="$SWIFTBAR_TOGGLE_HOME" XDG_CONFIG_HOME="$SWIFTBAR_TOGGLE_HOME/.config" PATH="$SWIFTBAR_TOGGLE_BIN:$STUB_BIN:/usr/bin:/bin" SWIFTBAR_PLUGIN_CACHE_PATH="$SWIFTBAR_TOGGLE_HOME/.cache/swiftbar" DICTATE_BIN="$SWIFTBAR_TOGGLE_BIN/dictate" bash "$ROOT/integrations/dictate-status.0.2s.sh")"
assert_contains "swiftbar_plugin_off_state" "$swiftbar_toggle_out" "SwiftBar integration: OFF"
assert_contains "swiftbar_plugin_off_enable_action" "$swiftbar_toggle_out" "Enable SwiftBar integration"

# --- Regression 8: vocab import/export/dedupe safety behavior remains stable. ---
VOCAB_HOME="$TMP_ROOT/home-vocab"
VOCAB_BIN="$VOCAB_HOME/.local/bin"
VOCAB_CFG="$VOCAB_HOME/.config/dictate"
mkdir -p "$VOCAB_BIN" "$VOCAB_CFG"
cp "$ROOT/bin/dictate" "$VOCAB_BIN/dictate"
cp "$ROOT/bin/dictate-lib.sh" "$VOCAB_BIN/dictate-lib.sh"
chmod +x "$VOCAB_BIN/dictate" "$VOCAB_BIN/dictate-lib.sh"

IMPORT_FILE="$TMP_ROOT/vocab-import.txt"
cat >"$IMPORT_FILE" <<'EOF'
health lag::help flag
my app -> MyApp
codex → Codex
bad line
EOF

import_out="$(HOME="$VOCAB_HOME" PATH="$VOCAB_BIN:/usr/bin:/bin" DICTATE_LIB_PATH= DICTATE_CONFIG_DIR="$VOCAB_CFG" DICTATE_CONFIG_FILE="$VOCAB_CFG/config.toml" dictate vocab import "$IMPORT_FILE")"
assert_contains "vocab_import_summary" "$import_out" "Vocab import ($IMPORT_FILE): added=3 duplicate=0 invalid=1"
assert_contains "vocab_import_invalid_preview" "$import_out" "line 4: bad line"

EXPORT_FILE="$TMP_ROOT/vocab-export.txt"
export_out="$(HOME="$VOCAB_HOME" PATH="$VOCAB_BIN:/usr/bin:/bin" DICTATE_LIB_PATH= DICTATE_CONFIG_DIR="$VOCAB_CFG" DICTATE_CONFIG_FILE="$VOCAB_CFG/config.toml" dictate vocab export "$EXPORT_FILE")"
assert_contains "vocab_export_summary" "$export_out" "Vocab export ($EXPORT_FILE): entries=3 duplicate_skipped=0 invalid_skipped=0"
assert_file_contains "vocab_export_arrow_normalized" "$EXPORT_FILE" "my app → MyApp"

printf '%s\n' 'health lag::help flag' 'still bad' >>"$VOCAB_CFG/vocab"
dedupe_out="$(HOME="$VOCAB_HOME" PATH="$VOCAB_BIN:/usr/bin:/bin" DICTATE_LIB_PATH= DICTATE_CONFIG_DIR="$VOCAB_CFG" DICTATE_CONFIG_FILE="$VOCAB_CFG/config.toml" dictate vocab dedupe)"
assert_contains "vocab_dedupe_summary" "$dedupe_out" "duplicate_removed=1 invalid_removed=1"
assert_contains "vocab_dedupe_backup_line" "$dedupe_out" "Backup: "
dedupe_backup="$(printf "%s\n" "$dedupe_out" | sed -n 's/^Backup: //p' | head -n 1)"
assert_file_exists "vocab_dedupe_backup_exists" "$dedupe_backup"

echo "Regression tests passed."
