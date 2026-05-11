#!/usr/bin/env bash

# Audio helpers own source-aware device resolution, cache lifecycle, and the
# diagnostic breadcrumbs used by startup, debug, bench, and flow parity tests.

load_audio_index_cache() {
  [[ -f "$AUDIO_INDEX_CACHE" ]] || return 1
  # shellcheck disable=SC1090
  source "$AUDIO_INDEX_CACHE" 2>/dev/null || return 1
  if [[ -z "${CACHED_AUDIO_KEY:-}" && -n "${CACHED_AUDIO_NAME:-}" ]]; then
    CACHED_AUDIO_KEY="$CACHED_AUDIO_NAME"
  fi
  [[ -n "${CACHED_AUDIO_KEY:-}" && -n "${CACHED_AUDIO_INDEX:-}" ]] || return 1
  return 0
}

write_audio_index_cache() {
  local key="${1:-}"
  local idx="${2:-}"
  local name="${3:-}"
  local match="${4:-}"
  [[ -n "$key" && -n "$idx" ]] || return 0

  mkdir -p "$AUDIO_CACHE_DIR" 2>/dev/null || return 0
  local tmp
  tmp="$(mktemp "$AUDIO_CACHE_DIR/.audio-index.XXXXXX" 2>/dev/null || true)"
  [[ -n "$tmp" ]] || return 0

  umask 077
  printf 'CACHED_AUDIO_KEY=%q\nCACHED_AUDIO_NAME=%q\nCACHED_AUDIO_MATCH=%q\nCACHED_AUDIO_INDEX=%q\nCACHED_AUDIO_AT=%q\n' \
    "$key" "$name" "$match" "$idx" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" >"$tmp" 2>/dev/null || {
    rm -f "$tmp" 2>/dev/null || true
    return 0
  }
  mv -f "$tmp" "$AUDIO_INDEX_CACHE" 2>/dev/null || true
}

audio_index_cache_file_is_fresh() {
  local max_age_ms="${DICTATE_AUDIO_CACHE_FAST_MAX_AGE_MS:-21600000}"
  [[ "$max_age_ms" =~ ^[0-9]+$ ]] || max_age_ms=21600000
  (( max_age_ms > 0 )) || return 1
  [[ -f "$AUDIO_INDEX_CACHE" ]] || return 1

  local mtime now max_age_s age_s
  mtime="$(stat -f '%m' "$AUDIO_INDEX_CACHE" 2>/dev/null || stat -c '%Y' "$AUDIO_INDEX_CACHE" 2>/dev/null || true)"
  [[ "$mtime" =~ ^[0-9]+$ ]] || return 1
  now="$(date +%s)"
  [[ "$now" =~ ^[0-9]+$ ]] || return 1

  max_age_s=$(( (max_age_ms + 999) / 1000 ))
  age_s=$(( now - mtime ))
  (( age_s < 0 )) && age_s=0
  (( age_s <= max_age_s ))
}

refresh_audio_index_cache_hit() {
  local key="${1:-}"
  local idx="${2:-}"
  local name="${3:-}"
  local match="${4:-}"
  local async="${5:-0}"
  [[ -n "$key" && -n "$idx" ]] || return 0

  if bool_is_on "$async"; then
    touch "$AUDIO_INDEX_CACHE" 2>/dev/null || true
    (
      trap '' HUP
      write_audio_index_cache "$key" "$idx" "$name" "$match"
    ) >/dev/null 2>&1 &
  else
    write_audio_index_cache "$key" "$idx" "$name" "$match"
  fi
}

clear_audio_index_cache() {
  rm -f "$AUDIO_INDEX_CACHE" 2>/dev/null || true
}

normalize_audio_source() {
  local src="${1:-auto}"
  src="$(printf "%s" "$src" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
  case "$src" in
    auto|name|external|mac|iphone) echo "$src" ;;
    *) echo "auto" ;;
  esac
}

detect_audio_index() {
  need ffmpeg
  need python3

  local source_mode preferred mac_name iphone_name cache_key skip_cache_validate
  source_mode="$(normalize_audio_source "${DICTATE_AUDIO_SOURCE:-${CFG_AUDIO_SOURCE:-auto}}")"
  preferred="${DICTATE_AUDIO_NAME:-${CFG_AUDIO_DEVICE_NAME:-MacBook Air Microphone}}"
  mac_name="${CFG_AUDIO_MAC_NAME:-${CFG_AUDIO_DEVICE_NAME:-MacBook Air Microphone}}"
  iphone_name="${CFG_AUDIO_IPHONE_NAME:-}"
  cache_key="source=${source_mode};preferred=${preferred};mac=${mac_name};iphone=${iphone_name}"
  skip_cache_validate="${DICTATE_AUDIO_CACHE_SKIP_VALIDATE:-0}"

  local started_ms detected_idx="" detected_name="" detected_match="" detect_meta=""
  started_ms="$(now_ms)"
  DICTATE_LAST_AUDIO_INDEX_SOURCE=""
  DICTATE_LAST_AUDIO_INDEX_MS="0"
  DICTATE_LAST_AUDIO_INDEX=""
  DICTATE_LAST_AUDIO_CACHE_NOTE=""

  local allow_cache="0"
  case "$source_mode" in
    name|mac) allow_cache="1" ;;
  esac

  cached_audio_entry_is_valid() {
    local idx="${1:-}"
    local name="${2:-}"
    [[ -n "$idx" && -n "$name" ]] || return 1

    local out
    out="$(ffmpeg -hide_banner -f avfoundation -list_devices true -i "" 2>&1 || true)"

    python3 -c '
import re, sys

idx = sys.argv[1] if len(sys.argv) > 1 else ""
name = sys.argv[2] if len(sys.argv) > 2 else ""
lines = sys.argv[3].splitlines() if len(sys.argv) > 3 else []

section = ""
for line in lines:
    if "AVFoundation audio devices:" in line:
        section = "audio"
        continue
    if "AVFoundation video devices:" in line:
        section = "video"
        continue
    if section != "audio":
        continue
    m = re.search(r"\[(\d+)\]\s+(.*)$", line)
    if not m:
        continue
    if m.group(1) == idx and m.group(2).strip() == name.strip():
        sys.exit(0)

sys.exit(1)
' "$idx" "$name" "$out"
  }

  audio_cache_entry_is_fresh() {
    local cached_at="${1:-}"
    local max_age_ms="${DICTATE_AUDIO_CACHE_FAST_MAX_AGE_MS:-21600000}"
    [[ -n "$cached_at" ]] || return 1
    [[ "$max_age_ms" =~ ^[0-9]+$ ]] || max_age_ms=21600000
    (( max_age_ms > 0 )) || return 1

    python3 - "$cached_at" "$max_age_ms" <<'PYEOF'
from datetime import datetime, timezone
import sys

cached_at = (sys.argv[1] if len(sys.argv) > 1 else "").strip()
max_age_ms = int(sys.argv[2]) if len(sys.argv) > 2 else 21600000

if not cached_at:
    raise SystemExit(1)

try:
    parsed = datetime.fromisoformat(cached_at.replace("Z", "+00:00"))
except Exception:
    raise SystemExit(1)

if parsed.tzinfo is None:
    parsed = parsed.replace(tzinfo=timezone.utc)

age_ms = int((datetime.now(timezone.utc) - parsed).total_seconds() * 1000)
if age_ms < 0:
    age_ms = 0

raise SystemExit(0 if age_ms <= max_age_ms else 1)
PYEOF
  }

  if [[ "$allow_cache" == "1" ]] && load_audio_index_cache && [[ "${CACHED_AUDIO_KEY:-}" == "$cache_key" ]]; then
    local cached_idx cached_name cached_match cached_at
    cached_idx="${CACHED_AUDIO_INDEX:-}"
    cached_name="${CACHED_AUDIO_NAME:-}"
    cached_match="${CACHED_AUDIO_MATCH:-cache}"
    cached_at="${CACHED_AUDIO_AT:-unknown}"
    detected_idx="${CACHED_AUDIO_INDEX:-}"
    detected_name="${CACHED_AUDIO_NAME:-}"
    detected_match="${cached_match:-cache}"
    local allow_fast_cache="0"
    if bool_is_on "$skip_cache_validate" && audio_index_cache_file_is_fresh; then
      allow_fast_cache="1"
    fi
    if [[ -n "$detected_idx" ]] && ( [[ "$allow_fast_cache" == "1" ]] || cached_audio_entry_is_valid "$detected_idx" "$detected_name" ); then
      DICTATE_LAST_AUDIO_INDEX_SOURCE="cache:source(${source_mode}):match(${detected_match:-cache}):name(${detected_name:-})"
      DICTATE_LAST_AUDIO_INDEX_MS="$(( $(now_ms) - started_ms ))"
      DICTATE_LAST_AUDIO_INDEX="$detected_idx"
      # Keep the cache age sliding forward on successful hits so the fast path
      # stays warm during normal use instead of aging into repeated revalidation.
      refresh_audio_index_cache_hit "$cache_key" "$detected_idx" "$detected_name" "$detected_match" "$allow_fast_cache"
      printf '%s\t%s\t%s\t%s\n' "$detected_idx" "$DICTATE_LAST_AUDIO_INDEX_SOURCE" "$DICTATE_LAST_AUDIO_INDEX_MS" "${DICTATE_LAST_AUDIO_CACHE_NOTE:-}"
      return 0
    fi
    DICTATE_LAST_AUDIO_CACHE_NOTE="stale cache invalidated: cached idx=${cached_idx:-unknown} name=${cached_name:-unknown} match=${cached_match:-unknown} at=${cached_at}"
    clear_audio_index_cache
  fi

  detect_meta="$(dictate_lib_detect_audio_device "$source_mode" "$preferred" "$mac_name" "$iphone_name" 2>/dev/null || true)"
  IFS=$'\t' read -r detected_idx detected_name detected_match <<<"$detect_meta"
  DICTATE_LAST_AUDIO_INDEX_MS="$(( $(now_ms) - started_ms ))"
  if [[ -n "$detected_idx" ]]; then
    DICTATE_LAST_AUDIO_INDEX_SOURCE="detect:source(${source_mode}):match(${detected_match:-unknown}):name(${detected_name:-})"
    DICTATE_LAST_AUDIO_INDEX="$detected_idx"
    if [[ -n "${DICTATE_LAST_AUDIO_CACHE_NOTE:-}" ]]; then
      DICTATE_LAST_AUDIO_CACHE_NOTE="${DICTATE_LAST_AUDIO_CACHE_NOTE}; re-resolved idx=${detected_idx} match=${detected_match:-unknown} name=${detected_name:-unknown}"
    fi
    if [[ "$allow_cache" == "1" ]]; then
      write_audio_index_cache "$cache_key" "$detected_idx" "$detected_name" "$detected_match"
    fi
    printf '%s\t%s\t%s\t%s\n' "$detected_idx" "$DICTATE_LAST_AUDIO_INDEX_SOURCE" "$DICTATE_LAST_AUDIO_INDEX_MS" "${DICTATE_LAST_AUDIO_CACHE_NOTE:-}"
    return 0
  fi

  DICTATE_LAST_AUDIO_INDEX_SOURCE="detect:miss:source(${source_mode})"
  if [[ -n "${DICTATE_LAST_AUDIO_CACHE_NOTE:-}" ]]; then
    DICTATE_LAST_AUDIO_CACHE_NOTE="${DICTATE_LAST_AUDIO_CACHE_NOTE}; no replacement found"
  fi
  printf '\t%s\t%s\t%s\n' "$DICTATE_LAST_AUDIO_INDEX_SOURCE" "$DICTATE_LAST_AUDIO_INDEX_MS" "${DICTATE_LAST_AUDIO_CACHE_NOTE:-}"
  return 1
}

detect_audio_name_by_index() {
  need ffmpeg
  need python3
  local idx="${1:-}"
  [[ -n "$idx" ]] || return 1

  local out
  out="$(ffmpeg -hide_banner -f avfoundation -list_devices true -i "" 2>&1 || true)"

  python3 -c '
import re, sys

target = sys.argv[1] if len(sys.argv) > 1 else ""
lines = sys.argv[2].splitlines() if len(sys.argv) > 2 else []
section = ""
for line in lines:
    if "AVFoundation audio devices:" in line:
        section = "audio"
        continue
    if "AVFoundation video devices:" in line:
        section = "video"
        continue
    if section != "audio":
        continue
    m = re.search(r"\[(\d+)\]\s+(.*)$", line)
    if not m:
        continue
    if m.group(1) == target:
        print(m.group(2).strip())
        sys.exit(0)
sys.exit(1)
' "$idx" "$out"
}
