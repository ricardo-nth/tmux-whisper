# Prototype validation — 2026-09-17

Local host: macOS 26.6.2, Apple Silicon, Swift 6.4 Command Line Tools.

## Completed

- `./tests/ci.sh`: passed, including after syncing main's usage implementation.
- `swift run --package-path integrations/native-macos CompanionCoreRegression`:
  passed. Covers status parsing, unknown/malformed/missing fields, safe control
  eligibility, exact command arguments, nonzero exit, timeout, PATH resolution,
  fresh pre-action checks, and version 1 usage parsing.
- `./integrations/native-macos/build.sh`: release build and ad-hoc bundle signing
  passed. `codesign --verify --deep --strict` and plist validation passed.
- Native app launched both directly and through Launch Services against the
  installed CLI. Accessibility inspection reported ready state, Start enabled,
  and Stop/Cancel disabled. The foreground application remained Safari.
- Real native menu screenshot inspected: hierarchy, readable status/control labels,
  native disabled states, and usage section. A menu-bar manager placed the new
  status item off-screen; `--show-menu` presents the menu without changing settings.
- Safe fixture exercised through actual native menu actions: start → recording;
  cancel → ready; start/stop → processing with controls disabled; read error →
  unavailable with controls disabled; refresh → recovery; command failure →
  persistent error and dismiss. No audio capture or paste occurred in these tests.
- Usage updates while the native menu remains open. Read completion uses common
  run-loop modes so menu tracking does not delay state updates.
- Frontend static contract audit: zero findings. This is not visual/accessibility
  proof; native inspection above is separate evidence.

## Limits before replacing SwiftBar or Raycast

- Spoken microphone → transcription → real paste/send has not been exercised from
  this app. Test in a scratch document with the user's intended permission setup,
  paste targets and autosend modes. No daily runtime was installed or changed.
- Full keyboard/VoiceOver, dark/high-contrast display, multi-display positioning,
  simultaneous adapters, permission denial, and day-long polling/CPU tests remain.
- Local ad-hoc signing only; no Developer ID/notarization, distribution installer,
  updater, login item, sandbox or universal binary.
- Status is a snapshot, and the CLI does not expose every asynchronous delivery
  error. CLI cancellation is global; fresh eligibility checks reduce but cannot
  atomically eliminate races with another adapter.
- Usage includes only the CLI's tracked coverage, never a historical backfill.
- Full Xcode's XCTest module was unavailable on this CLT-only machine, so the
  regression suite is a dependency-free Swift executable used by macOS CI too.

## Main sync recheck

Synced with main `78cc5a3` after usage, SwiftBar metrics, release preparation,
and cache/signature fixes merged. Resolved the changelog conflict by retaining
main's release wording unchanged: v0.6.0 remains stable, v0.7.0 is unreleased,
and this native prototype is outside that release scope.

The native regression harness and local signed release build passed again.
The rebuilt app launched against the installed CLI and the actual native menu
showed ready state, Start enabled, Stop/Cancel disabled, and unstarted usage
coverage. Screenshot and accessibility inspection confirmed the menu; the app
was then quit. No new integration risk was observed in this bounded check.
The spoken-delivery, permission, distribution and daily-performance limits above
remain unresolved. No features or daily-runtime changes were made during sync.
