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
dictate doctor
dictate --help
```

Pinned to stable tag:

```bash
curl -fsSL https://raw.githubusercontent.com/ricardo-nth/dictate-cli/v0.4.1/bootstrap.sh | bash
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
./install.sh --force            # refresh config defaults (creates backups)
./install.sh --no-sounds        # skip sample sound install
./install.sh --with-sounds      # explicit sound install
./install.sh --replace-sounds   # overwrite existing sound files with bundled samples
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

### Bench matrix

`dictate bench-matrix [N] [phrase_file]` runs the cleanup/postprocess pipeline across the in-repo phrase list (or a small file you supply) with the requested number of rounds. Each line in `phrase_file` is trimmed and blank/commented lines (those beginning with `#`) are ignored, so you can customize the set while keeping the defaults for quick comparison. Set `DICTATE_BENCH_MATRIX_MODE` to force which fixed mode (typically `short`) drives the cleanup, postprocess, and vocab helpers. The output table is sorted by postprocess, model, and vocab settings to keep diffs stable, and you still see the warning `postprocess=on combos skipped` if `CEREBRAS_API_KEY` is unset.

## UX Helpers

- `dictate doctor` now includes a **Suggested fixes** block with copy/paste commands when it finds dependency, install, config, or stale-state issues.
- `dictate doctor` now validates fixed/tmux mode values and core mode prompt files (`short`/`long`) and reports explicit fallback behavior when invalid.
- `dictate vocab import <file>` now shows line-numbered previews for invalid entries (first 5).
- `dictate vocab dedupe` now creates a timestamped backup before rewriting your vocab file.
- `dictate vocab export <file>` writes a normalized/deduped vocab snapshot you can share or version.
- `dictate bench-matrix [N] [phrase_file]` runs a quick matrix over postprocess/vocab toggles (and LLM models when API key is set) on fixed phrases.
  - Phrase file format: one phrase per line (blank lines and `#` comments ignored). Optional `label<TAB>phrase` is supported.
  - Set `DICTATE_BENCH_MATRIX_PROGRESS=0` for summary-only output (no per-combo progress lines).

## Troubleshooting

Start here:

```bash
dictate debug
dictate doctor
dictate status
```

Common fixes:

- Schema mismatch in `dictate doctor`:
  - `./install.sh --force`
- Invalid fixed mode fallback (`mode.current: <name> (invalid, fallback=short)`):
  - `dictate mode short`
  - or create it: `dictate mode create "<name>"`
- Invalid tmux mode fallback (`tmux.mode: <name> (invalid, fallback=short)`):
  - `dictate tmux mode short`
- Missing core mode prompts:
  - `dictate mode edit short`
  - `dictate mode edit long`
- Vocab import invalid lines:
  - use `wrong::right`, `wrong -> right`, or `wrong → right`
  - export a clean snapshot with `dictate vocab export <file>`

See `docs/TROUBLESHOOTING.md` for a fuller troubleshooting guide.

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

Runtime toggle (without uninstalling plugin file):

```bash
dictate swiftbar        # show ON/OFF
dictate swiftbar off    # keep plugin loaded but show OFF state
dictate swiftbar on
```

## Sounds

Bundled sample sounds live in `assets/sounds/dictate/` and install by default to:

```bash
~/.local/share/sounds/dictate
```

Existing files in that folder are preserved by default (including when using `--force`).
Use `--replace-sounds` only when you explicitly want to overwrite local sound files.

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
dictate bench-matrix 1
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

`dictate doctor` now includes config schema status (`meta.config_version`) and expects an exact schema match for this binary.

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
