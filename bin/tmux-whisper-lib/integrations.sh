#!/usr/bin/env bash

# Integration helpers report the installed adapter surface in one place so
# Raycast, SwiftBar, and install receipt drift can be inspected without hunting.

integration_path_exists_label() {
  [[ -e "${1:-}" ]] && printf '%s\n' "present" || printf '%s\n' "missing"
}

integration_path_executable_label() {
  local path="${1:-}"
  if [[ ! -e "$path" ]]; then
    printf '%s\n' "missing"
  elif [[ -x "$path" ]]; then
    printf '%s\n' "executable"
  else
    printf '%s\n' "not executable"
  fi
}

integration_receipt_value() {
  local key="${1:-}"
  local receipt="${2:-$DICTATE_CONFIG_DIR/install-receipt.env}"
  [[ -n "$key" && -r "$receipt" ]] || return 0
  (
    set +u
    # shellcheck disable=SC1090
    source "$receipt" 2>/dev/null || exit 0
    case "$key" in
      installed_at) printf '%s\n' "${installed_at:-}" ;;
      install_source) printf '%s\n' "${install_source:-}" ;;
      repo_git_ref) printf '%s\n' "${repo_git_ref:-}" ;;
      repo_git_commit) printf '%s\n' "${repo_git_commit:-}" ;;
      bin_path) printf '%s\n' "${bin_path:-}" ;;
      swiftbar_plugin) printf '%s\n' "${swiftbar_plugin:-}" ;;
      *) ;;
    esac
  )
}

integration_current_binary_path() {
  local found=""
  found="$(command -v tmux-whisper 2>/dev/null || true)"
  if [[ -n "$found" ]]; then
    printf '%s\n' "$found"
  elif [[ -x "$SCRIPT_DIR/tmux-whisper" ]]; then
    printf '%s\n' "$SCRIPT_DIR/tmux-whisper"
  else
    printf '%s\n' "$SCRIPT_DIR/tmux-whisper"
  fi
}

integration_swiftbar_plugin_path() {
  local receipt_plugin
  receipt_plugin="$(integration_receipt_value swiftbar_plugin)"
  if [[ -n "$receipt_plugin" && "$receipt_plugin" != "skipped" ]]; then
    printf '%s\n' "$receipt_plugin"
  else
    printf '%s\n' "${DICTATE_SWIFTBAR_PLUGIN_PATH:-$HOME/.config/swiftbar/plugins/tmux-whisper-status.0.2s.sh}"
  fi
}

integrations_status_json() {
  local binary_path="$1"
  local receipt_path="$2"
  local swiftbar_path="$3"
  local raycast_inline="$4"
  local raycast_toggle="$5"
  local raycast_cancel="$6"
  local receipt_installed_at="$7"
  local receipt_source="$8"
  local receipt_ref="$9"
  local receipt_commit="${10}"

  INTEGRATIONS_BINARY_PATH="$binary_path" \
  INTEGRATIONS_BINARY_EXISTS="$([[ -x "$binary_path" ]] && echo true || echo false)" \
  INTEGRATIONS_CONFIG_DIR="$DICTATE_CONFIG_DIR" \
  INTEGRATIONS_RECEIPT_PATH="$receipt_path" \
  INTEGRATIONS_RECEIPT_EXISTS="$([[ -r "$receipt_path" ]] && echo true || echo false)" \
  INTEGRATIONS_RECEIPT_INSTALLED_AT="$receipt_installed_at" \
  INTEGRATIONS_RECEIPT_SOURCE="$receipt_source" \
  INTEGRATIONS_RECEIPT_REF="$receipt_ref" \
  INTEGRATIONS_RECEIPT_COMMIT="$receipt_commit" \
  INTEGRATIONS_SWIFTBAR_ENABLED="$([[ "${CFG_SWIFTBAR_ENABLED:-1}" == "1" ]] && echo true || echo false)" \
  INTEGRATIONS_SWIFTBAR_PATH="$swiftbar_path" \
  INTEGRATIONS_SWIFTBAR_EXISTS="$([[ -f "$swiftbar_path" ]] && echo true || echo false)" \
  INTEGRATIONS_SWIFTBAR_EXECUTABLE="$([[ -x "$swiftbar_path" ]] && echo true || echo false)" \
  INTEGRATIONS_RAYCAST_INLINE="$raycast_inline" \
  INTEGRATIONS_RAYCAST_INLINE_EXISTS="$([[ -f "$raycast_inline" ]] && echo true || echo false)" \
  INTEGRATIONS_RAYCAST_INLINE_EXECUTABLE="$([[ -x "$raycast_inline" ]] && echo true || echo false)" \
  INTEGRATIONS_RAYCAST_TOGGLE="$raycast_toggle" \
  INTEGRATIONS_RAYCAST_TOGGLE_EXISTS="$([[ -f "$raycast_toggle" ]] && echo true || echo false)" \
  INTEGRATIONS_RAYCAST_TOGGLE_EXECUTABLE="$([[ -x "$raycast_toggle" ]] && echo true || echo false)" \
  INTEGRATIONS_RAYCAST_CANCEL="$raycast_cancel" \
  INTEGRATIONS_RAYCAST_CANCEL_EXISTS="$([[ -f "$raycast_cancel" ]] && echo true || echo false)" \
  INTEGRATIONS_RAYCAST_CANCEL_EXECUTABLE="$([[ -x "$raycast_cancel" ]] && echo true || echo false)" \
  python3 - <<'PYEOF'
import json
import os

def b(name):
    return os.environ.get(name) == "true"

payload = {
    "command": "integrations",
    "binary": {
        "path": os.environ.get("INTEGRATIONS_BINARY_PATH", ""),
        "exists": b("INTEGRATIONS_BINARY_EXISTS"),
    },
    "config_dir": os.environ.get("INTEGRATIONS_CONFIG_DIR", ""),
    "receipt": {
        "path": os.environ.get("INTEGRATIONS_RECEIPT_PATH", ""),
        "exists": b("INTEGRATIONS_RECEIPT_EXISTS"),
        "installed_at": os.environ.get("INTEGRATIONS_RECEIPT_INSTALLED_AT", ""),
        "install_source": os.environ.get("INTEGRATIONS_RECEIPT_SOURCE", ""),
        "repo_git_ref": os.environ.get("INTEGRATIONS_RECEIPT_REF", ""),
        "repo_git_commit": os.environ.get("INTEGRATIONS_RECEIPT_COMMIT", ""),
    },
    "swiftbar": {
        "enabled": b("INTEGRATIONS_SWIFTBAR_ENABLED"),
        "plugin": {
            "path": os.environ.get("INTEGRATIONS_SWIFTBAR_PATH", ""),
            "exists": b("INTEGRATIONS_SWIFTBAR_EXISTS"),
            "executable": b("INTEGRATIONS_SWIFTBAR_EXECUTABLE"),
        },
    },
    "raycast": {
        "scripts": [
            {
                "name": "inline",
                "path": os.environ.get("INTEGRATIONS_RAYCAST_INLINE", ""),
                "exists": b("INTEGRATIONS_RAYCAST_INLINE_EXISTS"),
                "executable": b("INTEGRATIONS_RAYCAST_INLINE_EXECUTABLE"),
            },
            {
                "name": "tmux-toggle",
                "path": os.environ.get("INTEGRATIONS_RAYCAST_TOGGLE", ""),
                "exists": b("INTEGRATIONS_RAYCAST_TOGGLE_EXISTS"),
                "executable": b("INTEGRATIONS_RAYCAST_TOGGLE_EXECUTABLE"),
            },
            {
                "name": "cancel",
                "path": os.environ.get("INTEGRATIONS_RAYCAST_CANCEL", ""),
                "exists": b("INTEGRATIONS_RAYCAST_CANCEL_EXISTS"),
                "executable": b("INTEGRATIONS_RAYCAST_CANCEL_EXECUTABLE"),
            },
        ],
    },
    "next": ["run ./install.sh --force to refresh installed adapters"],
}
print(json.dumps(payload, sort_keys=True))
PYEOF
}

manage_integrations() {
  local action="${1:-status}"
  shift 2>/dev/null || true
  local json_output="0"
  case "$action" in
    ""|show|status) ;;
    --json)
      json_output="1"
      action="status"
      ;;
    *)
      die "usage: tmux-whisper integrations [status|--json]"
      ;;
  esac
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json) json_output="1" ;;
      *) die "usage: tmux-whisper integrations [status|--json]" ;;
    esac
    shift
  done

  local binary_path receipt_path swiftbar_path
  local raycast_inline raycast_toggle raycast_cancel
  binary_path="$(integration_current_binary_path)"
  receipt_path="$DICTATE_CONFIG_DIR/install-receipt.env"
  swiftbar_path="$(integration_swiftbar_plugin_path)"
  raycast_inline="$DICTATE_CONFIG_DIR/integrations/raycast/tmux-whisper-inline.sh"
  raycast_toggle="$DICTATE_CONFIG_DIR/integrations/raycast/tmux-whisper-toggle.sh"
  raycast_cancel="$DICTATE_CONFIG_DIR/integrations/raycast/tmux-whisper-cancel.sh"

  local receipt_installed_at receipt_source receipt_ref receipt_commit
  receipt_installed_at="$(integration_receipt_value installed_at "$receipt_path")"
  receipt_source="$(integration_receipt_value install_source "$receipt_path")"
  receipt_ref="$(integration_receipt_value repo_git_ref "$receipt_path")"
  receipt_commit="$(integration_receipt_value repo_git_commit "$receipt_path")"

  if [[ "$json_output" == "1" ]]; then
    integrations_status_json "$binary_path" "$receipt_path" "$swiftbar_path" \
      "$raycast_inline" "$raycast_toggle" "$raycast_cancel" \
      "$receipt_installed_at" "$receipt_source" "$receipt_ref" "$receipt_commit"
    return 0
  fi

  echo "Integrations:"
  echo "  binary: $binary_path ($(integration_path_executable_label "$binary_path"))"
  echo "  config: $DICTATE_CONFIG_DIR"
  echo "  install receipt: $receipt_path ($(integration_path_exists_label "$receipt_path"))"
  if [[ -n "$receipt_installed_at" ]]; then
    echo "  installed_at: $receipt_installed_at"
  fi
  if [[ -n "$receipt_ref" || -n "$receipt_commit" ]]; then
    echo "  installed_ref: ${receipt_ref:-unknown} ${receipt_commit:-}"
  fi
  echo ""
  echo "SwiftBar:"
  echo "  enabled: $([[ "${CFG_SWIFTBAR_ENABLED:-1}" == "1" ]] && echo "ON" || echo "OFF")"
  echo "  plugin: $swiftbar_path ($(integration_path_executable_label "$swiftbar_path"))"
  echo ""
  echo "Raycast:"
  echo "  inline: $raycast_inline ($(integration_path_executable_label "$raycast_inline"))"
  echo "  tmux-toggle: $raycast_toggle ($(integration_path_executable_label "$raycast_toggle"))"
  echo "  cancel: $raycast_cancel ($(integration_path_executable_label "$raycast_cancel"))"
  echo ""
  echo "Next: run ./install.sh --force to refresh installed adapters"
}
