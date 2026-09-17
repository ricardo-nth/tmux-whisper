# Native macOS companion — experimental

A local AppKit menu bar prototype for issue #30. It reads the installed
`tmux-whisper status --json` and invokes the existing CLI. AppKit's native
`NSStatusItem`/`NSMenu` keeps the menu from becoming a dictation destination.
Raycast and SwiftBar continue working alongside it.

## Build and run

Requires macOS 13+, Xcode Command Line Tools with Swift 6.0+, and an existing
working Tmux Whisper install. From the repository root:

```sh
swift run --package-path integrations/native-macos CompanionCoreRegression
./integrations/native-macos/run.sh
```

The script builds an ad-hoc signed `.app` inside the ignored `.build` directory
and launches it with your shell environment. Use **Quit companion** to exit.
Pass `--show-menu` to open the menu on-screen after the first status read, even
if a menu-bar manager has hidden its new icon.
To build without launching: `./integrations/native-macos/build.sh`.
Nothing is copied to Applications, installed at login, or changed in CLI config.
Do not run the repository installer just to try this companion.

An absolute `DICTATE_BIN` selects another executable for testing. Otherwise the
companion searches the existing local/Homebrew installation and PATH. It does
not source shell dotfiles; launch from a configured shell if your CLI requires
environment overrides. Finder launches inherit a different environment.

## Controls and boundaries

- **Start inline recording** uses `inline start`.
- **Stop and transcribe** uses `inline stop`; existing paste/autosend settings apply.
- **Cancel recording (discard audio)** uses `cancel`, enabled only for an isolated
  inline recording. The CLI has no flow-specific cancel; concurrent tmux activity,
  processing or stale state disables this control. Use your existing controls in
  those cases. A status recheck reduces races but cannot atomically reserve CLI state.
- Status displays both inline and tmux activity. Tmux control remains with existing
  adapters; this app cannot infer the intended tmux pane.
- Read failures disable controls until a successful refresh. Failed commands are
  shown in the menu. Unknown completion is never automatically retried.
- Quitting does not stop recording or processing.

Usage reads the version 1 `usage --json` contract: delivered dictations, processed
words, and coverage start. Unstarted coverage explicitly says tracking begins with
the next successful delivery. Older dictations are not included. Usage refreshes
independently every 30 seconds (or with Refresh status); failure leaves controls
usable. This prototype calculates no usage totals. There is no global hotkey, notification system, updater, autostart,
or replacement capture/transcription/paste/accounting implementation.

## Packaging and acceptance

The local ad-hoc signature is for experimentation, not public distribution. There
is no Developer ID signing, notarization, sandbox, universal build, or installer.
Microphone/Accessibility/Automation permissions may be attributed differently when
launching the CLI from an app; signing and permission persistence need real-machine
acceptance before distribution. Keep the same local bundle path during testing.

Before replacing either current adapter, verify spoken start/stop/delivery into a
scratch document with your actual permissions, both paste-target policies, autosend
modes, focus changes while processing, concurrent tmux activity, permission denial,
restart/recovery, and CPU/latency over a daily session. Status polling is a snapshot,
not an event stream; the status contract does not expose every background error.

### Reproducible menu preview

Exercise controls without touching your microphone or daily runtime:

```sh
printf '{"state":"ready"}\n' > integrations/native-macos/.build/preview-state.json
DICTATE_BIN="$PWD/integrations/native-macos/Tests/Fixtures/preview-cli.py" \
WHISPER_PREVIEW_STATE_FILE="$PWD/integrations/native-macos/.build/preview-state.json" \
./integrations/native-macos/run.sh
```

Start moves the fixture to recording, stop to processing, and cancel to ready.
Set the JSON state to `ready`, `processing`, `attention`, or `error` to inspect
recovery. `{"state":"ready","fail":true}` exercises command failure. Quit the
preview before launching against your installed CLI again.
