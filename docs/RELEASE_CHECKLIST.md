# Release Checklist

## Pre-release

- [ ] Confirm `main` CI is green.
- [ ] Run local validation:
  - [ ] `./tests/ci.sh`
  - [ ] `./install.sh --force`
  - [ ] `test -f ~/.config/dictate/install-receipt.env`
  - [ ] `tmux-whisper debug`
  - [ ] `tmux-whisper doctor`
- [ ] Confirm changelog is updated (`CHANGELOG.md`).
- [ ] Confirm roadmap alignment (`ROADMAP.md`) if scope changed.

## Tag and Publish

- [ ] Create release tag in `tmux-whisper` (`vX.Y.Z`).
- [ ] Push tag to origin.
- [ ] Verify GitHub tarball URL and checksum:
  - [ ] `tools/update-homebrew-formula.sh vX.Y.Z`
- [ ] Smoke-test pinned bootstrap install from the tag in a temporary `$HOME`:
  - [ ] `DICTATE_BOOTSTRAP_REF=vX.Y.Z bash bootstrap.sh --no-sounds`

## Homebrew Update

- [ ] Update `homebrew-tap/Formula/tmux-whisper.rb` from the tagged tarball:
  - [ ] `tools/update-homebrew-formula.sh vX.Y.Z --write`
  - [ ] Review diff in `../homebrew-tap/Formula/tmux-whisper.rb`
- [ ] Run:
  - [ ] `git -C ../homebrew-tap status --short`
  - [ ] `brew update`
  - [ ] `brew audit --new --strict --online ricardo-nth/tap/tmux-whisper`
  - [ ] `brew install/upgrade ricardo-nth/tap/tmux-whisper`
- [ ] Validate command:
  - [ ] `tmux-whisper --help`
  - [ ] `tmux-whisper debug`
- [ ] Commit/push tap repo update (`../homebrew-tap`) after formula validation passes.

## Post-release

- [ ] Announce release notes summary.
- [ ] Track regressions/issues under next milestone.
