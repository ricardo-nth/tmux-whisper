# Release Checklist

## Pre-release

- [ ] Confirm `main` CI is green.
- [ ] Run local validation:
  - [ ] `./tests/ci.sh`
  - [ ] `./install.sh --force`
  - [ ] `tmux-whisper debug`
  - [ ] `tmux-whisper doctor`
- [ ] Confirm changelog is updated (`CHANGELOG.md`).
- [ ] Confirm roadmap alignment (`ROADMAP.md`) if scope changed.

## Tag and Publish

- [ ] Create release tag in `tmux-whisper` (`vX.Y.Z`).
- [ ] Push tag to origin.
- [ ] Verify GitHub tarball URL and checksum.

## Homebrew Update

- [ ] Update `homebrew-tap/Formula/tmux-whisper.rb`:
  - [ ] `url` -> new tag
  - [ ] `sha256` -> new archive checksum
- [ ] Run:
  - [ ] `brew update`
  - [ ] `brew audit --new --strict --online ricardo-nth/tap/tmux-whisper`
  - [ ] `brew install/upgrade ricardo-nth/tap/tmux-whisper`
- [ ] Validate command:
  - [ ] `tmux-whisper --help`
  - [ ] `tmux-whisper debug`

## Post-release

- [ ] Announce release notes summary.
- [ ] Track regressions/issues under next milestone.
