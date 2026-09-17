#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

BIN_DIR="$TMP_ROOT/bin"
HOME_DIR="$TMP_ROOT/home"
CONFIG_DIR="$HOME_DIR/.config/dictate"
mkdir -p "$BIN_DIR" "$HOME_DIR" "$CONFIG_DIR"
BIN_REAL="$(cd "$BIN_DIR" && pwd -P)/tmux-whisper"

cp "$ROOT/bin/tmux-whisper" "$BIN_DIR/tmux-whisper"
cp "$ROOT/bin/dictate-lib.sh" "$BIN_DIR/dictate-lib.sh"
cp -R "$ROOT/bin/tmux-whisper-lib" "$BIN_DIR/tmux-whisper-lib"
chmod +x "$BIN_DIR/tmux-whisper" "$BIN_DIR/dictate-lib.sh"

run_version() {
  HOME="$HOME_DIR" \
  PATH="$BIN_DIR:/usr/bin:/bin" \
  DICTATE_LIB_PATH= \
  DICTATE_CONFIG_DIR="$CONFIG_DIR" \
  DICTATE_CONFIG_FILE="$CONFIG_DIR/config.toml" \
  "$BIN_DIR/tmux-whisper" "$@"
}

assert_contains() {
  local name="$1"
  local value="$2"
  local expected="$3"
  if [[ "$value" != *"$expected"* ]]; then
    echo "Expected $name to contain: $expected" >&2
    echo "Actual: $value" >&2
    exit 1
  fi
  echo "PASS: $name"
}

missing_text="$(run_version version)"
assert_contains "missing_cli_version" "$missing_text" "CLI version: 0.7.0-dev"
assert_contains "missing_config_schema" "$missing_text" "Config schema: v1"
assert_contains "missing_running_binary" "$missing_text" "Running binary: $BIN_REAL"
assert_contains "missing_receipt" "$missing_text" "Install receipt: missing ($CONFIG_DIR/install-receipt.env)"

# A source checkout must fall back as a complete runtime when an older local
# library directory exists but cannot provide this newly added module.
mkdir -p "$HOME_DIR/.local/bin/tmux-whisper-lib"
source_text="$(HOME="$HOME_DIR" PATH="/usr/bin:/bin" DICTATE_CONFIG_DIR="$CONFIG_DIR" DICTATE_CONFIG_FILE="$CONFIG_DIR/config.toml" "$ROOT/bin/tmux-whisper" version)"
assert_contains "source_checkout_stale_lib_fallback" "$source_text" "Running binary: $ROOT/bin/tmux-whisper"

missing_json="$(run_version version --json)"
VERSION_JSON="$missing_json" python3 - <<'PYEOF'
import json
import os

payload = json.loads(os.environ["VERSION_JSON"])
assert payload["command"] == "version"
assert payload["schema_version"] == 1
assert payload["cli_version"] == "0.7.0-dev"
assert payload["config_schema_version"] == 1
assert payload["running_binary"]["path"].endswith("/bin/tmux-whisper")
assert payload["receipt"]["present"] is False
assert payload["receipt"]["installed_at"] is None
assert payload["receipt"]["source"] is None
assert payload["receipt"]["ref"] is None
assert payload["receipt"]["commit"] is None
PYEOF
echo "PASS: missing_receipt_json"

cat >"$CONFIG_DIR/install-receipt.env" <<'EOF'
installed_at=2026-09-17T10:00:00Z
install_source=bootstrap:ricardo-nth/tmux-whisper@v0.7.0
repo_git_ref=release\ candidate
repo_git_commit=0123456789abcdef
bin_path=/a/source/checkout/bin/tmux-whisper
EOF

present_text="$(run_version version)"
assert_contains "present_receipt" "$present_text" "Install receipt: present ($CONFIG_DIR/install-receipt.env)"
assert_contains "present_installed_at" "$present_text" "installed at: 2026-09-17T10:00:00Z"
assert_contains "present_source" "$present_text" "source: bootstrap:ricardo-nth/tmux-whisper@v0.7.0"
assert_contains "present_ref" "$present_text" "ref: release candidate"
assert_contains "present_commit" "$present_text" "commit: 0123456789abcdef"
assert_contains "receipt_binary_separation" "$present_text" "Receipt provenance records install metadata; the running binary is listed separately."

alias_text="$(run_version --version)"
if [[ "$alias_text" != "$present_text" ]]; then
  echo "Expected --version to match version output" >&2
  exit 1
fi
echo "PASS: version_alias"

present_json="$(run_version version --json)"
VERSION_JSON="$present_json" python3 - <<'PYEOF'
import json
import os

payload = json.loads(os.environ["VERSION_JSON"])
receipt = payload["receipt"]
assert receipt["present"] is True
assert receipt["readable"] is True
assert receipt["installed_at"] == "2026-09-17T10:00:00Z"
assert receipt["source"] == "bootstrap:ricardo-nth/tmux-whisper@v0.7.0"
assert receipt["ref"] == "release candidate"
assert receipt["commit"] == "0123456789abcdef"
PYEOF
echo "PASS: present_receipt_json"

echo "Version command tests passed."
