# Tmux Whisper

Local-first dictation for macOS using a warm Swift/CoreML Parakeet backend by default, with optional LLM cleanup and tmux/desktop integrations.

## Core USP

Tmux Whisper is **tmux-first**.

- Primary workflow: record in a tmux pane, let transcription/process run, and keep working in other panes/windows.
- Inline dictation is supported, but it is a secondary convenience path.
- Design priority is reliability and flow inside terminal/tmux environments over maximum raw transcription speed.

## What You Get

- `bin/tmux-whisper`: main CLI / orchestration layer
- `bin/dictate-lib.sh`: shared helper library used by Tmux Whisper and its integrations
- `tmux-whisperd/`: local Swift daemon package used by the default backend
- `config/`: default config, modes, and vocab
- `integrations/raycast/`: Raycast scripts (`inline`, `toggle`, `cancel`)
- `integrations/tmux-whisper-status.0.2s.sh`: SwiftBar plugin
- `assets/sounds/dictate/`: tiny sample WAV sound pack
- `install.sh`: local installer
- `docs/plans/`: planning/history notes kept separate from active operator docs
- `tests/`: deterministic bash tests and install smoke tests
- `.github/workflows/ci.yml`: CI for syntax + tests

## Requirements

- macOS
- `ffmpeg`
- `python3` (with `tomllib`, Python 3.11+ recommended)
- `swift` + Xcode toolchain (for building the local `tmux-whisperd` backend)
- a local Parakeet model directory, either at `~/.local/share/tmux-whisper/models/...` or via `swift_parakeet.model_path`
- Optional: `tmux`, Raycast, SwiftBar
- Optional for LLM postprocess: `CEREBRAS_API_KEY`

## Install Channels

Choose the channel that matches how you want to use the tool:

### Homebrew stable

Best for daily use when you want tagged releases and the simplest update path.

```bash
brew tap ricardo-nth/tap
brew install ricardo-nth/tap/tmux-whisper
```

Update later with:

```bash
brew upgrade tmux-whisper
```

### Bootstrap from GitHub

Best for testing `main` or pinning a specific release without keeping a local clone.

```bash
curl -fsSL https://raw.githubusercontent.com/ricardo-nth/tmux-whisper/main/bootstrap.sh | bash
```

Pinned to a release tag:

```bash
curl -fsSL https://raw.githubusercontent.com/ricardo-nth/tmux-whisper/v0.6.0/bootstrap.sh | bash
```

Pass bootstrap and install flags explicitly:

```bash
curl -fsSL https://raw.githubusercontent.com/ricardo-nth/tmux-whisper/main/bootstrap.sh | bash -s -- --force --with-sounds
curl -fsSL https://raw.githubusercontent.com/ricardo-nth/tmux-whisper/main/bootstrap.sh | bash -s -- --ref v0.6.0 --force
```

### Local clone / development

Best when this repo is your source of truth and you want fast local iteration.

```bash
git clone https://github.com/ricardo-nth/tmux-whisper.git
cd tmux-whisper
./install.sh
```

Refresh a local clone after pulling new changes:

```bash
git pull
./install.sh --force
```

## Install Notes

The default backend is local `swift_parakeet`.

Preferred Parakeet model home:

- `~/.local/share/tmux-whisper/models/parakeet-tdt-0.6b-v3-coreml`
- `~/.local/share/tmux-whisper/models/parakeet-tdt-0.6b-v2-coreml`

Tmux Whisper expects a Parakeet model to already exist locally in that owned path, or to be pointed at an existing model directory via `swift_parakeet.model_path`. Install does not download model assets for you.

Install behavior:

- Preserves existing config, modes, and vocab by default, including when `--force` is used.
- `--force` refreshes binaries/integrations and seeds missing defaults; it does not replace your live config file.
- Installs Raycast scripts to `~/.config/dictate/integrations/raycast`.
- Installs SwiftBar plugin to `~/.config/swiftbar/plugins/tmux-whisper-status.0.2s.sh`.
- Installs sample sounds to `~/.local/share/sounds/dictate`.
- Runs a best-effort backend warm-up after install/update, including a tiny synthetic prime transcription so the next real dictation is closer to warm.
- Writes an install receipt to `~/.config/dictate/install-receipt.env` with the install source, archive URL when bootstrapped, repo ref/commit when available, and resolved runtime paths.
- Note: config and sounds paths intentionally remain under `dictate` in this phase (`~/.config/dictate`, `~/.local/share/sounds/dictate`).

Useful install flags:

```bash
./install.sh --force            # reinstall scripts and seed missing defaults (preserves local config)
./install.sh --no-sounds        # skip sample sound install
./install.sh --with-sounds      # explicit sound install
./install.sh --replace-sounds   # overwrite existing sound files with bundled samples
```

`bootstrap.sh` downloads a repository archive from GitHub and runs `install.sh` from that archive. Use `--ref <tag-or-commit>` when you want reproducible setup across machines.

## First Run Checklist

Run these once after install or upgrade:

```bash
tmux-whisper debug
tmux-whisper doctor
tmux-whisper status
tmux-whisper warmup
```

Use `tmux-whisper debug` if you are ever unsure which binary/channel you are running. It shows the resolved binary path and install channel.

## Quick Start

```bash
tmux-whisper debug
tmux-whisper            # tmux-first toggle mode
tmux-whisper devices
tmux-whisper inline
tmux-whisper mode auto
tmux-whisper postprocess on
```

### Tmux-first daily loop

- Start from the tmux pane you want to send back into.
- Run `tmux-whisper`, speak, then stop.
- Let processing finish while you keep working in tmux.

If you are not inside tmux, use `tmux-whisper inline` or the Raycast inline integration instead.

## Upgrade and Repair

Daily-use upgrade flow depends on channel:

- Homebrew:
  - `brew upgrade tmux-whisper`
- Bootstrap:
  - rerun the bootstrap command you used before, typically with `--force`
  - for reproducible upgrades, include the same `--ref <tag-or-commit>` on every machine
- Local clone:
  - `git pull`
  - `./install.sh --force`

After any upgrade:

```bash
tmux-whisper doctor
tmux-whisper status
```

If config drift is reported:

```bash
tmux-whisper config repair --dry-run
tmux-whisper config repair
```

### Bench matrix

`tmux-whisper bench-matrix [N] [phrase_file]` runs the cleanup/postprocess pipeline across the in-repo phrase list (or a small file you supply) with the requested number of rounds. Each line in `phrase_file` is trimmed and blank/commented lines (those beginning with `#`) are ignored, so you can customize the set while keeping the defaults for quick comparison. Set `DICTATE_BENCH_MATRIX_MODE` to force which fixed mode (typically `code`) drives the cleanup, postprocess, and vocab helpers. The output table is sorted by postprocess, model, and vocab settings to keep diffs stable, and you still see the warning `postprocess=on combos skipped` if `CEREBRAS_API_KEY` is unset.

## UX Helpers

- `tmux-whisper doctor` now includes a **Suggested fixes** block with copy/paste commands when it finds dependency, install, config, or stale-state issues.
- `tmux-whisper doctor` now validates fixed/tmux mode values and core mode prompt files (`code`/`long`) and reports explicit fallback behavior when invalid.
- `tmux-whisper config defaults` now prints the canonical default config template, and `tmux-whisper config repair [--dry-run]` can safely fill missing defaults, refresh schema version in place, or reset malformed TOML with a backup.
- `tmux-whisper vocab import <file>` now shows line-numbered previews for invalid entries (first 5).
- `tmux-whisper vocab import --dry-run <file>` lets you preview additions before mutating your live vocab.
- `tmux-whisper vocab dedupe` now creates a timestamped backup before rewriting your vocab file.
- `tmux-whisper vocab rm "pattern"` now uses safer literal matching by default, with `--regex` available when you truly want regex behavior.
- `tmux-whisper vocab export <file>` writes a normalized/deduped vocab snapshot you can share or version.
- `tmux-whisper history list [N] --json` now exposes recent dictation summaries as a machine-readable array for shell scripts and future operator tooling.
- `tmux-whisper history search <query> [N] [--json]` turns saved dictations into a searchable operator surface without leaving the CLI.
- `tmux-whisper history export [N|all] [--json]` now exports full history entries for shell pipelines, sharing, and agent/operator replay flows.
- History JSON keeps transcript, word-count, timing, and audio-artifact metadata for stats/roundups; inline debug WAVs are pruned separately with `history.audio_retention_days` / `DICTATE_HISTORY_AUDIO_RETENTION_DAYS` so audio cannot grow forever.
- `tmux-whisper logs path|tail|follow|--json` now gives log inspection both snapshot and live-follow workflows instead of one fixed text dump.
- `tmux-whisper devices --json` now exposes AVFoundation audio devices as structured CLI output for support/debug flows.
- `tmux-whisper config [--json]`, `config path [--json]`, and `config get <path> [--json]` now give config inspection a real read-only operator surface instead of only repair-oriented guidance.
- `tmux-whisper bench [N] --json` now exposes timing summaries as structured data, and `tmux-whisper bench export [N|all] [--json]` exports the raw recent rows behind those summaries.
- `tmux-whisper watch [--interval SECONDS] [--iterations N]` now turns `status` + `last` + `bench` into a text-first live operator overview without committing the project to a TUI.
- `tmux-whisper status --preset compact` and `watch --preset compact` now provide narrower operator snapshots for tighter terminals, quick checks, and future shell/plugin surfaces.
- `tmux-whisper bench-matrix [N] [phrase_file]` runs a quick matrix over postprocess/vocab toggles (and LLM models when API key is set) on fixed phrases.
  - Phrase file format: one phrase per line (blank lines and `#` comments ignored). Optional `label<TAB>phrase` is supported.
  - Set `DICTATE_BENCH_MATRIX_PROGRESS=0` for summary-only output (no per-combo progress lines).
- Stable CLI JSON surfaces are tracked in [`docs/CLI_CONTRACTS.md`](docs/CLI_CONTRACTS.md); prefer those contracts for scripts, agents, SwiftBar/native wrappers, and future UI layers.

## Troubleshooting

Start here:

```bash
tmux-whisper debug
tmux-whisper doctor
tmux-whisper status
```

Common real-world fixes are documented in [docs/TROUBLESHOOTING.md](/Users/admin/Documents/Projects/tmux-whspr/tmux-whisper/docs/TROUBLESHOOTING.md), including:

- install-channel refresh and upgrade drift
- invalid config repair
- tmux vs inline usage errors
- Raycast/SwiftBar environment issues
- vocab and mode recovery flows

## Integrations

### Raycast

Installer-managed Raycast scripts live at:

- `~/.config/dictate/integrations/raycast/tmux-whisper-inline.sh`
- `~/.config/dictate/integrations/raycast/tmux-whisper-toggle.sh`
- `~/.config/dictate/integrations/raycast/tmux-whisper-cancel.sh`

Recommended setup:

- create three Raycast Script Commands that point at those installed files
- use `tmux-whisper-inline.sh` for frontmost-app paste/send
- use `tmux-whisper-toggle.sh` for tmux-first recording from a hotkey
- use `tmux-whisper-cancel.sh` for discard/cancel behavior

### SwiftBar

Installer-managed plugin path:

- `~/.config/swiftbar/plugins/tmux-whisper-status.0.2s.sh`

Runtime toggle (without uninstalling plugin file):

```bash
tmux-whisper swiftbar        # show ON/OFF
tmux-whisper swiftbar off    # keep plugin loaded but show OFF state
tmux-whisper swiftbar on
```

If needed, set `DICTATE_INSTALL_SWIFTBAR=0` to skip plugin install.

### Integration environment note

Raycast and SwiftBar often run with a minimal shell environment. If you rely on `CEREBRAS_API_KEY`, custom PATH entries, or env-based overrides, put them in `~/.zshenv` so the integrations can see them consistently.

### Integration lifecycle checks

`tmux-whisper integrations` inspects the installed adapter surface. For v0.7 integration-platform work, lifecycle checks start with an observable doctor and a dry-run repair preview:

```bash
tmux-whisper integrations doctor
tmux-whisper integrations repair --dry-run
tmux-whisper integrations repair
```

`doctor` checks the installed binary, install receipt, Raycast scripts, SwiftBar plugin, executable bits, and adapter drift from the recorded source tree. `integrations` and `doctor` report each adapter as `current`, `missing`, `non-executable`, or `different` from source so update provenance is visible before repair. `repair --dry-run` shows the adapter-only refresh plan without changing files. `repair` refreshes only the installed Raycast scripts and SwiftBar plugin, creates missing adapter directories, fixes executable bits, and backs up replaced adapter files; use `./install.sh --force` only when you need a full local runtime refresh.

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
tmux-whisper debug
tmux-whisper bench 10
tmux-whisper bench --json
tmux-whisper bench-matrix 1
```

## Repo Layout

- `bin/tmux-whisper` is the main product orchestration layer.
- `tmux-whisperd/` contains the Swift/CoreML daemon package for the Parakeet backend.
- `install.sh`, `config/`, `integrations/`, and `tests/` are active first-class parts of the app, not support-only extras.
- `docs/` keeps active operator docs at the top level, while longer-term planning notes live under `docs/plans/`.

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

`tmux-whisper doctor` now includes config schema status (`meta.config_version`) and expects an exact schema match for this binary.

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
- Existing local config is preserved by default, including when `--force` is used.

## License

MIT
