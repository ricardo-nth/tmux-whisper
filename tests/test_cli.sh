#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

BIN_DIR="$TMP_ROOT/bin"
HOME_DIR="$TMP_ROOT/home"
mkdir -p "$BIN_DIR" "$HOME_DIR"
OPLOG="$TMP_ROOT/daemon-ops.log"

cp "$ROOT/bin/tmux-whisper" "$BIN_DIR/tmux-whisper"
cp "$ROOT/bin/dictate-lib.sh" "$BIN_DIR/dictate-lib.sh"
chmod +x "$BIN_DIR/tmux-whisper" "$BIN_DIR/dictate-lib.sh"

# Ensure the default ~/.local/bin path is unavailable and fallback-to-sibling works.
output="$(HOME="$HOME_DIR" PATH="$BIN_DIR:/usr/bin:/bin" DICTATE_LIB_PATH= "$BIN_DIR/tmux-whisper" --help)"

if [[ "$output" != *"tmux-whisper: local dictation with pluggable ASR backends"* ]]; then
  echo "Expected help output from tmux-whisper command" >&2
  exit 1
fi

MODEL_DIR="$TMP_ROOT/parakeet-tdt-0.6b-v3-coreml"
CONFIG_DIR="$HOME_DIR/.config/dictate"
mkdir -p "$MODEL_DIR" "$CONFIG_DIR"
cat >"$CONFIG_DIR/config.toml" <<EOF
[meta]
config_version = 1

[audio]
source = "auto"

[whisper]
backend = "swift_parakeet"

[swift_parakeet]
model_path = "$MODEL_DIR"
socket_path = "$TMP_ROOT/tmux-whisperd.sock"
EOF

cat >"$BIN_DIR/tmux-whisperd" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" != "serve" || "${2:-}" != "--socket" || -z "${3:-}" ]]; then
  echo "usage: tmux-whisperd serve --socket <path>" >&2
  exit 2
fi
socket_path="$3"
python3 - "$socket_path" <<'PYEOF'
import json
import os
import socket
import sys

socket_path = sys.argv[1]
try:
    os.unlink(socket_path)
except FileNotFoundError:
    pass

server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
server.bind(socket_path)
server.listen(8)
log_path = os.environ.get("DICTATE_TEST_CLI_OPLOG", "")

while True:
    conn, _ = server.accept()
    try:
        data = b""
        while b"\n" not in data:
            chunk = conn.recv(4096)
            if not chunk:
                break
            data += chunk
        raw = data.split(b"\n", 1)[0]
        request = json.loads(raw.decode("utf-8"))
        op = request.get("op")
        if log_path:
            with open(log_path, "a", encoding="utf-8") as fh:
                fh.write(f"{op}\n")
        if op == "ping":
            response = {
                "id": request.get("id", "stub"),
                "ok": True,
                "engine": "swift_parakeet",
                "duration_ms": 0,
                "message": "ok",
            }
        elif op == "warmup":
            response = {
                "id": request.get("id", "stub"),
                "ok": True,
                "engine": "swift_parakeet",
                "model": os.path.basename(request.get("model_path", "")),
                "duration_ms": 12,
                "message": "warmed",
            }
        elif op == "transcribe":
            wav_path = request.get("wav_path", "")
            if not wav_path or not os.path.exists(wav_path):
                raise SystemExit("missing warmup wav_path")
            import wave
            with wave.open(wav_path, "rb") as wav_file:
                frames = wav_file.getnframes()
                sample_rate = wav_file.getframerate()
            if sample_rate != 16000:
                raise SystemExit(f"warmup prime sample rate mismatch: {sample_rate}")
            duration_ms = int((frames / sample_rate) * 1000)
            if duration_ms < 1000:
                raise SystemExit(f"warmup prime audio too short: {duration_ms}ms")
            response = {
                "id": request.get("id", "stub"),
                "ok": True,
                "engine": "swift_parakeet",
                "model": os.path.basename(request.get("model_path", "")),
                "text": "",
                "duration_ms": 4,
                "message": None,
            }
        else:
            response = {
                "id": request.get("id", "stub"),
                "ok": False,
                "engine": "swift_parakeet",
                "error_code": "unsupported_operation",
                "message": op or "unknown",
            }
        conn.sendall(json.dumps(response).encode("utf-8") + b"\n")
        if op == "transcribe":
            break
    finally:
        conn.close()

server.close()
try:
    os.unlink(socket_path)
except FileNotFoundError:
    pass
PYEOF
EOF
chmod +x "$BIN_DIR/tmux-whisperd"

warmup_output="$(HOME="$HOME_DIR" PATH="$BIN_DIR:/usr/bin:/bin" DICTATE_LIB_PATH= DICTATE_CONFIG_DIR="$CONFIG_DIR" DICTATE_CONFIG_FILE="$CONFIG_DIR/config.toml" DICTATE_TMUX_WHISPERD_BIN="$BIN_DIR/tmux-whisperd" DICTATE_TEST_CLI_OPLOG="$OPLOG" "$BIN_DIR/tmux-whisper" warmup)"

if [[ "$warmup_output" != *"Warmup: ready (model=parakeet-tdt-0.6b-v3-coreml, duration=12ms)"* ]]; then
  echo "Expected warmup output from tmux-whisper command" >&2
  echo "$warmup_output" >&2
  exit 1
fi

if ! grep -Fxq "warmup" "$OPLOG" || ! grep -Fxq "transcribe" "$OPLOG"; then
  echo "Expected warmup command to prime with a synthetic transcribe" >&2
  cat "$OPLOG" >&2 || true
  exit 1
fi

rm -f "$OPLOG"

warmup_output="$(HOME="$HOME_DIR" PATH="$BIN_DIR:/usr/bin:/bin" DICTATE_LIB_PATH= DICTATE_CONFIG_DIR="$CONFIG_DIR" DICTATE_CONFIG_FILE="$CONFIG_DIR/config.toml" DICTATE_TMUX_WHISPERD_BIN="$BIN_DIR/tmux-whisperd" DICTATE_TEST_CLI_OPLOG="$OPLOG" DICTATE_WARMUP_PRIME_MS=0800 "$BIN_DIR/tmux-whisper" warmup)"

if [[ "$warmup_output" != *"Warmup: ready (model=parakeet-tdt-0.6b-v3-coreml, duration=12ms)"* ]]; then
  echo "Expected warmup output with leading-zero prime duration override" >&2
  echo "$warmup_output" >&2
  exit 1
fi

if ! grep -Fxq "warmup" "$OPLOG" || ! grep -Fxq "transcribe" "$OPLOG"; then
  echo "Expected warmup command with leading-zero override to complete prime transcribe" >&2
  cat "$OPLOG" >&2 || true
  exit 1
fi

echo "CLI relocation smoke test passed."
