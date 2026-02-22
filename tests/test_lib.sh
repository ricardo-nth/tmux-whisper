#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/bin/dictate-lib.sh"

pass() {
  printf "PASS: %s\n" "$1"
}

fail() {
  printf "FAIL: %s\n" "$1" >&2
  exit 1
}

assert_eq() {
  local name="$1"
  local expected="$2"
  local actual="$3"
  if [[ "$expected" != "$actual" ]]; then
    printf "Expected: [%s]\nActual:   [%s]\n" "$expected" "$actual" >&2
    fail "$name"
  fi
  pass "$name"
}

assert_contains() {
  local name="$1"
  local haystack="$2"
  local needle="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    printf "Did not find [%s] in [%s]\n" "$needle" "$haystack" >&2
    fail "$name"
  fi
  pass "$name"
}

trim_nl() {
  tr -d '\n'
}

assert_eq "expand_path_home" "$HOME/tmp" "$(dictate_lib_expand_path '~/tmp')"

SOUNDS_DIR="/tmp/example-sounds"
export SOUNDS_DIR
assert_eq "expand_sound_path" "/tmp/example-sounds/dictate/start.wav" "$(dictate_lib_expand_sound_path '$SOUNDS_DIR/dictate/start.wav')"
unset SOUNDS_DIR

cleaned="$(printf '%s' 'um, I mean basically this is fine' | dictate_lib_clean_fillers | trim_nl)"
assert_eq "clean_fillers" "this is fine" "$cleaned"

repeats1="$(printf '%s' 'this this is is fine fine' | dictate_lib_clean_repeats 1 | trim_nl)"
assert_eq "clean_repeats_level1" "this is fine" "$repeats1"

repeats2="$(printf '%s' 'go to go to the store' | dictate_lib_clean_repeats 2 | trim_nl)"
assert_eq "clean_repeats_level2" "go to the store" "$repeats2"

sanitized="$(printf '%s' '[blank audio] hello (blank_audio) world' | dictate_lib_sanitize_transcript_artifacts | trim_nl)"
assert_eq "sanitize_artifacts" "hello world" "$sanitized"

british="$(printf '%s' 'Color and optimize behavior.' | dictate_lib_normalize_british_spelling 1 | trim_nl)"
assert_eq "british_spelling" "Colour and optimise behaviour." "$british"

para_input="Sentence one is long enough. Sentence two continues with more words. Sentence three keeps this going. Sentence four closes it out."
para_out="$(printf '%s' "$para_input" | dictate_lib_auto_paragraphs code 10)"
assert_contains "auto_paragraphs_split" "$para_out" $'\n\n'

cfg_tmp="$(mktemp -d)"
trap 'rm -rf "$cfg_tmp"' EXIT
mkdir -p "$cfg_tmp/modes/code"
printf '%s\n' 'codex -> Codex' > "$cfg_tmp/vocab"
printf '%s\n' 'tmux -> Tmux' > "$cfg_tmp/modes/code/vocab"
vocab_out="$(printf '%s' 'codex and tmux' | dictate_lib_apply_vocab_corrections code "$cfg_tmp" | trim_nl)"
assert_eq "vocab_corrections" "Codex and Tmux" "$vocab_out"

assert_eq "resolve_model_turbo" "/models/ggml-large-v3-turbo-q5_0.bin" "$(dictate_lib_resolve_model_path turbo /models)"
assert_eq "resolve_model_alias_file" "/tmp/ggml-large-v3-turbo-q5_0.bin" "$(dictate_lib_resolve_model_path /tmp/ggml-large-v3-turbo.bin /unused)"

echo "All lib helper tests passed."
