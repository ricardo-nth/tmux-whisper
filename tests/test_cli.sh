#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

BIN_DIR="$TMP_ROOT/bin"
HOME_DIR="$TMP_ROOT/home"
mkdir -p "$BIN_DIR" "$HOME_DIR"

cp "$ROOT/bin/dictate" "$BIN_DIR/dictate"
cp "$ROOT/bin/dictate-lib.sh" "$BIN_DIR/dictate-lib.sh"
chmod +x "$BIN_DIR/dictate" "$BIN_DIR/dictate-lib.sh"

# Ensure the default ~/.local/bin path is unavailable and fallback-to-sibling works.
output="$(HOME="$HOME_DIR" PATH="$BIN_DIR:/usr/bin:/bin" DICTATE_LIB_PATH= "$BIN_DIR/dictate" --help)"

if [[ "$output" != *"dictate: local whisper.cpp dictation"* ]]; then
  echo "Expected help output from dictate command" >&2
  exit 1
fi

echo "CLI relocation smoke test passed."
