#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$ROOT/build.sh"
# Launch directly so explicit CLI/environment overrides reach the app.
exec "$ROOT/.build/Tmux Whisper Companion.app/Contents/MacOS/WhisperCompanion" "$@"
