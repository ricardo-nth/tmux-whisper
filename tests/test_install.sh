#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_HOME="$(mktemp -d)"
trap 'rm -rf "$TMP_HOME"' EXIT

export HOME="$TMP_HOME/home"
mkdir -p "$HOME"

assert_file() {
  local path="$1"
  [[ -f "$path" ]] || {
    echo "Missing file: $path" >&2
    exit 1
  }
}

assert_exec() {
  local path="$1"
  [[ -x "$path" ]] || {
    echo "Missing executable bit: $path" >&2
    exit 1
  }
}

"$ROOT/install.sh" --with-sounds

assert_exec "$HOME/.local/bin/tmux-whisper"
assert_exec "$HOME/.local/bin/dictate-lib.sh"
assert_file "$HOME/.config/dictate/config.toml"
assert_file "$HOME/.config/dictate/current-mode"
assert_file "$HOME/.config/dictate/vocab"
assert_file "$HOME/.config/dictate/integrations/raycast/tmux-whisper-inline.sh"
assert_file "$HOME/.config/swiftbar/plugins/tmux-whisper-status.0.2s.sh"
assert_file "$HOME/.local/share/sounds/dictate/start.wav"

# Non-force install should preserve user-edited config.
printf '%s\n' '# user-edit' >> "$HOME/.config/dictate/config.toml"
"$ROOT/install.sh" --with-sounds
if ! rg -q '# user-edit' "$HOME/.config/dictate/config.toml"; then
  echo "Expected user config edit to be preserved without --force" >&2
  exit 1
fi

# Force install should refresh config and create backup.
"$ROOT/install.sh" --force --with-sounds
if rg -q '# user-edit' "$HOME/.config/dictate/config.toml"; then
  echo "Expected --force to refresh config.toml" >&2
  exit 1
fi

# Force install should not overwrite existing custom sounds unless explicitly requested.
printf '%s\n' 'custom-start-sound' > "$HOME/.local/share/sounds/dictate/start.wav"
"$ROOT/install.sh" --force --with-sounds
if ! rg -q 'custom-start-sound' "$HOME/.local/share/sounds/dictate/start.wav"; then
  echo "Expected existing sounds to be preserved without --replace-sounds" >&2
  exit 1
fi

"$ROOT/install.sh" --force --with-sounds --replace-sounds
if rg -q 'custom-start-sound' "$HOME/.local/share/sounds/dictate/start.wav"; then
  echo "Expected --replace-sounds to refresh sound files" >&2
  exit 1
fi

shopt -s nullglob
backups=("$HOME/.config/dictate/config.toml.bak."*)
if (( ${#backups[@]} == 0 )); then
  echo "Expected backup file after --force install" >&2
  exit 1
fi

echo "Install smoke tests passed."
