# Domain Docs

How the engineering skills should consume this repo's domain documentation when exploring the codebase.

## Before exploring, read these

- `CONTEXT.md` at the repo root, if it exists.
- `CONTEXT-MAP.md` at the repo root, if it exists.
- `docs/adr/`, if it exists.

If these files do not exist, proceed silently. Do not flag their absence or suggest creating them up front.

## Layout

This is a single-context repo. Tmux Whisper is a macOS-first, tmux-first dictation CLI with Raycast and SwiftBar integrations as adapter surfaces around the CLI/runtime.

Use the repo's established terms:

- `tmux-whisper` for the public command.
- `dictate` only for legacy config, state, temp, and user-local runtime paths that intentionally still use that name.
- `inline` for frontmost-app paste/send dictation.
- `tmux` for pane-targeted dictation.
- `SwiftBar plugin` and `Raycast scripts` for integration adapters.
- `processing markers`, `state files`, and `install receipt` for runtime/integration observability.

## ADRs

If future ADRs are added under `docs/adr/`, read the ones that touch the area being changed. Surface any conflict explicitly rather than silently overriding it.
