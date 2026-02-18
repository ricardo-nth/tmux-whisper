# dictate-cli

Local dictation CLI for macOS using `ffmpeg` + `whisper.cpp`, with optional LLM post-processing.

## What this repo provides

- `bin/dictate`: main CLI command
- `bin/dictate-lib.sh`: shared helper library
- `config/`: default config, modes, and vocab
- `integrations/raycast/`: Raycast scripts for inline/toggle/cancel
- `integrations/dictate-status.0.2s.sh`: SwiftBar plugin
- `install.sh`: installer for local setup

## Requirements

- macOS
- `ffmpeg`
- `whisper-cli` (from whisper.cpp)
- `python3` (tomllib support)
- Optional: `tmux`, Raycast, SwiftBar
- Optional for LLM postprocess: `CEREBRAS_API_KEY`

## Install

```bash
git clone https://github.com/ricardo-nth/dictate-cli.git
cd dictate-cli
./install.sh
```

Force refresh defaults (backs up existing config files first):

```bash
./install.sh --force
```

## Quick start

```bash
dictate debug
dictate devices
dictate inline
dictate mode short
dictate postprocess on
```

## Whisper models

Default lookup path is:

```bash
~/.local/share/whisper/models
```

Place your `ggml-*.bin` model files there, then set one with:

```bash
dictate model base
```

## Safety notes

- This repo excludes runtime history/cache directories.
- No API keys are stored in repo config.
- Existing `~/.config/dictate` files are not overwritten unless `--force` is used.

## License

MIT
