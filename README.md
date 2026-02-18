# dictate-cli

Local-first dictation for macOS using `ffmpeg` + `whisper.cpp` (`whisper-cli`), with optional LLM cleanup and tmux/desktop integrations.

## Core USP

Dictate is **tmux-first**.

- Primary workflow: record in a tmux pane, let transcription/process run, and keep working in other panes/windows.
- Inline dictation is supported, but it is a secondary convenience path.
- Design priority is reliability and flow inside terminal/tmux environments over maximum raw transcription speed.

## What You Get

- `bin/dictate`: main CLI
- `bin/dictate-lib.sh`: shared helper library used by CLI and integrations
- `config/`: default config, modes, and vocab
- `integrations/raycast/`: Raycast scripts (`inline`, `toggle`, `cancel`)
- `integrations/dictate-status.0.2s.sh`: SwiftBar plugin
- `assets/sounds/dictate/`: tiny sample WAV sound pack
- `install.sh`: local installer
- `tests/`: deterministic bash tests and install smoke tests
- `.github/workflows/ci.yml`: CI for syntax + tests

## Requirements

- macOS
- `ffmpeg`
- `whisper-cli` (from whisper.cpp)
- `python3` (with `tomllib`, Python 3.11+ recommended)
- Optional: `tmux`, Raycast, SwiftBar
- Optional for LLM postprocess: `CEREBRAS_API_KEY`

## Install

Homebrew (recommended):

```bash
brew tap ricardo-nth/tap
brew install ricardo-nth/tap/dictate-cli
```

Or one-line bootstrap:

```bash
curl -fsSL https://raw.githubusercontent.com/ricardo-nth/dictate-cli/main/bootstrap.sh | bash
```

Update:

```bash
brew upgrade dictate-cli
```

First run:

```bash
dictate debug
dictate --help
```

Pinned to stable tag:

```bash
curl -fsSL https://raw.githubusercontent.com/ricardo-nth/dictate-cli/v0.4.0/bootstrap.sh | bash
```

Pass install flags through bootstrap:

```bash
curl -fsSL https://raw.githubusercontent.com/ricardo-nth/dictate-cli/main/bootstrap.sh | bash -s -- --force --with-sounds
```

Or install from a local clone:

```bash
git clone https://github.com/ricardo-nth/dictate-cli.git
cd dictate-cli
./install.sh
```

Install behavior:

- Does not overwrite existing `~/.config/dictate/*` defaults unless `--force` is used.
- Installs Raycast scripts to `~/.config/dictate/integrations/raycast`.
- Installs SwiftBar plugin to `~/.config/swiftbar/plugins/dictate-status.0.2s.sh`.
- Installs sample sounds to `~/.local/share/sounds/dictate`.

Useful install flags:

```bash
./install.sh --force         # refresh config defaults (creates backups)
./install.sh --no-sounds     # skip sample sound install
./install.sh --with-sounds   # explicit sound install
```

`bootstrap.sh` downloads a repository archive from GitHub and runs `install.sh` from that archive.

## Quick Start

```bash
dictate debug
dictate            # tmux-first toggle mode
dictate devices
dictate inline
dictate mode short
dictate postprocess on
```

## Integrations

### Raycast

Import or point Raycast script commands to:

- `~/.config/dictate/integrations/raycast/dictate-inline.sh`
- `~/.config/dictate/integrations/raycast/dictate-toggle.sh`
- `~/.config/dictate/integrations/raycast/dictate-cancel.sh`

### SwiftBar

Use plugin:

- `~/.config/swiftbar/plugins/dictate-status.0.2s.sh`

If needed, set `DICTATE_INSTALL_SWIFTBAR=0` to skip plugin install.

## Sounds

Bundled sample sounds live in `assets/sounds/dictate/` and install by default to:

```bash
~/.local/share/sounds/dictate
```

Default config references that location directly, so sounds work out of the box after install.

## Development Workflow

Use this repo as the source of truth and install to your local runtime path:

```bash
# from repo root
./install.sh --force
```

Then test your local command:

```bash
dictate debug
dictate bench 10
```

## Testing and CI

Run local checks:

```bash
./tests/ci.sh
```

This runs:

- `bash -n` syntax checks across shipped shell scripts
- `tests/test_lib.sh` (helper behavior)
- `tests/test_cli.sh` (relocation behavior for brew installs)
- `tests/test_regression.sh` (diagnostic/integration hardening guards)
- `tests/test_flow_parity.sh` (stubbed tmux/inline lifecycle + send-path parity)
- `tests/test_install.sh` (installer smoke tests)
- `tests/test_bootstrap.sh` (bootstrap flow smoke test)

GitHub Actions runs the same checks on push and pull requests.

## Changelog

`CHANGELOG.md` in this repo mirrors the detailed project history from local development, including the active TODO/next queue.

## Roadmap

See `ROADMAP.md` for current milestone direction (tmux-first hardening -> UX maturity -> integration platform -> stable release).

## Contributing

See `CONTRIBUTING.md` for branch, validation, and release expectations.

Release operators should also follow `docs/RELEASE_CHECKLIST.md`.

## Safety Notes

- Runtime directories (`history`, caches, archives, temp logs) are not tracked.
- API keys are not stored in this repository.
- Existing local config is preserved unless `--force` is used.

## License

MIT
