#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

# Build a local archive that mirrors GitHub codeload structure: tmux-whisper-<ref>/
ARCHIVE_ROOT="$TMP_ROOT/archive-root"
SNAPSHOT_DIR="$ARCHIVE_ROOT/tmux-whisper-main"
mkdir -p "$SNAPSHOT_DIR"

(
  cd "$ROOT"
  tar --exclude='.git' -cf "$TMP_ROOT/src.tar" .
)
tar -xf "$TMP_ROOT/src.tar" -C "$SNAPSHOT_DIR"
tar -czf "$TMP_ROOT/tmux-whisper-main.tar.gz" -C "$ARCHIVE_ROOT" tmux-whisper-main

HOME="$TMP_ROOT/home"
export HOME
mkdir -p "$HOME"

ARCHIVE_URL="file://$TMP_ROOT/tmux-whisper-main.tar.gz"

assert_file() {
  local path="$1"
  [[ -f "$path" ]] || {
    echo "Missing file: $path" >&2
    exit 1
  }
}

assert_not_file() {
  local path="$1"
  [[ ! -f "$path" ]] || {
    echo "Unexpected file present: $path" >&2
    exit 1
  }
}

bootstrap_help="$("$ROOT/bootstrap.sh" --help)"
if [[ "$bootstrap_help" != *"Installs Tmux Whisper from a GitHub source archive."* ]]; then
  echo "Expected bootstrap help to describe Tmux Whisper branding" >&2
  exit 1
fi
if [[ "$bootstrap_help" != *"--ref v0.6.0 --force"* ]]; then
  echo "Expected bootstrap help to show a pinned ref example" >&2
  exit 1
fi
if [[ "$bootstrap_help" != *"v0.6.0/bootstrap.sh"* ]]; then
  echo "Expected bootstrap help to reference the next stable tag example" >&2
  exit 1
fi

# Pass-through args should reach install.sh.
bootstrap_output="$(DICTATE_BOOTSTRAP_ARCHIVE_URL="$ARCHIVE_URL" "$ROOT/bootstrap.sh" --no-sounds)"
if [[ "$bootstrap_output" != *"Bootstrap source: ricardo-nth/tmux-whisper@main"* ]]; then
  echo "Expected bootstrap output to report source repo/ref" >&2
  exit 1
fi
if [[ "$bootstrap_output" != *"Bootstrap archive: $ARCHIVE_URL"* ]]; then
  echo "Expected bootstrap output to report archive URL" >&2
  exit 1
fi

assert_file "$HOME/.local/bin/tmux-whisper"
assert_file "$HOME/.config/dictate/config.toml"
assert_file "$HOME/.config/dictate/install-receipt.env"
assert_not_file "$HOME/.local/share/sounds/dictate/start.wav"
if ! rg -q '^install_source=bootstrap:ricardo-nth/tmux-whisper@main$' "$HOME/.config/dictate/install-receipt.env"; then
  echo "Expected bootstrap install receipt source" >&2
  exit 1
fi

DICTATE_BOOTSTRAP_REF=ignored "$ROOT/bootstrap.sh" --archive-url "$ARCHIVE_URL" --ref test-ref --with-sounds
assert_file "$HOME/.local/share/sounds/dictate/start.wav"
if ! rg -q '^install_source=bootstrap:ricardo-nth/tmux-whisper@test-ref$' "$HOME/.config/dictate/install-receipt.env"; then
  echo "Expected --ref to be reflected in bootstrap install receipt" >&2
  exit 1
fi

echo "Bootstrap smoke tests passed."
