#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

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

custom_debug="$(HOME="$CUSTOM_HOME" PATH="$CUSTOM_BIN:/usr/bin:/bin" DICTATE_LIB_PATH= "$CUSTOM_BIN/dictate" debug)"
assert_contains "debug_channel_present" "$custom_debug" "channel: "
assert_contains "debug_paths_section" "$custom_debug" "Paths:"
assert_contains "debug_install_lib_line" "$custom_debug" "lib:"

custom_doctor="$(HOME="$CUSTOM_HOME" PATH="$CUSTOM_BIN:/usr/bin:/bin" DICTATE_LIB_PATH= "$CUSTOM_BIN/dictate" doctor)"
assert_contains "doctor_install_sanity_section" "$custom_doctor" "Install sanity:"
assert_contains "doctor_channel_present" "$custom_doctor" "install channel: "

# --- Regression 2: install-channel detection should work for local user installs. ---
LOCAL_HOME="$TMP_ROOT/home-local"
LOCAL_BIN="$LOCAL_HOME/.local/bin"
mkdir -p "$LOCAL_BIN"
cp "$ROOT/bin/dictate" "$LOCAL_BIN/dictate"
cp "$ROOT/bin/dictate-lib.sh" "$LOCAL_BIN/dictate-lib.sh"
chmod +x "$LOCAL_BIN/dictate" "$LOCAL_BIN/dictate-lib.sh"

local_debug="$(HOME="$LOCAL_HOME" PATH="$LOCAL_BIN:/usr/bin:/bin" DICTATE_LIB_PATH= dictate debug)"
assert_contains "debug_local_user_channel" "$local_debug" "channel: local-user"

# --- Regression 3: integration scripts keep PATH-based command resolution. ---
assert_file_contains "raycast_inline_lib_resolution" "$ROOT/integrations/raycast/dictate-inline.sh" "command -v dictate-lib.sh"
assert_file_contains "raycast_toggle_dictate_resolution" "$ROOT/integrations/raycast/dictate-toggle.sh" "command -v dictate"
assert_file_contains "swiftbar_dictate_resolution" "$ROOT/integrations/dictate-status.0.2s.sh" "command -v dictate"

echo "Regression tests passed."
