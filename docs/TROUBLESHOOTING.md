# Troubleshooting

Use this page for quick diagnosis and high-confidence fixes.

## 1) Run the health checks

```bash
dictate debug
dictate doctor
dictate status
```

- `debug`: detailed config/env/path visibility
- `doctor`: install/dependency/mode/runtime checks with suggested fixes
- `status`: current runtime + effective settings snapshot

## 2) Setup and config issues

Schema mismatch:

- Symptom in `dictate doctor`: `config schema: ... status=mismatch`
- Fix:

```bash
./install.sh --force
```

Missing dependencies:

- `python3`, `ffmpeg`, `whisper-cli` are required.
- Typical Homebrew installs:

```bash
brew install python ffmpeg whisper-cpp
```

## 3) Mode configuration issues

Invalid fixed mode fallback:

- Symptom: `mode.current: <name> (invalid, fallback=short)`
- Fix either:
  - reset to built-in mode: `dictate mode short`
  - create missing custom mode: `dictate mode create "<name>"`

Invalid tmux mode fallback:

- Symptom: `tmux.mode: <name> (invalid, fallback=short)`
- Fix:
  - `dictate tmux mode short`

Missing prompt files:

- Symptom: `mode.short.prompt: missing/empty` or `mode.long.prompt: missing/empty`
- Fix:

```bash
dictate mode edit short
dictate mode edit long
```

If both are missing after install drift, refresh defaults:

```bash
./install.sh --force
```

## 4) Vocabulary workflow issues

Accepted correction formats:

- `wrong::right`
- `wrong -> right`
- `wrong → right`

Invalid import lines:

- `dictate vocab import <file>` now reports line numbers for invalid entries (first 5).
- Clean and normalize existing vocab safely:

```bash
dictate vocab dedupe
```

This writes a timestamped backup before rewrite.

Export a clean snapshot for sharing/versioning:

```bash
dictate vocab export <file>
```

## 5) Integration optionality

Dictate remains usable without Raycast/SwiftBar.

- Missing integration scripts appear as warnings in `dictate doctor`, not hard failures.
- Runtime SwiftBar toggle:

```bash
dictate swiftbar        # show state
dictate swiftbar off    # disable SwiftBar runtime integration
dictate swiftbar on
```
