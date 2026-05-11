#!/usr/bin/env bash

# Mode policy owns mode naming, flow eligibility, app detection, and prompt
# assembly. Recording flows and integrations should consume these rules instead
# of mirroring them.

canonical_mode_name() {
  local m="${1:-}"
  case "$m" in
    "") echo "code" ;;
    *) echo "$m" ;;
  esac
}

mode_display_name() {
  local m
  m="$(canonical_mode_name "${1:-}")"
  echo "$m"
}

mode_to_dir_name() {
  local m
  m="$(canonical_mode_name "${1:-}")"
  echo "$m"
}

mode_override_key() {
  local m
  m="$(canonical_mode_name "${1:-}")"
  echo "$m"
}

mode_exists() {
  local mode
  mode="$(canonical_mode_name "${1:-}")"
  [[ -n "$mode" ]] || return 1
  [[ -d "$DICTATE_CONFIG_DIR/modes/$(mode_to_dir_name "$mode")" ]]
}

mode_dir_path() {
  local mode
  mode="$(canonical_mode_name "${1:-}")"
  [[ -n "$mode" ]] || return 1
  printf "%s\n" "$DICTATE_CONFIG_DIR/modes/$(mode_to_dir_name "$mode")"
}

mode_flows_file_path() {
  local mode_dir
  mode_dir="$(mode_dir_path "${1:-}")" || return 1
  printf "%s\n" "$mode_dir/flows"
}

mode_apps_file_path() {
  local mode_dir
  mode_dir="$(mode_dir_path "${1:-}")" || return 1
  printf "%s\n" "$mode_dir/apps"
}

mode_invalid_flow_entries() {
  local flows_file line invalid_entries=""
  flows_file="$(mode_flows_file_path "${1:-}")" || return 0
  [[ -f "$flows_file" ]] || return 0

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    line="$(printf '%s' "$line" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
    [[ -n "$line" ]] || continue
    case "$line" in
      all|both|tmux|inline) ;;
      *)
        invalid_entries="${invalid_entries}${line}"$'\n'
        ;;
    esac
  done < "$flows_file"

  [[ -n "$invalid_entries" ]] || return 0
  printf '%s' "$invalid_entries" | awk '!seen[$0]++'
}

mode_flow_summary() {
  local mode="${1:-}"
  local allow_tmux="0"
  local allow_inline="0"

  mode_allows_flow "$mode" "tmux" && allow_tmux="1"
  mode_allows_flow "$mode" "inline" && allow_inline="1"

  if [[ "$allow_tmux" == "1" && "$allow_inline" == "1" ]]; then
    echo "tmux+inline"
  elif [[ "$allow_tmux" == "1" ]]; then
    echo "tmux"
  elif [[ "$allow_inline" == "1" ]]; then
    echo "inline"
  else
    echo "hidden"
  fi
}

mode_recommended_flow_spec() {
  local mode required_flow
  mode="$(canonical_mode_name "${1:-}")"
  required_flow="${2:-}"
  case "$required_flow" in
    inline)
      if mode_allows_flow "$mode" "tmux"; then
        echo "both"
      else
        echo "inline"
      fi
      ;;
    tmux)
      if mode_allows_flow "$mode" "inline"; then
        echo "both"
      else
        echo "tmux"
      fi
      ;;
    *)
      echo "both"
      ;;
  esac
}

write_mode_flows() {
  local mode spec flows_file
  mode="$(canonical_mode_name "${1:-}")"
  spec="${2:-}"
  mode_exists "$mode" || die "unknown mode: $mode"
  flows_file="$(mode_flows_file_path "$mode")"
  mkdir -p "$(dirname "$flows_file")"

  case "$spec" in
    inline)
      printf 'inline\n' >"$flows_file"
      ;;
    tmux)
      printf 'tmux\n' >"$flows_file"
      ;;
    both|all)
      printf 'tmux\ninline\n' >"$flows_file"
      ;;
    clear|reset)
      rm -f "$flows_file" 2>/dev/null || true
      ;;
    *)
      die "usage: tmux-whisper mode flows [name] [inline|tmux|both|clear]"
      ;;
  esac
}

show_mode_flows() {
  local mode flows_file summary invalid_entries config_state
  mode="$(canonical_mode_name "${1:-}")"
  mode_exists "$mode" || die "unknown mode: $mode"

  flows_file="$(mode_flows_file_path "$mode")"
  summary="$(mode_flow_summary "$mode")"
  invalid_entries="$(mode_invalid_flow_entries "$mode" | paste -sd ', ' - 2>/dev/null || true)"

  if [[ -f "$flows_file" ]]; then
    config_state="explicit ($flows_file)"
  else
    config_state="default (all flows allowed)"
  fi

  echo "Mode flows for $(mode_display_name "$mode"): $summary"
  echo "  config: $config_state"
  if [[ -f "$flows_file" ]]; then
    local rendered=""
    rendered="$(sed -E 's/#.*$//; s/^[[:space:]]+//; s/[[:space:]]+$//' "$flows_file" 2>/dev/null | sed '/^$/d' | paste -sd ', ' - 2>/dev/null || true)"
    [[ -n "$rendered" ]] && echo "  entries: $rendered"
  fi
  [[ -n "$invalid_entries" ]] && echo "  invalid entries: $invalid_entries"
  echo "Set with:"
  echo "  tmux-whisper mode flows $mode inline|tmux|both|clear"
}

mode_app_entries() {
  local apps_file line
  apps_file="$(mode_apps_file_path "${1:-}")" || return 0
  [[ -f "$apps_file" ]] || return 0

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    line="$(printf '%s' "$line" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
    [[ -n "$line" ]] || continue
    printf '%s\n' "$line"
  done < "$apps_file"
}

mode_app_entry_count() {
  local count="0"
  while IFS= read -r _line; do
    count=$((count + 1))
  done < <(mode_app_entries "${1:-}")
  printf '%s\n' "$count"
}

mode_allows_flow() {
  local mode flow flows_file line saw_entries
  mode="$(canonical_mode_name "${1:-}")"
  flow="${2:-}"
  [[ -n "$mode" ]] || return 1
  [[ -z "$flow" ]] && return 0

  flows_file="$DICTATE_CONFIG_DIR/modes/$(mode_to_dir_name "$mode")/flows"
  [[ -f "$flows_file" ]] || return 0

  saw_entries="0"
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    line="$(printf '%s' "$line" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
    [[ -n "$line" ]] || continue
    saw_entries="1"
    case "$line" in
      all|both) return 0 ;;
      tmux|inline)
        [[ "$line" == "$flow" ]] && return 0
        ;;
    esac
  done < "$flows_file"

  # Empty/comment-only flows files behave like "all" for portability.
  [[ "$saw_entries" == "0" ]]
}

list_modes() {
  local flow="${1:-}"
  local mode_dir mode_name
  for mode_dir in "$DICTATE_CONFIG_DIR/modes"/*/; do
    [[ -d "$mode_dir" ]] || continue
    mode_name="$(basename "$mode_dir")"
    mode_name="$(canonical_mode_name "$mode_name")"
    mode_exists "$mode_name" || continue
    mode_allows_flow "$mode_name" "$flow" || continue
    printf '%s\n' "$mode_name"
  done | sort -u
}

first_mode_for_flow() {
  local flow="${1:-}"
  if mode_exists "code" && mode_allows_flow "code" "$flow"; then
    echo "code"
    return 0
  fi
  local first
  first="$(list_modes "$flow" | head -n 1)"
  [[ -n "$first" ]] && echo "$first" || echo "code"
}

default_inline_mode() {
  if mode_exists "base" && mode_allows_flow "base" "inline"; then
    echo "base"
    return 0
  fi
  first_mode_for_flow "inline"
}

normalize_mode_name() {
  local mode
  mode="$(canonical_mode_name "${1:-}")"
  [[ -z "$mode" ]] && mode="code"
  if mode_exists "$mode"; then
    echo "$mode"
  else
    first_mode_for_flow ""
  fi
}

detect_mode() {
  local app="${1:-}"

  # If no app provided, try to detect frontmost.
  if [[ -z "$app" ]]; then
    app="$(osascript -e 'tell application "System Events" to get name of first process whose frontmost is true' 2>/dev/null || echo "")"
  fi

  [[ -z "$app" ]] && default_inline_mode && return 0

  # Check each mode's apps file.
  for mode_dir in "$DICTATE_CONFIG_DIR/modes"/*/; do
    local mode_name="$(basename "$mode_dir")"
    local apps_file="$mode_dir/apps"
    [[ -f "$apps_file" ]] || continue
    mode_allows_flow "$mode_name" "inline" || continue

    if grep -iq "^${app}$" "$apps_file" 2>/dev/null; then
      normalize_mode_name "$mode_name"
      return 0
    fi
  done

  # Default to a plain dictation mode when no app-specific mapping matches.
  default_inline_mode
}

get_current_mode() {
  local target_app="${1:-}"

  # Allow forcing mode via env var (used by tmux mode).
  if [[ -n "${DICTATE_FORCE_MODE:-}" ]]; then
    normalize_mode_name "$DICTATE_FORCE_MODE"
    return 0
  fi

  if [[ -f "$MODE_FILE" ]]; then
    local saved_mode
    saved_mode="$(head -n 1 "$MODE_FILE" 2>/dev/null | tr -d '\r' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
    if [[ -z "$saved_mode" || "$saved_mode" == "auto" ]]; then
      detect_mode "$target_app"
      return 0
    fi
    if mode_exists "$saved_mode" && mode_allows_flow "$saved_mode" "inline"; then
      normalize_mode_name "$saved_mode"
      return 0
    fi
    detect_mode "$target_app"
    return 0
  fi

  detect_mode "$target_app"
}

build_mode_prompt() {
  local mode
  mode="$(canonical_mode_name "$1")"
  local mode_dir="$DICTATE_CONFIG_DIR/modes/$(mode_to_dir_name "$mode")"

  local base_prompt='You are cleaning speech-to-text dictation.

HARD RULES:
- You are a dictation cleaner/editor, not a task-completing assistant.
- Follow the MODE INSTRUCTIONS below.
- You may add minimal structural elements required by the mode (e.g. paragraph breaks, email greeting/subject), but do not add new facts, steps, or deliverables.
- If the dictation asks to create/generate/list items (e.g. "make 10 prompts"), keep it as a request instead of generating the items, unless the MODE INSTRUCTIONS explicitly require generating them.
- Preserve meaning; do not add new information or opinions.
- Remove filler words and obvious false starts.
- Fix obvious transcription errors and apply corrections.
- Output ONLY the final result (no preamble, no explanations).'

  local mode_prompt=""
  if [[ -f "$mode_dir/prompt" ]]; then
    mode_prompt="$(cat "$mode_dir/prompt")"
  fi

  local global_vocab=""
  if [[ -f "$DICTATE_CONFIG_DIR/vocab" ]]; then
    global_vocab="$(cat "$DICTATE_CONFIG_DIR/vocab" | tr '\n' ';' | sed 's/;$//')"
  fi

  local mode_vocab=""
  if [[ -f "$mode_dir/vocab" ]]; then
    mode_vocab="$(cat "$mode_dir/vocab" | tr '\n' ';' | sed 's/;$//')"
  fi

  local full_prompt="$base_prompt"

  if [[ -n "$mode_prompt" ]]; then
    full_prompt="${full_prompt}

${mode_prompt}"
  fi

  if [[ -n "$global_vocab" ]]; then
    full_prompt="${full_prompt}

GLOBAL CORRECTIONS: ${global_vocab}"
  fi

  if [[ -n "$mode_vocab" ]]; then
    full_prompt="${full_prompt}

MODE CORRECTIONS: ${mode_vocab}"
  fi

  echo "$full_prompt"
}
