#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
swift build --package-path "$ROOT" -c release
BIN_DIR="$(swift build --package-path "$ROOT" -c release --show-bin-path)"
APP="$ROOT/.build/Tmux Whisper Companion.app"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN_DIR/WhisperCompanion" "$APP/Contents/MacOS/WhisperCompanion"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
printf '%s\n' "$APP"
