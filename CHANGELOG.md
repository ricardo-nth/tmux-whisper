# Changelog

All notable public-repo changes are documented in this file.

## [Unreleased]

### Added

- `bootstrap.sh` for curl-based installation from GitHub archive.
- `tests/test_bootstrap.sh` smoke test to validate bootstrap flow.

### Changed

- `tests/ci.sh` now validates `bootstrap.sh` and runs bootstrap smoke tests.
- README install section now documents bootstrap and pinned-tag install commands.

## [0.2.0] - 2026-02-18

### Added

- GitHub Actions CI workflow at `.github/workflows/ci.yml`.
- Deterministic test suite:
  - `tests/test_lib.sh` for helper behavior checks.
  - `tests/test_install.sh` for installer smoke tests.
  - `tests/ci.sh` as local/CI check runner.
- Tiny sample sound pack in `assets/sounds/dictate/`.
- `assets/sounds/README.md` with install and usage notes.

### Changed

- `install.sh` now supports:
  - `--with-sounds` / `--no-sounds`
  - `--force` with backup behavior
  - help output (`--help`)
- Default sound paths in `config/config.toml` now target `~/.local/share/sounds/dictate/*.wav`.
- README rewritten for production usage (install, integrations, dev workflow, CI).

## [0.1.0] - 2026-02-18

### Added

- Initial public packaging of Dictate CLI:
  - Main CLI and shared library in `bin/`
  - Default config and modes in `config/`
  - Raycast and SwiftBar integrations in `integrations/`
  - Installer script (`install.sh`)
  - MIT license and repository docs
