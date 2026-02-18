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

# --- Regression 4: integration scripts keep PATH-based command resolution. ---
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

# --- Regression 5: script-level behavior for missing dictate binary is explicit. ---
TOGGLE_HOME="$TMP_ROOT/home-toggle"
mkdir -p "$TOGGLE_HOME"
toggle_out="$(HOME="$TOGGLE_HOME" PATH="$STUB_BIN:/usr/bin:/bin" DICTATE_BIN="$TMP_ROOT/not-found-dictate" bash "$ROOT/integrations/raycast/dictate-toggle.sh" 2>&1 || true)"
assert_contains "raycast_toggle_missing_binary_runtime" "$toggle_out" "dictate-toggle: Dictate binary not found."

SWIFTBAR_HOME="$TMP_ROOT/home-swiftbar"
mkdir -p "$SWIFTBAR_HOME"
swiftbar_out="$(HOME="$SWIFTBAR_HOME" PATH="$STUB_BIN:/usr/bin:/bin" DICTATE_BIN="$TMP_ROOT/not-found-dictate" bash "$ROOT/integrations/dictate-status.0.2s.sh")"
assert_contains "swiftbar_missing_binary_runtime" "$swiftbar_out" "Dictate binary not found"

echo "Regression tests passed."
