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
- [ ] Verify integration lifecycle and adapter versions on the installed runtime:
  - [ ] `tmux-whisper integrations --json` reports the installed binary/receipt and each Raycast/SwiftBar adapter's source and installed version.
  - [ ] `tmux-whisper integrations doctor` reports no unexpected `missing`, `non-executable`, or `different` adapter state.
  - [ ] `tmux-whisper integrations repair --dry-run` shows the expected adapter-only plan before any repair.
  - [ ] If repair is needed, run `tmux-whisper integrations repair`, then repeat `integrations --json` and `integrations doctor`.
- [ ] Verify delivered-usage accounting:
  - [ ] Record and successfully deliver one inline dictation and one tmux dictation.
  - [ ] Confirm `tmux-whisper usage --json` advances the relevant delivery/word totals without exposing transcript text, and reports its coverage start and typing-time assumption.
- [ ] Verify SwiftBar in the installed environment:
  - [ ] Confirm ready-state usage metrics match `tmux-whisper usage --json` after its normal cache interval.
  - [ ] Watch an inline recording through recording, processing, and ready transitions; confirm the frontmost app is not considered safe to move away from until paste/autosend completes.
  - [ ] Exercise a cancel and a controlled error path; confirm SwiftBar returns to ready rather than retaining a stale recording or processing state.
- [ ] Confirm daily behavior with a real spoken inline delivery and a real spoken tmux delivery. Inline is the primary daily path; tmux remains the pane-targeted asynchronous workflow.

## Tag and Publish

Complete the pre-release checks before this section. Tagging and publication are separate actions from release preparation.

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
