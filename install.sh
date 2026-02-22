#!/usr/bin/env bash
set -euo pipefail

FORCE=0
INSTALL_SOUNDS="${DICTATE_INSTALL_SAMPLE_SOUNDS:-1}"
REPLACE_SOUNDS="${DICTATE_REPLACE_SOUNDS:-0}"

usage() {
  cat <<'EOF'
Usage: ./install.sh [--force] [--with-sounds|--no-sounds] [--replace-sounds]

Options:
  --force        reinstall binaries/integrations (preserves existing config and modes)
  --with-sounds  install bundled sample sounds into ~/.local/share/sounds/dictate
  --no-sounds    skip sample sound installation
  --replace-sounds  overwrite existing sound files with bundled samples
  -h, --help     show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force)
      FORCE=1
      ;;
    --with-sounds)
      INSTALL_SOUNDS=1
      ;;
    --no-sounds)
      INSTALL_SOUNDS=0
      ;;
    --replace-sounds)
      REPLACE_SOUNDS=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${DICTATE_BIN_DIR:-$HOME/.local/bin}"
CONFIG_DIR="${DICTATE_CONFIG_DIR:-$HOME/.config/dictate}"
SWIFTBAR_DIR="${DICTATE_SWIFTBAR_DIR:-$HOME/.config/swiftbar/plugins}"
INSTALL_SWIFTBAR="${DICTATE_INSTALL_SWIFTBAR:-1}"
SOUND_DIR="${DICTATE_SOUNDS_DIR:-$HOME/.local/share/sounds/dictate}"

copy_if_missing() {
  local src="$1"
  local dst="$2"
  [[ -e "$dst" ]] || cp -R "$src" "$dst"
}

migrate_mode_short_to_code() {
  local modes_dir="$CONFIG_DIR/modes"
  if [[ -d "$modes_dir/short" && ! -e "$modes_dir/code" ]]; then
    mv "$modes_dir/short" "$modes_dir/code"
  fi
  if [[ -f "$CONFIG_DIR/current-mode" ]]; then
    local current_mode
    current_mode="$(tr -d '[:space:]' < "$CONFIG_DIR/current-mode" 2>/dev/null || true)"
    if [[ "$current_mode" == "short" ]]; then
      printf '%s\n' "code" > "$CONFIG_DIR/current-mode"
    fi
  fi
  if [[ -f "$CONFIG_DIR/config.toml" ]]; then
    local tmp_cfg
    tmp_cfg="$(mktemp)"
    awk '
      BEGIN { in_tmux=0 }
      /^\[/ {
        in_tmux = ($0 ~ /^\[tmux\][[:space:]]*$/)
      }
      {
        line = $0
        if (in_tmux && line ~ /^[[:space:]]*mode[[:space:]]*=/) {
          sub(/"short"/, "\"code\"", line)
        }
        print line
      }
    ' "$CONFIG_DIR/config.toml" > "$tmp_cfg"
    mv "$tmp_cfg" "$CONFIG_DIR/config.toml"
  fi
}

install_default_config_files() {
  copy_if_missing "$REPO_ROOT/config/config.toml" "$CONFIG_DIR/config.toml"
  copy_if_missing "$REPO_ROOT/config/vocab" "$CONFIG_DIR/vocab"
  copy_if_missing "$REPO_ROOT/config/current-mode" "$CONFIG_DIR/current-mode"
}

install_default_modes_preserving_local() {
  local modes_preexisting="0"
  [[ -d "$CONFIG_DIR/modes" ]] && modes_preexisting="1"
  mkdir -p "$CONFIG_DIR/modes"
  migrate_mode_short_to_code
  if [[ "$modes_preexisting" == "0" ]]; then
    cp -R "$REPO_ROOT/config/modes/." "$CONFIG_DIR/modes/"
    return 0
  fi
  # Existing installs keep local mode set; only ensure the core code mode exists.
  copy_if_missing "$REPO_ROOT/config/modes/code" "$CONFIG_DIR/modes/code"
}

mkdir -p "$BIN_DIR" "$CONFIG_DIR" "$CONFIG_DIR/integrations/raycast"

install -m 0755 "$REPO_ROOT/bin/tmux-whisper" "$BIN_DIR/tmux-whisper"
install -m 0755 "$REPO_ROOT/bin/dictate-lib.sh" "$BIN_DIR/dictate-lib.sh"

# Preserve user config and local mode edits on every install, including --force.
# `--force` remains a convenience for reinstalling binaries/integrations.
install_default_config_files
install_default_modes_preserving_local

install -m 0755 "$REPO_ROOT/integrations/raycast/tmux-whisper-inline.sh" "$CONFIG_DIR/integrations/raycast/tmux-whisper-inline.sh"
install -m 0755 "$REPO_ROOT/integrations/raycast/tmux-whisper-toggle.sh" "$CONFIG_DIR/integrations/raycast/tmux-whisper-toggle.sh"
install -m 0755 "$REPO_ROOT/integrations/raycast/tmux-whisper-cancel.sh" "$CONFIG_DIR/integrations/raycast/tmux-whisper-cancel.sh"

if [[ "$INSTALL_SWIFTBAR" == "1" ]]; then
  mkdir -p "$SWIFTBAR_DIR"
  install -m 0755 "$REPO_ROOT/integrations/tmux-whisper-status.0.2s.sh" "$SWIFTBAR_DIR/tmux-whisper-status.0.2s.sh"
fi

if [[ "$INSTALL_SOUNDS" == "1" && -d "$REPO_ROOT/assets/sounds/dictate" ]]; then
  mkdir -p "$SOUND_DIR"
  for wav in "$REPO_ROOT"/assets/sounds/dictate/*.wav; do
    [[ -f "$wav" ]] || continue
    target="$SOUND_DIR/$(basename "$wav")"
    if [[ "$REPLACE_SOUNDS" -eq 1 || ! -f "$target" ]]; then
      install -m 0644 "$wav" "$target"
    fi
  done
fi

echo "Installed tmux-whisper to: $BIN_DIR/tmux-whisper"
echo "Config path: $CONFIG_DIR"
if [[ "$INSTALL_SWIFTBAR" == "1" ]]; then
  echo "SwiftBar plugin: $SWIFTBAR_DIR/tmux-whisper-status.0.2s.sh"
else
  echo "SwiftBar plugin: skipped (DICTATE_INSTALL_SWIFTBAR=0)"
fi
if [[ "$INSTALL_SOUNDS" == "1" ]]; then
  echo "Sample sounds: $SOUND_DIR"
else
  echo "Sample sounds: skipped"
fi
echo "Run: tmux-whisper debug"
