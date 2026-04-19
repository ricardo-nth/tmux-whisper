# Troubleshooting

Use this page for quick diagnosis and high-confidence fixes.

## 1) Run the health checks

```bash
tmux-whisper debug
tmux-whisper doctor
tmux-whisper status
```

- `debug`: detailed config/env/path visibility
- `doctor`: install/dependency/mode/runtime checks with suggested fixes
- `status`: current runtime + effective settings snapshot

## 2) Setup and config issues

Schema mismatch:

- Symptom in `tmux-whisper doctor`: `config schema: ... status=mismatch`
- Fix:

```bash
tmux-whisper config repair --dry-run
tmux-whisper config repair
```

Invalid TOML:

- Symptoms:
  - `tmux-whisper doctor`: `config schema: invalid`
  - `tmux-whisper status`: `headline: Config file is invalid TOML.`
- Fix:

```bash
tmux-whisper config repair --dry-run
tmux-whisper config repair
```

Missing dependencies:

- `python3` and `ffmpeg` are required.
- `swift` is required when the local `tmux-whisperd` binary needs to be built or rebuilt.
- Typical Homebrew installs:

```bash
brew install python ffmpeg
```

Parakeet backend unavailable:

- Symptoms in `tmux-whisper doctor`:
  - `tmux-whisperd binary: ... (build needed)`
  - `tmux-whisperd socket: ... (offline)`
  - `parakeet model: missing`
- Fix:
  - run `./install.sh --force`
  - run `tmux-whisper warmup`
  - verify `swift_parakeet.model_path` in `~/.config/dictate/config.toml`
  - ensure `swift` is installed if the native backend needs to rebuild

## 3) Mode configuration issues

Invalid fixed mode fallback:

- Symptom: `mode.current: <name> (invalid, fallback=auto)`
- Fix either:
  - reset to auto-detect: `tmux-whisper mode auto`
  - create missing custom mode: `tmux-whisper mode create "<name>"`

Invalid tmux mode fallback:

- Symptom: `tmux.mode: <name> (invalid, fallback=code)`
- Fix:
  - `tmux-whisper tmux mode code`

Missing prompt files:

- Symptom: `mode.code.prompt: missing/empty` or `mode.long.prompt: missing/empty`
- Fix:

```bash
tmux-whisper mode edit code
tmux-whisper mode edit long
```

If both are missing after install drift, reinstall and seed missing defaults:

```bash
./install.sh --force
```

## 4) Vocabulary workflow issues

Accepted correction formats:

- `wrong::right`
- `wrong -> right`
- `wrong → right`

Invalid import lines:

- `tmux-whisper vocab import <file>` now reports line numbers for invalid entries (first 5).
- Preview a batch without mutating your live vocab:

```bash
tmux-whisper vocab import --dry-run <file>
```

- Clean and normalize existing vocab safely:

```bash
tmux-whisper vocab dedupe
```

This writes a timestamped backup before rewrite.

Export a clean snapshot for sharing/versioning:

```bash
tmux-whisper vocab export <file>
```

Remove entries safely:

```bash
tmux-whisper vocab rm "literal text"
tmux-whisper vocab rm --regex "pattern"
```

## 5) Integration optionality

Tmux Whisper remains usable without Raycast/SwiftBar.

- Missing integration scripts appear as warnings in `tmux-whisper doctor`, not hard failures.
- Runtime SwiftBar toggle:

```bash
tmux-whisper swiftbar        # show state
tmux-whisper swiftbar off    # disable SwiftBar runtime integration
tmux-whisper swiftbar on
```
