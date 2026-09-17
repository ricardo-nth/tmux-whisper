#!/usr/bin/env python3
"""Manual native-menu fixture; never calls the real dictation runtime.

Set DICTATE_BIN to this absolute path. Optional WHISPER_PREVIEW_STATE_FILE
selects a writable JSON state file for transitions; otherwise status is ready.
Write {"state":"processing"} / {"state":"attention"} / {"state":"error"}
to inspect those menu states. Command failures use {"state":"ready","fail":true}.
"""
import json
import os
import pathlib
import sys

path = os.environ.get("WHISPER_PREVIEW_STATE_FILE")
value = json.loads(pathlib.Path(path).read_text()) if path and pathlib.Path(path).exists() else {"state": "ready"}
state = value.get("state", "ready")
if sys.argv[1:] == ["status", "--json"]:
    if state == "error":
        print("Preview: CLI unavailable. Refresh after restoring the fixture.", file=sys.stderr)
        sys.exit(1)
    recording = state == "recording"
    processing = int(state == "processing")
    print(json.dumps({
        "command": "status",
        "summary": {"state": state, "headline": f"Preview: {state}.",
                    "next_action": "This fixture does not record or paste.",
                    "active_flow": "inline" if recording else None},
        "runtime": {
            "inline": {"state": "active" if recording else "idle", "stale": False},
            "tmux": {"state": "idle", "stale": False},
            "processing_markers": {"total": processing, "live": processing, "stale": 0},
            "tmux_queue": {"total": 0, "recording": 0, "processing": 0}
        }
    }))
else:
    if value.get("fail"):
        print("Preview command failure. Check your CLI and try again.", file=sys.stderr)
        sys.exit(1)
    commands = {("inline", "start"): "recording", ("inline", "stop"): "processing", ("cancel",): "ready"}
    next_state = commands.get(tuple(sys.argv[1:]))
    if not path or not next_state:
        print("Set WHISPER_PREVIEW_STATE_FILE for preview controls.", file=sys.stderr)
        sys.exit(1)
    pathlib.Path(path).write_text(json.dumps({"state": next_state}))
