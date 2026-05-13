# Roadmap

This roadmap reflects the current product direction: **tmux-first reliability** for daily terminal work, with inline and integrations as supporting paths.

## Principles

- Keep core behavior stable in tmux-first workflows.
- Improve UX without introducing fragile complexity.
- Ship stable releases via Homebrew; use local/bootstrap installs for active testing.

## v0.4.0 - Public Hardening

Focus: make the public project robust for wider use.

- Harden parity between CLI, Raycast, and SwiftBar behaviors.
- Improve diagnostics (`tmux-whisper debug`, `tmux-whisper doctor`) for install/path/config issues.
- Add contributor-facing repo hygiene:
  - `CONTRIBUTING.md`
  - issue templates
  - release checklist
- Reduce logic duplication where practical, especially integration surfaces.

Success criteria:

- No known drift bugs between tmux/inline/integrations over a full release cycle.
- Clean upgrade path for both Homebrew and bootstrap users.

## v0.5.x - UX + Config Maturity (instead of backend expansion)

Focus: make day-to-day usage cleaner and safer.

- Improve mode/config UX and validation.
- Keep public command/help/docs language aligned on `tmux-whisper` while deferring internal `dictate` path/env churn.
- Improve vocab workflows (import/export/normalize safety).
- Refine docs for real-world setup and troubleshooting.

Recent progress (2026-02-19):

- `tmux-whisper doctor` now includes mode/config fallback diagnostics plus actionable suggested fixes.
- `tmux-whisper config defaults` and `config repair [--dry-run]` now provide a forward-safe config migration path, including reset/backup handling for malformed TOML.
- Vocab safety flow now includes invalid-line previews, guarded dedupe backups, and export snapshots.
- Added dedicated troubleshooting guide: `docs/TROUBLESHOOTING.md`.
- Active docs now better reflect real-world use: install channel choice, tmux-first setup, integration env expectations, and upgrade/repair flow.
- Added runtime SwiftBar integration toggle (`tmux-whisper swiftbar on|off|toggle`) so integration can be managed without reinstalling.
- Public-facing command language is now standardized on `tmux-whisper` across the active docs/operator surface, while config/sound paths remain intentionally under `dictate` for now.
- Stale cached AVFoundation audio-index invalidations now leave lightweight breadcrumbs in `debug`, `debug --json`, and active record logs when device-order changes force a re-resolve.
- Bootstrap installs now accept explicit source selectors (`--repo`, `--ref`, `--archive-url`) and write `~/.config/dictate/install-receipt.env`, making multi-machine setup/update provenance easier to verify.

Success criteria:

- Fewer setup/support issues caused by config mismatches.
- Predictable behavior after upgrades.

## v0.6.x - CLI-First Operator Platform

Focus: turn the existing operator summary layer into a first-class terminal product before adding any dashboard/TUI.

- Expand read-only/operator commands so shell users can inspect history, logs, bench data, devices, and config state without scraping human-only output.
- Keep pushing from parity into workflow depth: export/search/follow/watch commands should build on the read-only contracts rather than bypass them.
- Add export-friendly and watch/tail-style workflows that keep tmux/terminal users inside the CLI.
- Use filtered bench inspection and history session summaries as the main reliability investigation surface for FFmpeg drift soak, morning-delay warm-cache behavior, and SwiftBar/sound-start timing.
- Keep tmux-first workflow as the primary operating model.
- Treat any future TUI as a later convenience layer built on stable CLI contracts, not as the next milestone.

Success criteria:

- Common support and inspection tasks are answerable from the CLI alone.
- Read-only operator surfaces have clear text plus machine-readable contracts.
- Future integrations/TUI work can consume stable CLI data instead of re-implementing logic.
- Legacy whisper.cpp decode-default tuning is no longer an active roadmap item; runtime tuning now targets Parakeet warmup/cache/latency behavior.

## v0.7.x - Integration Platform

Focus: integrations as first-class, versioned surfaces.

- Current starting point: `v0.6.0` is stable; v0.7 starts with dry-run lifecycle diagnostics before live adapter repair.
- Formalize Raycast and SwiftBar integration lifecycle/versioning.
- Add setup/update helpers for integrations, beginning with `tmux-whisper integrations doctor` and `tmux-whisper integrations repair --dry-run`.
- Document integration compatibility matrix and support boundaries.

Success criteria:

- Integrations can be updated confidently without core regressions.
- Adapter refresh plans can be inspected safely before they mutate Raycast or SwiftBar files.

## v1.0.0 - Stable Platform Release

Focus: stable command surface and release guarantees.

- Lock core CLI semantics.
- Define support policy (platform, dependencies, upgrade behavior).
- Publish clear stable vs experimental feature boundaries.

Success criteria:

- Users can adopt on stable channels with minimal breaking surprises.

## Post-v1 / Experimental Track

`faster-whisper` is intentionally **not** in the near-term roadmap.

Reasoning:

- Prior attempts were slower or required disproportionate complexity for this project's goals.
- Near-term effort is better spent on reliability and UX of the tmux-first core.

Future options (post-stability):

- Dedicated experimental branch/track for alternate backends.
- Separate sister tool focused on `faster-whisper`/other backend architecture from day one.
