#!/usr/bin/env bash
set -euo pipefail

FORCE=0
if [[ "${1:-}" == "--force" ]]; then
  FORCE=1
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${DICTATE_BIN_DIR:-$HOME/.local/bin}"
CONFIG_DIR="${DICTATE_CONFIG_DIR:-$HOME/.config/dictate}"
SWIFTBAR_DIR="${DICTATE_SWIFTBAR_DIR:-$HOME/.config/swiftbar/plugins}"
INSTALL_SWIFTBAR="${DICTATE_INSTALL_SWIFTBAR:-1}"
STAMP="$(date +%Y%m%d-%H%M%S)"

backup_if_exists() {
  local target="$1"
  if [[ -e "$target" ]]; then
    cp -R "$target" "${target}.bak.${STAMP}"
  fi
}

mkdir -p "$BIN_DIR" "$CONFIG_DIR" "$CONFIG_DIR/integrations/raycast"

install -m 0755 "$REPO_ROOT/bin/dictate" "$BIN_DIR/dictate"
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

install -m 0755 "$REPO_ROOT/integrations/raycast/dictate-inline.sh" "$CONFIG_DIR/integrations/raycast/dictate-inline.sh"
install -m 0755 "$REPO_ROOT/integrations/raycast/dictate-toggle.sh" "$CONFIG_DIR/integrations/raycast/dictate-toggle.sh"
install -m 0755 "$REPO_ROOT/integrations/raycast/dictate-cancel.sh" "$CONFIG_DIR/integrations/raycast/dictate-cancel.sh"

if [[ "$INSTALL_SWIFTBAR" == "1" ]]; then
  mkdir -p "$SWIFTBAR_DIR"
  install -m 0755 "$REPO_ROOT/integrations/dictate-status.0.2s.sh" "$SWIFTBAR_DIR/dictate-status.0.2s.sh"
fi

echo "Installed dictate to: $BIN_DIR/dictate"
echo "Config path: $CONFIG_DIR"
echo "Run: dictate debug"
