#!/usr/bin/env bash
set -euo pipefail

FORCE=0
INSTALL_SOUNDS="${DICTATE_INSTALL_SAMPLE_SOUNDS:-1}"
REPLACE_SOUNDS="${DICTATE_REPLACE_SOUNDS:-0}"

usage() {
  cat <<'EOF'
Usage: ./install.sh [--force] [--with-sounds|--no-sounds] [--replace-sounds]

Options:
  --force        overwrite config defaults (backing up current files first)
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
STAMP="$(date +%Y%m%d-%H%M%S)"

backup_if_exists() {
  local target="$1"
  if [[ -e "$target" ]]; then
    cp -R "$target" "${target}.bak.${STAMP}"
  fi
}

mkdir -p "$BIN_DIR" "$CONFIG_DIR" "$CONFIG_DIR/integrations/raycast"

install -m 0755 "$REPO_ROOT/bin/tmux-whisper" "$BIN_DIR/tmux-whisper"
install -m 0755 "$REPO_ROOT/bin/dictate-lib.sh" "$BIN_DIR/dictate-lib.sh"

if [[ "$FORCE" -eq 1 ]]; then
  backup_if_exists "$CONFIG_DIR/config.toml"
  backup_if_exists "$CONFIG_DIR/vocab"
  backup_if_exists "$CONFIG_DIR/current-mode"
  backup_if_exists "$CONFIG_DIR/modes"
  cp "$REPO_ROOT/config/config.toml" "$CONFIG_DIR/config.toml"
  cp "$REPO_ROOT/config/vocab" "$CONFIG_DIR/vocab"
  cp "$REPO_ROOT/config/current-mode" "$CONFIG_DIR/current-mode"
  rm -rf "$CONFIG_DIR/modes"
  cp -R "$REPO_ROOT/config/modes" "$CONFIG_DIR/modes"
else
  [[ -f "$CONFIG_DIR/config.toml" ]] || cp "$REPO_ROOT/config/config.toml" "$CONFIG_DIR/config.toml"
  [[ -f "$CONFIG_DIR/vocab" ]] || cp "$REPO_ROOT/config/vocab" "$CONFIG_DIR/vocab"
  [[ -f "$CONFIG_DIR/current-mode" ]] || cp "$REPO_ROOT/config/current-mode" "$CONFIG_DIR/current-mode"
  if [[ ! -d "$CONFIG_DIR/modes" ]]; then
    cp -R "$REPO_ROOT/config/modes" "$CONFIG_DIR/modes"
  fi
fi

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
