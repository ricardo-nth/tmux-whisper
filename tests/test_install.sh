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

# Force install should preserve user-edited config and local mode customizations.
printf '%s\n' "my custom code prompt" > "$HOME/.config/dictate/modes/code/prompt"
rm -rf "$HOME/.config/dictate/modes/email"
"$ROOT/install.sh" --force --with-sounds
if ! rg -q '# user-edit' "$HOME/.config/dictate/config.toml"; then
  echo "Expected --force to preserve config.toml" >&2
  exit 1
fi
if ! rg -q 'my custom code prompt' "$HOME/.config/dictate/modes/code/prompt"; then
  echo "Expected --force to preserve local mode prompt" >&2
  exit 1
fi
if [[ -e "$HOME/.config/dictate/modes/email" ]]; then
  echo "Expected --force to preserve local mode set (email should stay removed)" >&2
  exit 1
fi

# Legacy local mode folder should migrate from short -> code without clobbering contents.
mv "$HOME/.config/dictate/modes/code" "$HOME/.config/dictate/modes/short"
printf '%s\n' "short" > "$HOME/.config/dictate/current-mode"
printf '%s\n' "legacy code prompt" > "$HOME/.config/dictate/modes/short/prompt"
tmp_cfg="$(mktemp)"
awk '
  BEGIN { in_tmux=0 }
  /^\[/ { in_tmux = ($0 ~ /^\[tmux\][[:space:]]*$/) }
  {
    line = $0
    if (in_tmux && line ~ /^[[:space:]]*mode[[:space:]]*=/) {
      sub(/"code"/, "\"short\"", line)
    }
    print line
  }
' "$HOME/.config/dictate/config.toml" > "$tmp_cfg"
mv "$tmp_cfg" "$HOME/.config/dictate/config.toml"
"$ROOT/install.sh" --force --with-sounds
if [[ -d "$HOME/.config/dictate/modes/short" ]]; then
  echo "Expected legacy short mode folder to be migrated to code" >&2
  exit 1
fi
if [[ ! -f "$HOME/.config/dictate/modes/code/prompt" ]]; then
  echo "Expected code mode folder after migration" >&2
  exit 1
fi
if ! rg -q 'legacy code prompt' "$HOME/.config/dictate/modes/code/prompt"; then
  echo "Expected migrated code mode prompt to preserve local content" >&2
  exit 1
fi
if [[ "$(tr -d '[:space:]' < "$HOME/.config/dictate/current-mode")" != "code" ]]; then
  echo "Expected current-mode short to migrate to code" >&2
  exit 1
fi
if ! rg -q '^[[:space:]]*mode = "code"$' "$HOME/.config/dictate/config.toml"; then
  echo "Expected [tmux] mode short to migrate to code" >&2
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

echo "Install smoke tests passed."
