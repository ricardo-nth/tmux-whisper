#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: curl -fsSL <bootstrap-url> | bash
       curl -fsSL <bootstrap-url> | bash -s -- [bootstrap options] [install options]

Installs Tmux Whisper from a GitHub source archive.

Environment:
  DICTATE_BOOTSTRAP_REPO         GitHub repo slug (default: ricardo-nth/tmux-whisper)
  DICTATE_BOOTSTRAP_REF          Git ref/branch/tag (default: main)
  DICTATE_BOOTSTRAP_ARCHIVE_URL  Optional override archive URL (advanced/testing)

Bootstrap options:
  --repo OWNER/REPO       source repository (default: ricardo-nth/tmux-whisper)
  --ref REF               source branch/tag/commit-ish (default: main)
  --archive-url URL       exact source archive URL (advanced/testing)
  -h, --help              show this help

Any arguments after `bash -s --` are forwarded to install.sh.
Examples:
  curl -fsSL https://raw.githubusercontent.com/ricardo-nth/tmux-whisper/main/bootstrap.sh | bash
  curl -fsSL https://raw.githubusercontent.com/ricardo-nth/tmux-whisper/main/bootstrap.sh | bash -s -- --force
  curl -fsSL https://raw.githubusercontent.com/ricardo-nth/tmux-whisper/main/bootstrap.sh | bash -s -- --ref v0.6.0 --force
  curl -fsSL https://raw.githubusercontent.com/ricardo-nth/tmux-whisper/v0.6.0/bootstrap.sh | bash -s -- --no-sounds
USAGE
}

REPO="${DICTATE_BOOTSTRAP_REPO:-ricardo-nth/tmux-whisper}"
REF="${DICTATE_BOOTSTRAP_REF:-main}"
ARCHIVE_URL="${DICTATE_BOOTSTRAP_ARCHIVE_URL:-}"
INSTALL_ARGS=()

while [[ $# -gt 0 ]]; do
  case "${1:-}" in
    -h|--help)
      usage
      exit 0
      ;;
    --repo)
      shift
      [[ $# -gt 0 && -n "${1:-}" ]] || {
        echo "bootstrap error: --repo requires OWNER/REPO" >&2
        exit 1
      }
      REPO="${1:-}"
      ;;
    --repo=*)
      REPO="${1#*=}"
      ;;
    --ref)
      shift
      [[ $# -gt 0 && -n "${1:-}" ]] || {
        echo "bootstrap error: --ref requires a branch, tag, or commit-ish" >&2
        exit 1
      }
      REF="${1:-}"
      ;;
    --ref=*)
      REF="${1#*=}"
      ;;
    --archive-url)
      shift
      [[ $# -gt 0 && -n "${1:-}" ]] || {
        echo "bootstrap error: --archive-url requires a URL" >&2
        exit 1
      }
      ARCHIVE_URL="${1:-}"
      ;;
    --archive-url=*)
      ARCHIVE_URL="${1#*=}"
      ;;
    --)
      shift
      while [[ $# -gt 0 ]]; do
        INSTALL_ARGS+=("$1")
        shift
      done
      break
      ;;
    *)
      INSTALL_ARGS+=("$1")
      ;;
  esac
  shift
done

for cmd in bash curl tar mktemp; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "bootstrap error: missing required command: $cmd" >&2
    exit 1
  fi
done

ARCHIVE_URL="${ARCHIVE_URL:-https://codeload.github.com/${REPO}/tar.gz/${REF}}"

echo "Bootstrap source: ${REPO}@${REF}"
echo "Bootstrap archive: ${ARCHIVE_URL}"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tmux-whisper-bootstrap.XXXXXX")"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

ARCHIVE_PATH="$TMP_DIR/repo.tar.gz"

curl -fsSL "$ARCHIVE_URL" -o "$ARCHIVE_PATH"
tar -xzf "$ARCHIVE_PATH" -C "$TMP_DIR"

SRC_DIR="$(find "$TMP_DIR" -mindepth 1 -maxdepth 1 -type d -name 'tmux-whisper-*' | head -n1)"
if [[ -z "$SRC_DIR" || ! -x "$SRC_DIR/install.sh" ]]; then
  echo "bootstrap error: could not find extracted install.sh" >&2
  exit 1
fi

DICTATE_INSTALL_SOURCE="bootstrap:${REPO}@${REF}" \
DICTATE_INSTALL_ARCHIVE_URL="$ARCHIVE_URL" \
  bash "$SRC_DIR/install.sh" ${INSTALL_ARGS[@]+"${INSTALL_ARGS[@]}"}
