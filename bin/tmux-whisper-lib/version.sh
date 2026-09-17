#!/usr/bin/env bash

# Version information is a small, stable CLI support surface. Keep the
# currently executing binary separate from install receipt provenance: a
# receipt says how an install was created, not which source checkout is live.

version_running_binary_path() {
  local invoked="${TMUX_WHISPER_RUNNING_BINARY:-$0}"
  local resolved=""

  if [[ "$invoked" == */* ]]; then
    resolved="$invoked"
  else
    resolved="$(command -v "$invoked" 2>/dev/null || true)"
  fi
  [[ -n "$resolved" ]] || resolved="$invoked"

  local parent base
  parent="$(dirname "$resolved")"
  base="$(basename "$resolved")"
  if [[ -d "$parent" ]]; then
    printf '%s/%s\n' "$(cd "$parent" && pwd -P)" "$base"
  else
    printf '%s\n' "$resolved"
  fi
}

version_receipt_value() {
  local key="${1:-}"
  local receipt="${2:-$DICTATE_CONFIG_DIR/install-receipt.env}"
  [[ -n "$key" && -r "$receipt" ]] || return 0

  # Install receipts are generated as shell-style key/value pairs. Read only
  # the expected key as data; never source a user-local receipt for a version
  # query. These provenance values contain no path expansion requirement.
  awk -v expected="$key" '
    index($0, expected "=") == 1 {
      print substr($0, length(expected) + 2)
      exit
    }
  ' "$receipt" 2>/dev/null || true
}

show_version() {
  local json_output="0"
  case "${1:-}" in
    "") ;;
    --json) json_output="1" ;;
    *) die "usage: tmux-whisper version [--json]" ;;
  esac
  [[ $# -le 1 ]] || die "usage: tmux-whisper version [--json]"

  local binary_path receipt_path receipt_present receipt_readable
  local installed_at source ref commit
  binary_path="$(version_running_binary_path)"
  receipt_path="$DICTATE_CONFIG_DIR/install-receipt.env"
  receipt_present="false"
  receipt_readable="false"
  if [[ -f "$receipt_path" ]]; then
    receipt_present="true"
  fi
  if [[ -r "$receipt_path" ]]; then
    receipt_readable="true"
  fi
  installed_at="$(version_receipt_value installed_at "$receipt_path")"
  source="$(version_receipt_value install_source "$receipt_path")"
  ref="$(version_receipt_value repo_git_ref "$receipt_path")"
  commit="$(version_receipt_value repo_git_commit "$receipt_path")"

  if [[ "$json_output" == "1" ]]; then
    need python3
    VERSION_CLI_VERSION="$TMUX_WHISPER_CLI_VERSION" \
    VERSION_CONFIG_SCHEMA_VERSION="$DICTATE_CONFIG_SCHEMA_VERSION" \
    VERSION_RUNNING_BINARY="$binary_path" \
    VERSION_RECEIPT_PATH="$receipt_path" \
    VERSION_RECEIPT_PRESENT="$receipt_present" \
    VERSION_RECEIPT_READABLE="$receipt_readable" \
    VERSION_RECEIPT_INSTALLED_AT="$installed_at" \
    VERSION_RECEIPT_SOURCE="$source" \
    VERSION_RECEIPT_REF="$ref" \
    VERSION_RECEIPT_COMMIT="$commit" \
    python3 - <<'PYEOF'
import json
import os

def optional(name):
    value = os.environ.get(name, "")
    return value if value else None

payload = {
    "command": "version",
    "schema_version": 1,
    "cli_version": os.environ["VERSION_CLI_VERSION"],
    "config_schema_version": int(os.environ["VERSION_CONFIG_SCHEMA_VERSION"]),
    "running_binary": {"path": os.environ["VERSION_RUNNING_BINARY"]},
    "receipt": {
        "path": os.environ["VERSION_RECEIPT_PATH"],
        "present": os.environ["VERSION_RECEIPT_PRESENT"] == "true",
        "readable": os.environ["VERSION_RECEIPT_READABLE"] == "true",
        "installed_at": optional("VERSION_RECEIPT_INSTALLED_AT"),
        "source": optional("VERSION_RECEIPT_SOURCE"),
        "ref": optional("VERSION_RECEIPT_REF"),
        "commit": optional("VERSION_RECEIPT_COMMIT"),
    },
}
print(json.dumps(payload, sort_keys=True))
PYEOF
    return 0
  fi

  echo "Tmux Whisper version"
  echo "CLI version: $TMUX_WHISPER_CLI_VERSION"
  echo "Config schema: v$DICTATE_CONFIG_SCHEMA_VERSION"
  echo "Running binary: $binary_path"
  if [[ "$receipt_present" != "true" ]]; then
    echo "Install receipt: missing ($receipt_path)"
    echo "Receipt provenance is unavailable until an install writes this file."
    return 0
  fi

  if [[ "$receipt_readable" != "true" ]]; then
    echo "Install receipt: present but unreadable ($receipt_path)"
    return 0
  fi

  echo "Install receipt: present ($receipt_path)"
  [[ -n "$installed_at" ]] && echo "  installed at: $installed_at"
  [[ -n "$source" ]] && echo "  source: $source"
  [[ -n "$ref" ]] && echo "  ref: $ref"
  [[ -n "$commit" ]] && echo "  commit: $commit"
  echo "Receipt provenance records install metadata; the running binary is listed separately."
}
