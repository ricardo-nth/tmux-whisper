# Roadmap

This roadmap reflects the current product direction: **tmux-first reliability** for daily terminal work, with inline and integrations as supporting paths.

## Principles

- Keep core behavior stable in tmux-first workflows.
- Improve UX without introducing fragile complexity.
- Ship stable releases via Homebrew; use local/bootstrap installs for active testing.

## v0.4.0 - Public Hardening

Focus: make the public project robust for wider use.

- Harden parity between CLI, Raycast, and SwiftBar behaviors.
- Improve diagnostics (`dictate debug`, `dictate doctor`) for install/path/config issues.
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
- Add stronger config migration/version handling.
- Improve vocab workflows (import/export/normalize safety).
- Refine docs for real-world setup and troubleshooting.

Recent progress (2026-02-19):

- `dictate doctor` now includes mode/config fallback diagnostics plus actionable suggested fixes.
- Vocab safety flow now includes invalid-line previews, guarded dedupe backups, and export snapshots.
- Added dedicated troubleshooting guide: `docs/TROUBLESHOOTING.md`.
- Added runtime SwiftBar integration toggle (`dictate swiftbar on|off|toggle`) so integration can be managed without reinstalling.

Success criteria:

- Fewer setup/support issues caused by config mismatches.
- Predictable behavior after upgrades.

## v0.6.x - Terminal-First UX Layer

Focus: optional richer UX while staying CLI-first.

- Explore TUI path (e.g., Bubble Tea) for status/control flows.
- Keep tmux-first workflow as the primary operating model.
- Ensure TUI complements, not replaces, scriptability.

Success criteria:

- Better discoverability without sacrificing speed for power users.

## v0.7.x - Integration Platform

Focus: integrations as first-class, versioned surfaces.

- Formalize Raycast and SwiftBar integration lifecycle/versioning.
- Add setup/update helpers for integrations.
- Document integration compatibility matrix and support boundaries.

Success criteria:

- Integrations can be updated confidently without core regressions.

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
