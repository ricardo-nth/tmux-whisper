# Native companion design

Scope: the experimental `integrations/native-macos` menu only. The CLI, Raycast,
and SwiftBar retain their existing interfaces. Source: issue #30, ROADMAP.md,
and docs/CLI_CONTRACTS.md.

## Intent and ownership

A small macOS utility for existing Tmux Whisper users: see dictation state and
control inline recording without taking focus from the destination app.
AppKit `NSStatusItem` / `NSMenu` owns layout, typography, colors, focus, keyboard
navigation, disabled controls, contrast, and light/dark appearance. Native system
metrics are the runtime token source; no copied web palette or font system.

## Iconography and layout

The signature is a waveform-in-circle menu bar icon. Recording, processing and
attention use distinct SF Symbols and text labels, never color alone. The menu
orders title, live status and guidance, inline controls, refresh, and quit.
Native menu separators group actions. Status/error text wraps into short lines;
full status is available in the icon tooltip. No animation or global hotkeys.

## Behavior

The core library owns JSON decoding and action eligibility. The app controller
owns asynchronous polling, in-flight action exclusion, freshness and visible
errors. Existing CLI commands own capture, transcription, delivery and cleanup.
The app is an accessory and never activates itself or reimplements paste logic.

Start requires ready and idle runtime. Stop applies to an active inline session.
Cancel requires an isolated inline recording because the CLI cancellation command
is global. Each action revalidates status. Unknown/stale/unavailable state disables
controls; Refresh retries reads. Processing is displayed, not cancellable. Quit
closes only the companion and leaves existing dictation running.

## Verification

Swift tests cover state parsing and command policy/execution. Inspect the launched
native menu, disabled/busy/error states, keyboard navigation, and frontmost-app
preservation. Real delivery testing remains necessary before daily replacement.
