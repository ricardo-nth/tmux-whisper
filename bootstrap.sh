#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: curl -fsSL <bootstrap-url> | bash

Environment:
  DICTATE_BOOTSTRAP_REPO         GitHub repo slug (default: ricardo-nth/dictate-cli)
  DICTATE_BOOTSTRAP_REF          Git ref/branch/tag (default: main)
  DICTATE_BOOTSTRAP_ARCHIVE_URL  Optional override archive URL (advanced/testing)

Any arguments after `bash -s --` are forwarded to install.sh.
Examples:
  curl -fsSL https://raw.githubusercontent.com/ricardo-nth/dictate-cli/main/bootstrap.sh | bash
  curl -fsSL https://raw.githubusercontent.com/ricardo-nth/dictate-cli/main/bootstrap.sh | bash -s -- --force
  curl -fsSL https://raw.githubusercontent.com/ricardo-nth/dictate-cli/v0.4.1/bootstrap.sh | bash -s -- --no-sounds
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

for cmd in bash curl tar mktemp; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "bootstrap error: missing required command: $cmd" >&2
    exit 1
  fi
done

REPO="${DICTATE_BOOTSTRAP_REPO:-ricardo-nth/dictate-cli}"
REF="${DICTATE_BOOTSTRAP_REF:-main}"
ARCHIVE_URL="${DICTATE_BOOTSTRAP_ARCHIVE_URL:-https://codeload.github.com/${REPO}/tar.gz/${REF}}"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/dictate-cli-bootstrap.XXXXXX")"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

ARCHIVE_PATH="$TMP_DIR/repo.tar.gz"

curl -fsSL "$ARCHIVE_URL" -o "$ARCHIVE_PATH"
tar -xzf "$ARCHIVE_PATH" -C "$TMP_DIR"

SRC_DIR="$(find "$TMP_DIR" -mindepth 1 -maxdepth 1 -type d -name 'dictate-cli-*' | head -n1)"
if [[ -z "$SRC_DIR" || ! -x "$SRC_DIR/install.sh" ]]; then
  echo "bootstrap error: could not find extracted install.sh" >&2
  exit 1
fi

bash "$SRC_DIR/install.sh" "$@"
