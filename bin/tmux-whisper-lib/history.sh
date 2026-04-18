#!/usr/bin/env bash

# History helpers are split out so operator-facing CLI work can evolve without
# adding more weight to the main runtime/dispatch file.

# Save a dictation to history
# Usage: save_history "raw_transcript" "processed_text" "mode" "app" [record_ms] [transcribe_ms] [clean_ms] [postprocess_ms] [paste_ms] [total_ms]
save_history() {
  local raw="$1"
  local processed="$2"
  local mode="${3:-unknown}"
  local app="${4:-unknown}"
  local record_ms="${5:-}"
  local transcribe_ms="${6:-}"
  local clean_ms="${7:-}"
  local postprocess_ms="${8:-}"
  local paste_ms="${9:-}"
  local total_ms="${10:-}"

  mkdir -p "$HISTORY_DIR"

  # Get retention days from config (default 7)
  local retention="${CFG_HISTORY_RETENTION_DAYS:-7}"

  # Clean old entries first
  cleanup_history "$retention"

  # Generate timestamp filename
  local ts
  ts="$(date '+%Y-%m-%dT%H-%M-%S')"
  local filename="$HISTORY_DIR/${ts}.json"

  # Escape for JSON
  local raw_escaped processed_escaped mode_escaped app_escaped
  raw_escaped="$(printf '%s' "$raw" | jq -Rs .)"
  processed_escaped="$(printf '%s' "$processed" | jq -Rs .)"
  mode_escaped="$(printf '%s' "$mode" | jq -Rs .)"
  app_escaped="$(printf '%s' "$app" | jq -Rs .)"

  local metrics_lines=""
  append_metric_line() {
    local key="$1"
    local val="$2"
    [[ "$val" =~ ^[0-9]+$ ]] || return 0
    if [[ -n "$metrics_lines" ]]; then
      metrics_lines="${metrics_lines},"$'\n'
    fi
    metrics_lines="${metrics_lines}    \"${key}\": ${val}"
  }
  append_metric_line "record_ms" "$record_ms"
  append_metric_line "transcribe_ms" "$transcribe_ms"
  append_metric_line "clean_ms" "$clean_ms"
  append_metric_line "postprocess_ms" "$postprocess_ms"
  append_metric_line "paste_ms" "$paste_ms"
  append_metric_line "total_ms" "$total_ms"

  local budget_obs_lines=""
  if [[ "${DICTATE_LAST_POSTPROCESS_BUDGET_OBS_ACTIVE:-0}" == "1" ]]; then
    local _profile _llm
    local profile_escaped llm_escaped
    _profile="${DICTATE_LAST_POSTPROCESS_BUDGET_PROFILE:-}"
    _llm="${DICTATE_LAST_POSTPROCESS_BUDGET_LLM_MODEL:-}"
    profile_escaped="$(printf '%s' "$_profile" | jq -Rs .)"
    llm_escaped="$(printf '%s' "$_llm" | jq -Rs .)"
    budget_obs_lines="    \"numeric_sizing\": \"auto_dynamic\","$'\n'
    budget_obs_lines="${budget_obs_lines}    \"profile\": ${profile_escaped}"
    [[ "${DICTATE_LAST_POSTPROCESS_BUDGET_THRESHOLD:-}" =~ ^[0-9]+$ ]] && budget_obs_lines="${budget_obs_lines},"$'\n'"    \"threshold_words\": ${DICTATE_LAST_POSTPROCESS_BUDGET_THRESHOLD}"
    [[ "${DICTATE_LAST_POSTPROCESS_BUDGET_WORD_COUNT:-}" =~ ^[0-9]+$ ]] && budget_obs_lines="${budget_obs_lines},"$'\n'"    \"word_count\": ${DICTATE_LAST_POSTPROCESS_BUDGET_WORD_COUNT}"
    [[ "${DICTATE_LAST_POSTPROCESS_BUDGET_MAX_TOKENS:-}" =~ ^[0-9]+$ ]] && budget_obs_lines="${budget_obs_lines},"$'\n'"    \"max_tokens\": ${DICTATE_LAST_POSTPROCESS_BUDGET_MAX_TOKENS}"
    [[ "${DICTATE_LAST_POSTPROCESS_BUDGET_CHUNK_WORDS:-}" =~ ^[0-9]+$ ]] && budget_obs_lines="${budget_obs_lines},"$'\n'"    \"chunk_words\": ${DICTATE_LAST_POSTPROCESS_BUDGET_CHUNK_WORDS}"
    [[ "${DICTATE_LAST_POSTPROCESS_BUDGET_CHUNK_COUNT:-}" =~ ^[0-9]+$ ]] && budget_obs_lines="${budget_obs_lines},"$'\n'"    \"chunk_count\": ${DICTATE_LAST_POSTPROCESS_BUDGET_CHUNK_COUNT}"
    [[ -n "$_llm" ]] && budget_obs_lines="${budget_obs_lines},"$'\n'"    \"llm\": ${llm_escaped}"
  fi

  local extra_fields=""
  if [[ -n "$metrics_lines" ]]; then
    extra_fields="${extra_fields},"$'\n'"  \"metrics\": {"$'\n'"${metrics_lines}"$'\n'"  }"
  fi
  if [[ -n "$budget_obs_lines" ]]; then
    extra_fields="${extra_fields},"$'\n'"  \"postprocess_budget\": {"$'\n'"${budget_obs_lines}"$'\n'"  }"
  fi

  cat > "$filename" <<EOF
{
  "timestamp": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "mode": $mode_escaped,
  "app": $app_escaped,
  "raw": $raw_escaped,
  "processed": $processed_escaped${extra_fields}
}
EOF
}

# Remove history entries older than N days
cleanup_history() {
  local days="${1:-7}"
  [[ -d "$HISTORY_DIR" ]] || return 0

  # Find and delete files older than N days
  find "$HISTORY_DIR" -name "*.json" -type f -mtime +"$days" -delete 2>/dev/null || true
}

history_entry_file_by_index() {
  local n="${1:-1}"
  [[ "$n" =~ ^[0-9]+$ ]] || return 1
  [[ -d "$HISTORY_DIR" ]] || return 1
  ls -1t "$HISTORY_DIR"/*.json 2>/dev/null | sed -n "${n}p"
}

history_entry_json() {
  local n="${1:-1}"
  local file
  file="$(history_entry_file_by_index "$n")"
  if [[ -z "$file" || ! -f "$file" ]]; then
    die "history entry $n not found"
  fi

  jq --argjson index "$n" --arg file "$file" '
    {
      index: $index,
      file: $file,
      entry: .
    }
  ' "$file"
}

# List recent history entries
list_history() {
  local limit="${1:-20}"

  if [[ ! -d "$HISTORY_DIR" ]]; then
    echo "No history yet."
    return 0
  fi

  local files
  files="$(ls -1t "$HISTORY_DIR"/*.json 2>/dev/null | head -n "$limit")"

  if [[ -z "$files" ]]; then
    echo "No history entries."
    return 0
  fi

  echo "Recent dictations (newest first):"
  echo ""

  local i=1
  while IFS= read -r f; do
    local basename ts mode preview
    basename="$(basename "$f" .json)"
    ts="${basename/T/ }"
    ts="${ts//-/:}"
    # Fix: first 2 colons in date should be dashes
    ts="$(echo "$ts" | sed -E 's/:/-/; s/:/-/')"
    mode="$(jq -r '.mode // "?"' "$f" 2>/dev/null)"
    preview="$(jq -r '.processed // .raw' "$f" 2>/dev/null | head -c 60 | tr '\n' ' ')"
    printf "%2d. [%s] (%s) %s...\n" "$i" "$ts" "$mode" "$preview"
    ((i++))
  done <<< "$files"
}

# Show a specific history entry
show_history() {
  local n="${1:-1}"

  local file
  file="$(history_entry_file_by_index "$n")"

  if [[ -z "$file" || ! -f "$file" ]]; then
    die "history entry $n not found"
  fi

  local mode app raw processed
  local metrics_lines budget_lines
  mode="$(jq -r '.mode // "?"' "$file")"
  app="$(jq -r '.app // "?"' "$file")"
  raw="$(jq -r '.raw // ""' "$file")"
  processed="$(jq -r '.processed // ""' "$file")"
  metrics_lines="$(jq -r '
    (.metrics // {}) as $m
    | ["record_ms","transcribe_ms","clean_ms","postprocess_ms","paste_ms","total_ms"][]
    | select($m[.] != null)
    | "\(.) : \($m[.])"
  ' "$file" 2>/dev/null || true)"
  budget_lines="$(jq -r '
    (.postprocess_budget // {}) as $b
    | ["numeric_sizing","profile","threshold_words","word_count","max_tokens","chunk_words","chunk_count","llm"][]
    | select($b[.] != null)
    | "\(.) : \($b[.])"
  ' "$file" 2>/dev/null || true)"

  echo "=== Entry $n ==="
  echo "File: $(basename "$file")"
  echo "Mode: $mode"
  echo "App: $app"
  if [[ -n "${metrics_lines//[[:space:]]/}" ]]; then
    echo ""
    echo "--- Metrics ---"
    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      echo "$line"
    done <<< "$metrics_lines"
  fi
  if [[ -n "${budget_lines//[[:space:]]/}" ]]; then
    echo ""
    echo "--- Postprocess Budget ---"
    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      echo "$line"
    done <<< "$budget_lines"
  fi
  echo ""
  echo "--- Raw transcript ---"
  echo "$raw"
  echo ""
  echo "--- Processed ---"
  echo "$processed"
}

show_last_history() {
  local output_format="${1:-text}"
  local file
  file="$(history_entry_file_by_index 1)"

  if [[ -z "$file" || ! -f "$file" ]]; then
    echo "No history entries."
    return 0
  fi

  if [[ "$output_format" == "json" ]]; then
    history_entry_json 1
    return 0
  fi

  local timestamp mode app raw processed
  local raw_words processed_words metrics_compact budget_compact preview
  timestamp="$(jq -r '.timestamp // ""' "$file" 2>/dev/null)"
  mode="$(jq -r '.mode // "?"' "$file" 2>/dev/null)"
  app="$(jq -r '.app // "?"' "$file" 2>/dev/null)"
  raw="$(jq -r '.raw // ""' "$file" 2>/dev/null)"
  processed="$(jq -r '.processed // ""' "$file" 2>/dev/null)"
  raw_words="$(printf '%s' "$raw" | wc -w | tr -d '[:space:]')"
  processed_words="$(printf '%s' "$processed" | wc -w | tr -d '[:space:]')"
  metrics_compact="$(jq -r '
    (.metrics // {}) as $m
    | ["record_ms","transcribe_ms","clean_ms","postprocess_ms","paste_ms","total_ms"]
    | map(select($m[.] != null) | "\(.)=\($m[.])ms")
    | join(" ")
  ' "$file" 2>/dev/null || true)"
  budget_compact="$(jq -r '
    (.postprocess_budget // {}) as $b
    | if ($b | length) == 0 then ""
      else
        [
          (if $b.profile != null then "profile=\($b.profile)" else empty end),
          (if $b.word_count != null then "words=\($b.word_count)" else empty end),
          (if $b.max_tokens != null then "max_tokens=\($b.max_tokens)" else empty end),
          (if $b.chunk_count != null then "chunks=\($b.chunk_count)" else empty end)
        ] | join(" ")
      end
  ' "$file" 2>/dev/null || true)"
  preview="$(printf '%s' "$processed" | tr '\n' ' ' | head -c 120)"

  echo "Latest dictation"
  echo "  timestamp: ${timestamp:-unknown}"
  echo "  mode: ${mode:-?}"
  echo "  app: ${app:-?}"
  echo "  raw_words: ${raw_words:-0}"
  echo "  processed_words: ${processed_words:-0}"
  if [[ -n "${metrics_compact//[[:space:]]/}" ]]; then
    echo "  metrics: $metrics_compact"
  fi
  if [[ -n "${budget_compact//[[:space:]]/}" ]]; then
    echo "  budget: $budget_compact"
  fi
  echo "  preview: ${preview}..."
}

# Reprocess a history entry with a different mode
reprocess_history() {
  local n="${1:-1}"
  local target_mode="${2:-}"

  if [[ -z "${CEREBRAS_API_KEY:-}" ]]; then
    die "reprocess requires CEREBRAS_API_KEY"
  fi

  if [[ ! -d "$HISTORY_DIR" ]]; then
    die "no history directory"
  fi

  local file
  file="$(ls -1t "$HISTORY_DIR"/*.json 2>/dev/null | sed -n "${n}p")"

  if [[ -z "$file" || ! -f "$file" ]]; then
    die "history entry $n not found"
  fi

  local raw
  raw="$(jq -r '.raw // ""' "$file")"

  if [[ -z "$raw" ]]; then
    die "no raw transcript in entry $n"
  fi

  # Determine mode
  if [[ -z "$target_mode" ]]; then
    target_mode="$(get_current_mode)"
  else
    target_mode="$(canonical_mode_name "$target_mode")"
    if [[ ! -d "$DICTATE_CONFIG_DIR/modes/$(mode_to_dir_name "$target_mode")" ]]; then
      die "unknown mode: $target_mode"
    fi
  fi

  echo "🔄 Reprocessing entry $n with $(mode_display_name "$target_mode") mode..."

  local result
  result="$(DICTATE_FORCE_MODE="$target_mode" postprocess_llm "$raw" "")"
  result="$(printf "%s" "$result" | auto_paragraphs "$target_mode" | normalize_british_spelling)"

  printf "%s" "$result" | pbcopy

  echo "✅ Done. Result copied to clipboard:"
  echo ""
  echo "$result"
}

# Main history command handler
manage_history() {
  local json_output="0"
  local args=()
  local arg
  for arg in "$@"; do
    if [[ "$arg" == "--json" ]]; then
      json_output="1"
    else
      args+=("$arg")
    fi
  done
  set -- "${args[@]}"

  local subcmd="${1:-}"
  shift 2>/dev/null || true

  case "$subcmd" in
    ""|list)
      list_history "${1:-20}"
      ;;
    stats)
      need python3
      local history_dir="$HISTORY_DIR"
      if [[ ! -d "$history_dir" ]]; then
        die "no history directory"
      fi
      python3 - "$history_dir" "$json_output" <<'PYEOF'
import glob, json, os, re, statistics, sys

history_dir = os.path.expanduser(sys.argv[1])
json_output = sys.argv[2] == "1"
files = sorted(glob.glob(os.path.join(history_dir, "*.json")))
if not files:
    if json_output:
        print(json.dumps({"entries": 0, "history_files": 0, "postprocess_budget": {"entries": 0}}, indent=2))
    else:
        print("No history entries found.")
    raise SystemExit(0)

def word_count(s: str) -> int:
    return len(re.findall(r"\b\w+\b", s or ""))

def pctl(arr, pct):
    arr = [int(x) for x in arr]
    if not arr:
        return 0
    vals = sorted(arr)
    if len(vals) == 1:
        return vals[0]
    pos = (len(vals) - 1) * pct
    lo = int(pos)
    hi = min(lo + 1, len(vals) - 1)
    frac = pos - lo
    return int(round(vals[lo] * (1 - frac) + vals[hi] * frac))

def metric_summary(arr):
    vals = [int(x) for x in arr]
    if not vals:
        return {"n": 0, "median": 0, "p95": 0, "max": 0}
    return {
        "n": len(vals),
        "median": int(statistics.median(vals)),
        "p95": pctl(vals, 0.95),
        "max": max(vals),
    }

raw_chars = []
raw_words = []
proc_chars = []
proc_words = []
budget_rows = []

for f in files:
    try:
        with open(f, "r", encoding="utf-8") as fh:
            data = json.load(fh)
    except Exception:
        continue
    raw = data.get("raw", "") or ""
    proc = data.get("processed", "") or ""
    raw_chars.append(len(raw))
    raw_words.append(word_count(raw))
    proc_chars.append(len(proc))
    proc_words.append(word_count(proc))
    budget = data.get("postprocess_budget") or {}
    metrics = data.get("metrics") or {}
    if isinstance(budget, dict) and budget:
        def bint(name):
            v = budget.get(name)
            try:
                return int(v)
            except Exception:
                return 0
        def mint(name):
            v = metrics.get(name) if isinstance(metrics, dict) else None
            try:
                return int(v)
            except Exception:
                return 0
        budget_rows.append(
            {
                "profile": str(budget.get("profile", "") or ""),
                "word_count": bint("word_count"),
                "threshold_words": bint("threshold_words"),
                "max_tokens": bint("max_tokens"),
                "chunk_words": bint("chunk_words"),
                "chunk_count": bint("chunk_count"),
                "postprocess_ms": mint("postprocess_ms"),
                "numeric_sizing": str(budget.get("numeric_sizing", "") or ""),
            }
        )

profile_counts = {}
for row in budget_rows:
    p = row.get("profile") or "<unset>"
    profile_counts[p] = profile_counts.get(p, 0) + 1
numeric_modes = sorted({row.get("numeric_sizing", "") for row in budget_rows if row.get("numeric_sizing", "")})
thresholds = sorted({row.get("threshold_words", 0) for row in budget_rows if row.get("threshold_words", 0) > 0})

payload = {
    "entries": len(files),
    "history_files": len(files),
    "raw_chars": metric_summary(raw_chars),
    "raw_words": metric_summary(raw_words),
    "processed_chars": metric_summary(proc_chars),
    "processed_words": metric_summary(proc_words),
    "approx_max_tokens_raw": int(max(raw_words) * 1.33) if raw_words else 0,
    "postprocess_budget": {
        "entries": len(budget_rows),
        "profile_counts": profile_counts,
        "numeric_sizing": numeric_modes,
        "threshold_words": thresholds,
        "word_count": metric_summary([r["word_count"] for r in budget_rows if int(r["word_count"]) > 0]),
        "max_tokens": metric_summary([r["max_tokens"] for r in budget_rows if int(r["max_tokens"]) > 0]),
        "chunk_words": metric_summary([r["chunk_words"] for r in budget_rows if int(r["chunk_words"]) > 0]),
        "chunk_count": metric_summary([r["chunk_count"] for r in budget_rows if int(r["chunk_count"]) > 0]),
        "postprocess_ms": metric_summary([r["postprocess_ms"] for r in budget_rows if int(r["postprocess_ms"]) > 0]),
    },
}

if json_output:
    print(json.dumps(payload, indent=2, sort_keys=True))
    raise SystemExit(0)

print(f"History entries: {payload['entries']}")
print(f"raw_chars: max={payload['raw_chars']['max']}, p95={payload['raw_chars']['p95']}, median={payload['raw_chars']['median']}")
print(f"raw_words: max={payload['raw_words']['max']}, p95={payload['raw_words']['p95']}, median={payload['raw_words']['median']}")
print(f"processed_chars: max={payload['processed_chars']['max']}, p95={payload['processed_chars']['p95']}, median={payload['processed_chars']['median']}")
print(f"processed_words: max={payload['processed_words']['max']}, p95={payload['processed_words']['p95']}, median={payload['processed_words']['median']}")
print(f"approx_max_tokens (raw words * 1.33): {payload['approx_max_tokens_raw']}")

if budget_rows:
    print("")
    print(f"Postprocess budget observability entries: {payload['postprocess_budget']['entries']}")
    if profile_counts:
        print("budget_profile_counts: " + ", ".join(f"{k}={v}" for k, v in sorted(profile_counts.items())))
    if numeric_modes:
        print("budget_numeric_sizing: " + ", ".join(numeric_modes))
    if thresholds:
        print("budget_threshold_words: " + ", ".join(str(x) for x in thresholds))
    for label, key in (
        ("budget.word_count", "word_count"),
        ("budget.max_tokens", "max_tokens"),
        ("budget.chunk_words", "chunk_words"),
        ("budget.chunk_count", "chunk_count"),
        ("metrics.postprocess_ms", "postprocess_ms"),
    ):
        metric = payload["postprocess_budget"][key]
        print(f"{label}: n={metric['n']} median={metric['median']} p95={metric['p95']} max={metric['max']}")
PYEOF
      ;;
    clear)
      if [[ -d "$HISTORY_DIR" ]]; then
        rm -rf "$HISTORY_DIR"
        echo "History cleared."
      else
        echo "No history to clear."
      fi
      ;;
    reprocess)
      reprocess_history "${1:-1}" "${2:-}"
      ;;
    [0-9]*)
      if [[ "$json_output" == "1" ]]; then
        history_entry_json "$subcmd"
      else
        show_history "$subcmd"
      fi
      ;;
    *)
      die "unknown history command: $subcmd (use: list, N, reprocess, clear, stats)"
      ;;
  esac
}
