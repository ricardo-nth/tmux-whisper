# Dictate CLI - Project Working Agreement

This project is now the single source of truth for Dictate development.

## Source of Truth

- Primary development repo: `/Users/admin/Documents/Projects/dictate-cli`
- Homebrew tap repo: `/Users/admin/Documents/Projects/homebrew-tap`
- Legacy bare repo (`~/.dictate.git`) is retired and archived; do not use it for active development.

## Development Workflow

1. Create a feature branch in `dictate-cli`.
2. Implement changes in this repo only.
3. Run validation:
   - `./tests/ci.sh`
4. Install to local runtime for real usage testing:
   - `./install.sh --force`
5. Merge to `main` only when stable.

## Install Channels

- Daily/personal testing: `./install.sh --force` (or bootstrap installer).
- Public stable installs: Homebrew (`ricardo-nth/tap/dictate-cli`).

Do not require Homebrew for every development iteration.

## Release Workflow

1. Merge stable changes to `main`.
2. Update `CHANGELOG.md` with release-ready notes.
3. Tag release in `dictate-cli` (`vX.Y.Z`).
4. Update Homebrew formula in `homebrew-tap`:
   - `url` to new tag archive
   - `sha256` to matching archive checksum
5. Validate with:
   - `brew update`
   - `brew install/upgrade ricardo-nth/tap/dictate-cli`

## Config and Privacy Boundaries

- Keep repo defaults portable (`config/config.toml`, `config/vocab`).
- Do not commit personal machine-specific preferences or secrets.
- User-local config/runtime stays in:
  - `~/.config/dictate`
  - `~/.local/share/sounds/dictate`
  - `~/.local/share/whisper/models`

## Changelog Policy

- `CHANGELOG.md` should track:
  - current stable version,
  - notable completed changes,
  - upcoming queue/TODO.
- Keep it aligned with actual shipped behavior.
