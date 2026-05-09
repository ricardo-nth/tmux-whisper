# CLI Contracts

Tmux Whisper is CLI-first for operator work. Text output should stay useful for humans, but the `--json` surfaces below are the preferred contract for scripts, agents, SwiftBar/native wrappers, and later UI layers.

## Stable Read Contracts

These commands are safe to build integrations on:

- `tmux-whisper status --json`
  - Object with `command`, `summary`, `runtime`, `effective_settings`, `diagnostics`, and `more_detail`.
  - `summary.next_action` is the primary human next step.
  - `more_detail` is an ordered command list for deeper inspection.
- `tmux-whisper doctor --json`
  - Object with install, config, mode, and runtime health sections plus suggested fixes.
- `tmux-whisper history list [N] --json`
  - Newest-first array of compact history entries.
- `tmux-whisper history search <query> [N] --json`
  - Newest-first array of matching entries with `match_fields`.
- `tmux-whisper history export [N|all] --json`
  - Newest-first array of full history entries.
- `tmux-whisper history sessions [N] --json`
  - Object with `sessions` and `next_commands`.
  - Each session includes app, mode, words, timing metrics, audio artifact metadata, debug notes, and a preview.
- `tmux-whisper last --json`
  - Object with the latest history entry.
- `tmux-whisper logs --json`
- `tmux-whisper logs path|tail [stream] [--lines N] --json`
  - Object with `streams` and `next_commands`.
- `tmux-whisper devices --json`
  - Object with platform, device list, and permission hints.
- `tmux-whisper config --json`
- `tmux-whisper config path --json`
- `tmux-whisper config get <path> --json`
  - Read-only config inspection contracts.
- `tmux-whisper bench [N|all] --json [filters]`
  - Object with record counts, filters, stage summaries, startup summaries, latest row, and `next_commands`.
- `tmux-whisper bench export [N|all] --json [filters]`
  - Newest-first array of raw bench rows.

## Experimental Output

These are useful but not yet promised as stable contracts:

- `tmux-whisper logs follow ... --json`
  - Streaming newline-delimited JSON events. Treat event names as provisional.
- `tmux-whisper watch ...`
  - Human/operator text view composed from stable JSON commands.
- `tmux-whisper bench-matrix ...`
  - Benchmark-oriented text table for local tuning, not an integration API.

## Contract Rules

- Additive JSON fields are allowed.
- Existing field names and broad value types should not change without a changelog note.
- Text output may be refined more freely, but it should keep command cross-links visible where useful.
- Prefer `next_commands` or `more_detail` when a caller needs a recommended follow-up path.
