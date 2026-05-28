# Tmux Whisper changelog

## Current working version

- **Stable release**: `v0.6.0` (tagged on 2026-05-13; Homebrew formula updated)
- **Active development track**: `v0.7.x` (integration platform)
- **Completed**: FFmpeg AVFoundation capture now uses async resampling so WAV duration tracks wall-clock recording time instead of drifting short
- **Completed**: Swift tail rescue now re-transcribes the final seconds of longer WAVs and merges that text back into the full-file transcript, fixing cases where Parakeet's full-file pass omits words that are present in the recorded WAV
- **Completed**: Swift audio chunking is now opt-in via `DICTATE_SWIFT_PARAKEET_CHUNKING=1` instead of default, keeping the stable single-pass path for daily dictation
- **Watch**: treat Swift chunking as quarantined experimental code; if tail rescue solves the observed clipping without a clear long-audio need for chunking, remove the chunking path rather than carrying a dormant complexity branch
- **Completed**: experimental Swift chunking skips sub-1s tail fragments instead of asking the daemon to transcribe invalid audio
- **Completed**: inline/Raycast FFmpeg shutdown now sends a controlled `q` over a private FIFO before falling back to SIGINT, preserving most of the stop-grace tail that SIGINT was dropping
- **Completed**: trailing-word clipping hardening in the stop/transcribe path
- **Completed**: inline/Raycast stop breadcrumbs when `keep_logs` is enabled
- **Completed**: FFmpeg capture/shutdown diagnostics now archive WAV duration, byte counts, grace timing, and SIGINT/TERM exit timing for clipped-run forensics
- **Completed**: inline/Raycast processing cue now plays immediately on stop, before the grace window finishes recording
- **Completed**: inline `keep_logs` now archives per-run WAV + record/transcribe logs under `history/inline-debug` for clipped-run forensics
- **Completed**: history now records inline audio artifact metadata while pruning archived debug WAVs after `history.audio_retention_days`, keeping stats/roundup inputs without unbounded audio growth
- **Completed**: `whisper.cpp` removal; runtime, config, and operator docs are now Parakeet-only
- **Completed**: operator CLI foundation for `status`, `debug`, `doctor`, `history`, and `last` with machine-readable JSON output
- **Completed**: richer operator summaries for runtime state and recent history; these now become the base layer for a CLI-first operator expansion rather than a near-term dashboard/TUI
- **Completed**: `tmux-whisper history list [N] --json` now exposes recent dictation summaries as machine-readable arrays, seeding the next operator-grade CLI layer
- **Completed**: `tmux-whisper history search <query> [N] [--json]` now turns saved dictation history into a usable lookup surface for operators and agents
- **Completed**: `tmux-whisper history export [N|all] [--json]` now exports full recent/history entries for shell pipelines, handoff artifacts, and agent-readable replay/debug flows
- **Completed**: `tmux-whisper bench [N] --json` and `bench export [N|all] [--json]` now give operator timing data both summary-level JSON and full-row export paths instead of one text-only view
- **Completed**: `tmux-whisper logs` now has proper CLI subcommands for `path`, `tail`, `follow`, and `--json`, so log inspection no longer depends on scraping one fixed human-only dump
- **Completed**: `tmux-whisper devices --json` now turns AVFoundation device enumeration into a machine-readable support/debug surface instead of a text-only listing
- **Completed**: `tmux-whisper config [--json]`, `config path [--json]`, and `config get <path> [--json]` now make config inspection first-class for humans, shell tooling, and future agents
- **Completed**: `tmux-whisper watch [--interval SECONDS] [--iterations N]` now composes `status`, latest history, and bench data into a live text-first operator view instead of forcing a dashboard/TUI jump
- **Completed**: `tmux-whisper status --preset compact` and `watch --preset compact` now give terminal operators a tighter summary surface for narrow panes, quick checks, and future plugin-style shells without changing the JSON contracts underneath
- **Completed**: filtered bench inspection, history session summaries, and command cross-links now connect `bench`, `history sessions`, `logs`, `status`, and `watch` into a more navigable operator workflow
- **Completed**: `docs/CLI_CONTRACTS.md` now marks stable JSON read surfaces versus experimental streaming/watch/benchmark output so future wrappers can build on the CLI without guessing
- **Completed**: mode/config UX validation polish in `tmux-whisper doctor`, including flow-aware checks, surgical fix hints, and text/JSON parity
- **Completed**: public command/help/docs now standardize on `tmux-whisper ...`; internal `dictate` config/temp paths remain intentionally unchanged for now
- **Completed**: vocab safety follow-up now adds dry-run import paths plus backup/literal-match guardrails for vocab import and removal flows
- **Completed**: config repair flow now provides canonical `config defaults`, in-place `config repair [--dry-run]`, and install-time seeding from one default template
- **Completed**: malformed `config.toml` now degrades into explicit `debug`/`doctor`/`status` warnings, and `config repair` can reset invalid TOML safely with a backup
- **Completed**: real-world docs refresh now clarifies install channels, tmux-first setup, integration environment expectations, and channel-specific upgrade/repair flows
- **Completed**: bootstrap/install reproducibility pass now supports explicit bootstrap `--ref`, `--repo`, and `--archive-url` flags, records the installed source in `install-receipt.env`, and documents pinned setup across machines
- **Completed**: stale cached AVFoundation audio-index invalidations now leave lightweight breadcrumbs in `debug`, `debug --json`, and active record logs when device order changes force a re-resolve
- **Completed**: inline/Raycast fresh audio-cache hits now use a lighter mtime-based fast path and refresh cache timestamps in the background, reducing rare hotkey-to-start-cue stalls
- **Completed**: SwiftBar inline processing now stays active until transcription, paste, and optional autosend finish, so the menu-bar state reflects when the frontmost window is safe to move away from
- **Completed**: internal architecture deepening extracted config snapshots, audio source resolution, mode policy, and recording helpers into `bin/tmux-whisper-lib/` modules instead of keeping those seams embedded in the main CLI
- **Completed**: SwiftBar now consumes the shared mode policy module for mode names, flow allowance, and app-driven inline mode detection instead of mirroring the same rules locally
- **Completed**: `tmux-whisper integrations [--json]` now inspects the installed binary, install receipt, SwiftBar plugin, and Raycast scripts as a first integration-adapter status surface
- **Completed**: `tmux-whisper integrations repair` now applies an adapter-only Raycast/SwiftBar refresh with missing-directory creation, executable-bit repair, changed-file reporting, and backups for replaced adapter files, while `repair --dry-run` remains non-mutating
- **Completed**: integration status/doctor now reports per-adapter source provenance states (`current`, `missing`, `non-executable`, or `different`) for Raycast scripts and the SwiftBar plugin before any SwiftBar behavior changes
- **Completed**: SwiftBar state reliability now uses a shared best-effort `tmux-whisper swiftbar refresh` surface from CLI lifecycle paths and Raycast wrappers, refreshes recording/processing/cancel/error transitions, and prunes stale recording or processing markers so the menu falls back to polling without getting stuck
- **Completed**: Raycast and SwiftBar adapter files now carry explicit adapter-version metadata, and `tmux-whisper integrations --json` plus doctor/status output report installed/source versions for faster lifecycle review
- **Primary development branch**: `main` in `ricardo-nth/tmux-whisper`
- **Distribution channels**:
  - Homebrew (stable): `brew install ricardo-nth/tap/tmux-whisper`
  - Bootstrap/local install (testing): `bootstrap.sh` or `./install.sh --force`

### Residual v0.6 polish only (after the stable cut, if still needed)

- keep the operator CLI as the primary support surface: inspect reliability from `status`, `history sessions`, `bench`, and `logs` before adding any new UI layer
- keep filtered bench inspection, history session summaries, and compact/watch/log workflows evolving from real usage rather than opening a dashboard/TUI track
- if any CLI-first polish remains after the stable cut, keep it small and evidence-led so it does not blur into v0.7 integration work

### Planned next (v0.7 integration platform)

- begin v0.7 from a dedicated integration-platform branch now that `v0.6.0` is tagged and the Homebrew formula is updated
- keep proving `tmux-whisper integrations doctor`, `repair --dry-run`, and adapter-only `repair` in daily use before widening lifecycle actions
- extend `tmux-whisper integrations [--json]` from inspection/provenance into broader install/update actions only after the current repair lifecycle is proven
- add integration setup/update helpers that can verify or reinstall Raycast scripts and SwiftBar plugin files without forcing a full app reinstall
- explore the native macOS companion path separately from the CLI: lightweight menu-bar app, push-style state updates, and later Swift/Core Audio capture options
- document integration compatibility and support boundaries: supported macOS assumptions, required PATH/env behavior, Homebrew vs bootstrap/local differences, and stable vs experimental integration surfaces

## 2026-05-09

- **Inline/Raycast clipping hardening**:
  - Added async FFmpeg resampling (`aresample=async=1000:first_pts=0`) to tmux and inline capture so AVFoundation sample-clock drift does not produce short WAVs before transcription.
  - Retuned the inline stop grace window back down to `1000ms` as a diagnostic probe after capture drift was isolated; later tail-slice evidence showed clipped words were present in the WAV but missing from Parakeet's full-file transcript.
- **Validation**:
  - Ran `bash -n`, `./tests/test_cli.sh`, `./tests/test_regression.sh`, `./tests/test_flow_parity.sh`, `./tests/ci.sh`, `./install.sh --force`, and a fixed-duration FFmpeg probe that produced a `15.000s` WAV from a `15s` capture.

## 2026-04-19

- **Inline/Raycast clipping hardening**:
  - Retuned the inline stop grace window back to `1250ms` as a diagnostic probe now that FFmpeg capture/shutdown breadcrumbs are archived for clipped-run analysis.
  - Added FFmpeg capture/shutdown breadcrumbs so clipped inline runs can distinguish early capture gaps, already-dead FFmpeg processes, slow SIGINT exits, and post-transcription WAV mutation.
  - Retuned the inline stop grace window to `1000ms` so Raycast stop feels snappier while still buffering trailing words better than the original baseline.
  - Moved the inline processing cue to fire immediately on stop, so the sound matches the hotkey action instead of waiting for the grace window to finish.
  - Added per-run inline `keep_logs` archiving under `history/inline-debug` so rare clipped runs preserve the WAV, stop log, transcribe log, and timing metadata for inspection.
  - Documented rare tail clipping as an active optimization area rather than a release blocker; the current release prioritizes a strong default UX with observability for future tuning.
- **Validation**:
  - Ran `./tests/test_cli.sh`, `./tests/test_regression.sh`, `./tests/test_flow_parity.sh`, and `./tests/ci.sh`.
- **Audio-device cache observability**:
  - Added a lightweight stale-cache note when a cached AVFoundation audio index is invalidated and re-resolved after device-order changes.
  - Surfaced that note in `tmux-whisper debug`, `debug --json`, and the active tmux/inline record logs so device drift is easier to diagnose without adding noise to normal status output.

## 2026-04-18

- **Stability (dictation clipping)**:
  - Increased the default stop grace window from `250ms` to `400ms` so hotkey stop is less likely to cut off trailing speech.
  - Added a small transcription tail pad (`DICTATE_TRANSCRIBE_TAIL_PAD_MS`, default `250ms`) so ASR sees a clean utterance boundary before decoding.
  - Verified the latest clipped real-world entry was truncating in saved `raw` history before paste, and fixed the upstream record/transcribe boundary rather than only the paste path.
- **Validation**:
  - Added regression coverage for the new tail-pad ffmpeg path in flow parity tests.
  - Ran `./tests/test_cli.sh`, `./tests/test_flow_parity.sh`, `./tests/test_regression.sh`, and `./tests/ci.sh`.
- **Test isolation**:
  - Updated the SwiftBar status plugin to respect env-overridden runtime state paths so local regression runs stay hermetic on machines with real active dictation state.

## 2026-02-19

- **UX polish (`dictate doctor`)**:
  - Added a `Suggested fixes` section with actionable commands for common failures/warnings (missing deps, install/config issues, schema mismatch, stale state/processing markers, optional tmux install).
  - Added mode/config validation checks for invalid fixed/tmux modes and missing core prompts (`short`/`long`) with explicit fallback behavior and fix commands.
  - Kept diagnostics concise while making next-step remediation copy/paste friendly.
- **Vocab safety pass**:
  - Added `dictate vocab export <file>` to write a normalized + deduped snapshot for sharing/versioning.
  - `dictate vocab import` and `dictate vocab clipboard` now preview invalid entries with line numbers (first 5) instead of only showing counts.
  - `dictate vocab dedupe` now creates a timestamped backup before rewriting and reports duplicate/invalid removals.
  - `dictate vocab` normalization now also accepts ASCII arrow format (`wrong -> right`) in addition to `wrong::right` and `wrong → right`.
- **Validation**:
  - Expanded regression coverage for doctor suggestions and vocab import/export/dedupe safety behavior.
- **Docs refresh**:
  - Added troubleshooting-focused UX guidance in README.
  - Added `docs/TROUBLESHOOTING.md` with setup/mode/vocab recovery flows.
- **SwiftBar runtime toggle**:
  - Added `dictate swiftbar [show|on|off|toggle]` to control SwiftBar integration at runtime (without reinstall/uninstall).
  - SwiftBar plugin now respects `integrations.swiftbar.enabled` and shows a compact OFF state with one-click re-enable.
  - `dictate doctor` now reports SwiftBar plugin presence together with enabled/disabled state.
- **Bench matrix helper**:
  - Added `dictate bench-matrix [N] [phrase_file]` to compare postprocess/vocab-clean combinations on fixed phrases.
  - When `CEREBRAS_API_KEY` is set, bench-matrix also expands postprocess-on runs across configured LLM model candidates.
  - Bench-matrix now supports optional `label<TAB>phrase` phrase-file lines and a quiet mode (`DICTATE_BENCH_MATRIX_PROGRESS=0`) for summary-only output.
  - Added regression coverage for bench-matrix usage validation and no-key smoke behavior.

## 2026-02-18

- **v0.5.x cleanup (forward-only schema checks)**:
  - Simplified config schema diagnostics to `ok|mismatch` (removed legacy/future/unknown branching).
  - `dictate doctor` now treats schema mismatch as a hard issue with a single upgrade path (`./install.sh --force`).
  - Updated regression coverage and README wording to match strict schema matching behavior.

## 2026-02-18

- **v0.5.x groundwork (config maturity)**:
  - Added explicit config schema tracking via `meta.config_version` in default config.
  - `dictate debug` now prints config schema version/status against the expected schema.
  - `dictate doctor` added schema diagnostics as groundwork (later tightened to strict exact-match checks in the cleanup entry above).
  - Added regression coverage to prevent schema-status diagnostics from regressing.

## 2026-02-18

- **Release hardening follow-up (CI portability + local test hygiene)**:
  - Installer safety: `--force` no longer overwrites existing sound files; use new `--replace-sounds` when explicit sound replacement is desired.
  - Fixed Linux CI/runtime compatibility for state-file mtime handling in `dictate status`/`dictate doctor` by adding portable `stat` fallbacks.
  - Ensured diagnostics paths (`dictate debug`/`dictate status`) degrade gracefully when `ffmpeg` is unavailable instead of hard-exiting.
  - Updated regression harness to stub `osascript` in missing-binary checks so local test runs do not emit real macOS notifications.

## 2026-02-18

- **Hardening (phase 1)**:
  - Added stronger install/path diagnostics in `dictate debug` and `dictate doctor`:
    - install channel detection (`homebrew` vs `local-user` vs `custom`)
    - binary/lib/config/integration path sanity output
    - dependency checks and model-directory health checks
    - no hard failure in `dictate debug` when `ffmpeg` is missing
  - Added contribution/release governance artifacts:
    - `CONTRIBUTING.md`
    - `.github/ISSUE_TEMPLATE/*`
    - `docs/RELEASE_CHECKLIST.md`
  - Added hardening regression coverage:
    - `tests/test_regression.sh` for install-channel detection and integration path-resolution guards.
    - `tests/test_flow_parity.sh` for deterministic tmux/inline flow parity:
      - tmux start/stop queue lifecycle + send-mode behavior (`enter` vs `codex`)
      - inline autosend key paths (`ctrl_j`, `cmd_enter`)
      - vocab-only cleanup parity in inline mode
      - status/runtime parity for postprocess-no-key and mode/model env overrides
  - Integration hardening (Raycast/SwiftBar):
    - Broadened integration PATH fallbacks to include user-local + Homebrew + `/usr/local/bin`.
    - Raycast toggle now fails fast with explicit notifications when `dictate` or `tmux` is missing.
    - Raycast inline now fails fast with explicit notifications when `dictate-lib.sh`, `ffmpeg`, or `whisper-cli` is missing.
    - SwiftBar now shows a clear `Dictate binary not found` status instead of silent broken menu commands.

## 2026-02-18

- **New (public packaging + distribution)**:
  - Published public source repo: `ricardo-nth/dictate-cli`.
  - Added bootstrap install flow (`bootstrap.sh`) and CI smoke test coverage.
  - Added Homebrew distribution via `ricardo-nth/homebrew-tap` (`brew install ricardo-nth/tap/dictate-cli`).
- **Improved (packaging compatibility)**:
  - Updated runtime path resolution so `dictate`, Raycast, and SwiftBar scripts can resolve binaries/libs from PATH (not only `~/.local/bin`), enabling cleaner Homebrew installs.

## 2026-02-18

- **New (source-aware microphone selection)**:
  - Added `audio.source` strategy (`auto|external|mac|iphone|name`) with env override `DICTATE_AUDIO_SOURCE`.
  - `auto` now prefers `external -> mac -> iphone`, so unplug/replug workflows no longer require manual flips between external and built-in mics.
  - Added source hints in config: `audio.mac_name` and `audio.iphone_name`.
  - Added CLI controls:
    - `dictate device source <auto|external|mac|iphone|name>`
    - `dictate device external|mac|iphone`
    - `dictate device mac-name "<substring>"`
    - `dictate device iphone-name "<substring>"`
- **Improved (iPhone/Continuity detection)**:
  - Audio device classification now uses AVFoundation continuity heuristics (including Desk View camera pairings), so custom iPhone names like `"... Microphone"` can still be treated as iPhone source.
- **Improved (SwiftBar mic controls)**:
  - SwiftBar now shows configured mic source + last active resolved mic in the ready state.
  - Added a top-level **Mic src** menu to switch source strategy directly (`auto`, `external`, `mac`, `iphone`).
- **Fixed (SwiftBar advanced menu nesting)**:
  - Restored proper dropdown nesting for **Repeats level** and **Send mode** while keeping the advanced section compact.
- **Improved (Raycast parity)**:
  - Raycast inline now uses the same source-aware resolver as main CLI, including source key caching and fallback-index behavior when detection misses.

## 2026-02-07

- **Changed (tmux autosend simplification)**:
  - `tmux.send_mode` surface is now `auto | enter | codex`.
  - `auto` now only detects Codex and otherwise sends Enter.
  - Enter-only send path is verified stable in live use across both major terminal assistants.
  - `codex` remains available for explicit `Tab+Enter`, but there is a high chance this option can be removed soon.
  - If retained, `codex` may be renamed to a clearer `tab+enter` style label.
  - Tmux paste continues using bracketed paste when available (`paste-buffer -p`) and preserves LFs (`-r`).
  - `DICTATE_TMUX_SEND_KEY` remains deprecated; tmux send behavior is controlled by `tmux.send_mode` only.
- **Fixed (tmux pane targeting across multiple terminal windows)**:
  - Origin/current pane resolution now prefers the invoking shell pane (`TMUX_PANE`) instead of ambiguous client context.
  - Added pane-existence validation before paste/send with safe fallback to current invoking pane when the stored target no longer exists.
  - Known caveat: with multiple Ghostty windows attached to tmux, client focus can still lag until a pane is hard-focused; verify the start modal pane label and cancel/restart if needed.
- **Improved (postprocess fast path)**:
  - When postprocess is enabled, silence trim and repeat cleanup are now skipped by default in inline/tmux/Raycast paths (for faster stop->send).
  - Added opt-in env overrides to keep them active with postprocess:
    - `DICTATE_TRIM_WITH_POSTPROCESS=1`
    - `DICTATE_REPEATS_WITH_POSTPROCESS=1`
- **Improved (inline stop latency)**:
  - Inline autosend now uses a lower default `Cmd+V -> Enter` delay when target is `current` (20ms default; configurable via `DICTATE_INLINE_SEND_DELAY_MS`).
  - Inline history writes are now deferred asynchronously after successful paste/send, reducing user-visible stop latency in both CLI inline and Raycast inline flows.
- **New (inline autosend key strategy)**:
  - Added inline send mode controls for non-tmux flows:
    - `dictate send-mode enter|ctrl_j|cmd_enter`
    - env override: `DICTATE_INLINE_SEND_MODE=enter|ctrl_j|cmd_enter`
  - Wired into both main CLI inline and Raycast inline send paths (`Cmd+V` + configured send key), so Claude Code can use `ctrl_j` while Codex can stay on `enter`.
- **Fixed (inline autosend dispatch reliability)**:
  - Inline autosend now dispatches paste and send as two separate AppleScript events (`Cmd+V`, delay, then send key) instead of a single combined AppleScript block.
  - Reverted the `target=current` 20ms fast-path default back to the safer baseline delay behavior (configurable via `DICTATE_INLINE_SEND_DELAY_MS`).
  - Rationale: in Claude Code, tightly batched paste+Enter could be interpreted as newline/not-submit; split dispatch is more reliable.
- **Fixed (postprocess parity in metrics)**:
  - Main CLI tmux/inline paths now only mark postprocess as active when `CEREBRAS_API_KEY` is actually available (matching Raycast inline behavior), preventing misleadingly fast “postprocess ON” timings when API processing is effectively skipped.
  - Main CLI inline path now reuses the already-detected mode when invoking postprocess, avoiding a duplicate mode-detection pass.
  - `dictate status` now reports effective postprocess runtime state (and explicit note when disabled due to missing API key).
  - SwiftBar postprocess labels now show effective runtime state and display `OFF (no key)` when config is on but API key is unavailable in plugin environment.
- **Fixed (tmux postprocess precedence)**:
  - `tmux` runtime postprocess now resolves from `DICTATE_TMUX_POSTPROCESS -> tmux.postprocess -> postprocess.enabled` and no longer allows global `DICTATE_POSTPROCESS` to silently disable tmux cleanup.
  - `dictate status` now uses the same tmux postprocess resolver as the tmux stop path, so status and bench behavior stay aligned.
- **Fixed (Raycast tmux key loading)**:
  - `integrations/raycast/dictate-toggle.sh` now loads `CEREBRAS_API_KEY` from `.zshrc` (when missing), matching inline/SwiftBar behavior.
  - This prevents tmux runs started from Raycast from unexpectedly skipping postprocess (`post=0`) when the key is defined only in interactive shell config.
- **New (vocab-only cleanup path)**:
  - Added deterministic vocab correction pass for non-LLM runs in shared library (`dictate-lib.sh`) and wired it into main CLI tmux/inline + Raycast inline flows.
  - When postprocess is OFF, Dictate now applies global vocab + mode vocab corrections before final output.
  - Added env override `DICTATE_VOCAB_CLEAN=0|1` (default `1`) to disable/enable this non-LLM vocab pass.
- **Fixed (vocab add exit status)**:
  - `dictate vocab add` now returns success (`0`) when entries are added or already exist as duplicates, so shells/prompts no longer show a false error state after successful runs.
- **Improved (startup readiness)**:
  - Main CLI now caches resolved audio index in `~/.config/dictate/.cache/audio-index.sh` (same pattern as Raycast), reducing repeated device-scan cost.
  - Added one-shot stale-cache retry before failing tmux recording start.
  - `bench.tsv` now includes startup columns (`startup_total/audio/ffmpeg_live/target/audio_source`) for tmux/inline/Raycast flows.
  - `dictate bench` now prints a **Startup readiness** section with medians/p90/max.
- **Improved (inline modular targeting + speed)**:
  - Inline target now supports `origin` as a first-class alias of `restore` (`dictate target origin|current`; `restore` still accepted).
  - Added `DICTATE_INLINE_PASTE_TARGET=origin|current` env override for quick A/B behavior switching.
  - Raycast inline now skips target app/window/PID capture when target is `current`, reducing startup work on the fast path.
  - Raycast state now persists inline paste target so stop-time behavior matches start-time mode.
  - Inline paste/send path now uses lower default delays (`activate=90ms`, `send=35ms`) and combines paste+Enter into one AppleScript call when autosend is on.
  - Raycast stop path now polls for ffmpeg exit instead of sleeping a fixed 300ms before transcription.
- **Improved (SwiftBar wording clarity)**:
  - Renamed **Advanced → Tmux → Claude as Codex** to **Claude Enter-only (auto)** to match actual behavior and reduce confusion.
  - Consolidated tmux send controls under **Advanced → Tmux → Send mode** with explicit options: `auto`, `enter`, `codex`.

## 2026-02-06

- **Fixed (transcript artefacts)**: Strip placeholder tokens like `[blank audio]`/`[blank_audio]` from transcripts before post-processing/output (main script + Raycast inline), so they aren’t pasted or saved in history.
- **Improved (short mode readability)**: Tightened `modes/short/prompt` to explicitly split longer outputs (~80+ words) into multiple paragraphs at natural boundaries, while still preserving wording and avoiding list conversion.
- **Improved (tmux autosend reliability)**: Added a short configurable delay between `tmux paste-buffer` and autosend key dispatch to reduce occasional missed submits in chat panes.
- **Improved (Codex detection)**: Autosend now detects Codex via both `#{pane_current_command}` and child process command (from `#{pane_pid}`), so pane metadata quirks are less likely to break Codex-specific `Tab + Enter`.
- **New (tmux autosend tuning env vars)**:
  - `DICTATE_TMUX_SEND_MODE=auto|enter|codex` (default: `auto`)
  - `DICTATE_TMUX_SEND_DELAY_MS` (default: `90`)
  - `DICTATE_TMUX_CODEX_TAB_DELAY_MS` (default: `35`)
  - `DICTATE_TMUX_CLAUDE_TAB_ENTER=1` (optional, off by default)
- **New (debug)**: When `DICTATE_KEEP_LOGS=1`, transcribe log includes autosend decision details (`pane`, `mode`, `pane_cmd`, `child_cmd`).
- **New (doctor)**: Added `dictate doctor` for a concise health summary (state files, processing markers, tmux queue, and recent logs).
- **New (cleanup controls)**:
  - `dictate silence-trim on|off|toggle|show`
  - `dictate repeats 0|1|2|toggle|show`
- **Improved (SwiftBar controls)**: Added inline settings for silence trim and repeats level.
- **Improved (tmux target visibility)**: SwiftBar recording state now includes pane id + title + path for tmux target panes.
- **Refactor (shared helpers)**: Added `~/.local/bin/dictate-lib.sh` and moved shared text/model/backend/audio-index helpers out of both main CLI and Raycast inline script.
- **New (tmux process sound control)**:
  - `tmux.process_sound` config key (default: `false`)
  - `DICTATE_TMUX_PROCESS_SOUND=1` env override
  - `dictate tmux process-sound on|off`
  - SwiftBar toggle under **Tmux → Settings**
- **Improved (tmux pane context in CLI)**: `dictate` tmux start/stop/status output now includes pane id + title + path where available (not just `%pane`).
- **Changed (model menu simplification)**: Whisper model selectors are now focused on `base`, `small`, and `turbo` in CLI + SwiftBar.
- **Changed (mode naming)**: Inline/tmux mode UX now uses `short` + `long` instead of `code` + `prose` in CLI output, SwiftBar menus, and Raycast post-process mode resolution.
- **Changed (mode alias removal)**: `dictate mode` now accepts active mode names only (`short`, `long`, and explicit custom modes); legacy aliases are removed from command paths.
- **Improved (`dictate status`)**: Expanded from a minimal recording check to a full snapshot view (runtime state, tmux/inline queues, effective modes/models/toggles, resolved audio source, and active env overrides).
- **Improved (tmux modal clarity)**: Start/stop HUD text is now concise (`RECORDING/STOPPED → <cwd>`) and no longer includes pane id (`%N`) or model suffix in the brief toast output.
- **Fixed (SwiftBar tmux queue accuracy)**: Queue counting now prunes stale tmux job markers by pid liveness, so idle states no longer show phantom queued jobs.
- **New (advanced tmux/debug controls)**:
  - Config-backed `tmux.send_mode` (`auto|enter|codex`) and legacy compatibility toggle support.
  - Config-backed `debug.keep_logs` (bool), with `DICTATE_KEEP_LOGS` still supported as env override
  - New CLI: `dictate keep-logs on|off`, `dictate tmux send-mode ...`
  - SwiftBar now exposes a top-level **Advanced** menu with **Global / Inline / Tmux** sections
  - SwiftBar adds **Advanced → Inline** controls for `paste target`, `silence trim`, and `repeats level`
- **Refactor (backend simplification, Phase 1)**:
  - Runtime transcription is now `whisper-cli` only (main CLI + Raycast inline).
  - Removed faster-whisper/server execution branches and related env/config plumbing from active paths.
  - Removed deprecated compatibility shims: `dictate backend ...` and `dictate server ...`.
- **New (bench + stage timings)**:
  - Added persistent timing capture for core stages (`tmux`, `dictate inline`, and Raycast inline): `record`, `transcribe`, `clean`, `postprocess`, `paste`, `total(stop->done)`.
  - Added `dictate bench [N]` to summarize recent timing runs (counts by flow/status, stage medians/p90/max, latest run details).
  - Added `dictate bench clear` to reset stored benchmark samples.
- **New (short/long postprocess profiles)**:
  - Added `dictate profile` CLI to view and tune explicit `short` vs `long` postprocess defaults (`llm`, `max_tokens`, `chunk_words`).
  - Added profile setters: `dictate profile <short|long> llm|max_tokens|chunk_words ...`, plus `dictate profile <mode> clear`.
  - Profile lookup now uses explicit `short`/`long` override keys only.
  - `dictate status` now shows resolved `profile.short` and `profile.long` effective values.
- **Fixed (paragraph formatting reliability)**:
  - Added a deterministic postprocess paragraph pass for `short`/`long` modes: long single-block outputs now get a natural blank-line split even when the LLM returns one dense paragraph.
  - Applied the same paragraph pass in both main CLI and Raycast inline paths.
  - Tightened short-mode prompt guidance so paragraphing is explicit and consistent for longer outputs.
- **Improved (British spelling consistency)**:
  - Added deterministic UK spelling normalisation in shared postprocess output paths (main CLI + Raycast inline), so words like `optimization/organize/center` consistently become `optimisation/organise/centre`.
  - Added env override `DICTATE_BRITISH_SPELLING=0` for temporary opt-out (default is on).
- **Improved (vocab workflow)**:
  - `dictate vocab add` now supports multiple entries in one call and semicolon-separated batches.
  - Added `dictate vocab import <file>` for bulk import from line-based files.
  - Added `dictate vocab clipboard` for quick import from clipboard lines.
  - Added `dictate vocab dedupe` to normalize delimiters and remove duplicate entries.
  - `dictate vocab` output now shows numbered entries and quick command hints.
- **Refactor (legacy cleanup, breaking)**:
  - Removed deprecated command shims: `dictate backend ...` and `dictate server ...`.
  - Removed legacy model aliases (`tiny`, `large`), keeping only `base|small|turbo`.
  - Removed legacy mode aliases (`auto`, `code`, `prose`) from active command paths.
  - Removed legacy postprocess override fallback keys (`postprocess.mode_overrides.code|prose.*`).
  - Renamed mode directories from `modes/code` + `modes/prose` to `modes/short` + `modes/long`.

## 2026-01-31

- **Fixed (LLM postprocess / code mode)**: Prevented the LLM from "doing the task" (e.g., generating JSON prompt files) instead of just cleaning dictation.
- **Improved**: Strengthened base LLM instructions to treat input as text-to-edit, not instructions-to-execute.
- **Guardrail**: In `code` mode, reject obvious generated artefacts (e.g. `{"prompt": ...}` JSON when the input wasn't JSON) and fall back to the original chunk.
- **Note**: Applied the same fix to both `~/.local/bin/dictate` and the Raycast inline script (`integrations/raycast/dictate-inline.sh`) because they duplicate postprocess logic.

## 2026-01-27

- **Fixed (tmux → Codex)**: Autosend now works reliably in Codex panes by sending `C-i` then `Enter` after paste (other panes still use `Enter`).
- **Fixed (Raycast tmux toggle)**: Removed extra stop sound so stop SFX doesn’t double-play (stop sound comes from Dictate after processing completes).
- **Improved (Raycast sounds)**: Raycast scripts now play short SFX synchronously to avoid clipping.
- **Improved (Sound clipping)**: Added 150ms front-padding to WAVs in `~/.local/share/sounds/dictate/` and `~/.local/share/sounds/events/` (originals kept as `*.wav.orig.wav`). New helper: `~/.config/dictate/tools/pad-sfx.sh`.

## 2026-01-26

### Whisper Speed Knobs (beam + threads)

- **New**: Configurable decode settings in `config.toml`:
  - `whisper.threads` (default: `5`)
  - `whisper.beam_size` (default: `1`)
  - `whisper.best_of` (default: `1`)
- **New**: Env overrides for quick A/B testing:
  - `DICTATE_THREADS`, `DICTATE_BEAM_SIZE`, `DICTATE_BEST_OF`
- **Note**: These mainly affect `whisper-cli` decoding latency/quality tradeoffs; post-processing time is unchanged.

### Tmux-First Controls + Queue

- **New**: tmux-specific defaults in `config.toml`:
  - `tmux.autosend` (default: `true`)
  - `tmux.paste_target` (`origin` default, or `current`)
  - `tmux.postprocess` (default: `false`)
  - `tmux.mode` (default: `code`)
- **New**: CLI controls:
  - `dictate tmux autosend on|off`
  - `dictate tmux target origin|current`
  - `dictate tmux postprocess on|off`
  - `dictate tmux mode <name>`
- **New**: SwiftBar shows tmux queue counts and exposes tmux toggles (postprocess/autosend/target).
- **New**: SwiftBar now groups controls into **Inline** and **Tmux** menus (modes, models, and toggles).
- **New**: tmux model control (`tmux.model`, `dictate tmux model <name>`).
- **New**: tmux menu hides `email`/`chat` modes and turbo/large models (keeps base/small by default).
- **Updated**: SwiftBar hides Auto‑detect and removes the non‑selectable model labels (only selectable items remain).
- **Change**: tmux post-process is no longer tied to global `postprocess.enabled` unless tmux is unset.

### Raycast Inline Startup Latency

- **Fixed**: `integrations/raycast/dictate-inline.sh` config loader had a Python indentation error, so Raycast was silently ignoring `config.toml`.
- **Improved**: Raycast inline now caches the resolved AVFoundation audio **device index** by preferred device name at `~/.config/dictate/.cache/audio-index.sh` to reduce “hotkey → recording” latency.
- **Improved**: Recording start sound plays as soon as `ffmpeg` is live; target app/window capture is deferred until after recording begins (reduces perceived startup delay).
- **New (debug)**: Set `DICTATE_RAYCAST_TRACE=1` to log per-step timings into `/tmp/dictate-raycast-inline.log`.

### Regex Cleanup Knobs (no LLM)

- **New**: `clean.repeats_level` (default: `1`)
  - `0` = off
  - `1` = remove repeated words (e.g., `the the`)
  - `2` = also remove repeated short phrases (2–3 words) when adjacent
- **New**: Env override for A/B testing: `DICTATE_REPEATS_LEVEL`

### Silence Trimming (ffmpeg)

- **New**: Optional ffmpeg pre-trim using `silenceremove` (default **disabled**) to remove leading/trailing silence before transcription:
  - `audio.silence_trim` (bool)
  - `audio.silence_trim_mode` (`edges` default, `all` experimental)
  - `audio.silence_threshold_db` (default: `-60`)
  - `audio.silence_min_ms` (default: `250`)
  - `audio.silence_keep_ms` (default: `50`)
- **New**: Env override for quick A/B: `DICTATE_SILENCE_TRIM=0/1`

### Silence Skipping (VAD)

- **New**: `whisper.vad` + VAD tuning keys in `config.toml` (default **disabled**) to skip silence and reduce wasted decode time on pauses.
- **Important**: `whisper-cli --vad` currently triggers a `ggml-metal` assertion on Apple Silicon when running on GPU/Metal. When VAD is enabled, Dictate forces CPU (`-ng`) for stability.
- **Note**: whisper-cli VAD also requires a VAD model file; set `whisper.vad_model` (or `DICTATE_VAD_MODEL`) to a valid path, otherwise Dictate will skip VAD.
- **New**: `DICTATE_VAD=0/1` env override for quick A/B.
- **Fixed**: Bash 3.2 + `set -u` treated empty `vad_args[@]` expansions as an unbound variable; transcribe args are now built as a single array so `dictate inline` won’t crash when VAD is disabled.

### Faster-Whisper Daemon Experiment (archived)

Attempted to speed up transcription by implementing a persistent daemon that keeps the model loaded in memory.

**What was built:**
- `faster-whisper-server` - Python daemon listening on Unix socket (`/tmp/faster-whisper.sock`)
- `faster-whisper-client` - Client to query the server
- launchd plist for auto-start (`com.dictate.faster-whisper`)
- `dictate server start/stop/status/restart/logs` commands
- `dictate backend` switching (whisper/faster/server/auto)

**Results:**
- Daemon works correctly but **did not provide speed improvement**
- whisper.cpp CLI: ~1.6s for 15s audio (heavily optimized for Apple Silicon Metal/ANE)
- faster-whisper daemon: ~2.0s for same audio (Python/socket overhead negates preloaded model)
- The 3-4s model load time that plagues x86 systems is not an issue on M-series chips

**Conclusion:** whisper.cpp is already extremely fast on Apple Silicon. The daemon infrastructure is preserved for future use with backends that have slower model loading (e.g., Nvidia Parakeet, larger models).

**Files archived to:** `archive/faster-whisper/`
**Daemon files preserved:** `~/.local/bin/faster-whisper-server`, `faster-whisper-client`, launchd plist

**Current config:** Backend reset to `whisper-cli` (default).

---

### Long Dictation Fix + History

- **Fixed**: Removed `max_tokens: 1200` limit from LLM post-processing. Long dictations (4+ minutes) were being truncated mid-sentence. Now uses model default (8192 tokens for gpt-oss-120b).
- **New**: Configurable LLM cap + chunking to avoid truncation while keeping speed reasonable:
  - `postprocess.max_tokens` (default: `3000`) / env `DICTATE_LLM_MAX_TOKENS`
  - `postprocess.chunk_words` (default: `700`) / env `DICTATE_LLM_CHUNK_WORDS`
- **New**: Per-mode overrides for caps/chunking (currently `code` + `prose`):
  - `postprocess.mode_overrides.code.*`
  - `postprocess.mode_overrides.prose.*`
- **Updated**: Code mode prompt now uses a lighter‑touch cleanup (preserve phrasing, minimal edits, keep paragraphing).
- **New**: `dictate history` command - all dictations now saved to `~/.config/dictate/history/` with raw transcript and processed output.
  - `dictate history` - list recent (last 20)
  - `dictate history N` - show entry N (1 = most recent)
  - `dictate history reprocess N [mode]` - re-run LLM on raw transcript with different mode
  - `dictate history clear` - delete all history
- **Auto-cleanup**: History entries older than 7 days are automatically deleted on each dictation.

### Mode Consolidation

- **Simplified to 5 modes**: code, base, prose, email, chat
- **Deleted**: `code-v1` (superseded by new code mode)
- **Archived**: `linkedin`, `twitter`, `prompt` moved to `modes/archive/` - these are content transformation tools, not dictation cleanup, better suited as Claude skills or hooks
- **Updated code mode**:
  - Now base-like: preserves voice and phrasing
  - Adds light structure: paragraphs for topic changes, numbered lists when detected
  - Includes code-specific vocab corrections (WezTerm, pnpm, git, Ghostty, etc.)
  - No longer restructures or "polishes" - keeps your speaking style
- **Base mode**: Unchanged - single string output, minimal intervention

## 2026-01-25

### Focus & Paste Fixes
- **Fixed**: Inline mode now restores the correct **window** (not just app) when pasting. Previously, with multiple Ghostty windows open, dictate would paste to a random window. Now it captures the window name at recording start and uses `AXRaise` to bring the correct window to front.
- **Fixed**: Inline mode now captures **PID** of the frontmost process, enabling correct targeting when multiple instances of the same app exist (e.g., two separate Ghostty processes). Uses `unix id` to identify and restore the exact process.
- **Fixed**: `CEREBRAS_API_KEY` now loads from `.zshrc` if not set via `.zshenv`. Raycast doesn't source interactive shell config, so the Raycast script now extracts API keys explicitly.
- State file now uses `%q` quoting to handle special characters in app/window names.

### Mode System Overhaul
- **Synced modes from WhisperModes project**: All mode prompts updated with comprehensive, structured instructions.
- **New modes added**:
  - `prompt` - Code prompt enhancer for AI agents with @-file tagging, action patterns, imperative conversion
- **Removed** `meeting` and `exercise` modes from dictate config (kept in WhisperModes project for mobile use)
- **Updated modes**:
  - `code` - Now a clean conversational mode for terminal use (simpler, no @-tagging)
  - `prose` - Now uses `general.md` with full text formatting, trailing tone commands, email detection
  - `email` - Professional email formatter with auto-detected tone and no sign-off (user has signature)
  - `linkedin` - SLAY framework, hook patterns, POV style support
  - `twitter` - Ship 30 for 30 framework, thread support, strength levels
- **Added README** to `~/Documents/Projects/WhisperModes/` explaining mode sync workflow.
- **Vocab**: Added WezTerm corrections (where's term, wez term, west term → WezTerm).

## 2026-01-19

- Fixed `detect_audio_index()` bug: pipe+heredoc conflict caused stdin to be empty.
- Device selection is name-first with index as fallback (`dictate device name "..."`, `dictate device auto`).
- Removed hardcoded `DICTATE_AUDIO_INDEX=1` from Raycast integrations so config controls the device.
- Added `dictate debug` to show resolved device selection and common failure causes.
- Added `dictate logs` and `DICTATE_KEEP_LOGS=1` to keep logs only when needed.
- **Fixed**: Inline mode now pastes to the app that was frontmost when recording started (not hardcoded Ghostty).
- **Fixed**: Vocab now accepts `::` as delimiter (e.g., `dictate vocab add "wrong::right"`).
- SwiftBar: Autosend and Postprocess are now clickable toggles in the Settings menu.
- **New**: `dictate cancel` command (and tmux bind: prefix + Escape) to discard recording without pasting.
- **New**: `dictate target restore|current` to control paste behavior (restore = app from recording start, current = wherever you are now).
- **New**: `dictate replay <mode> "text"` to reprocess provided text instead of clipboard.
- **Fixed**: SwiftBar + `dictate` now prepend Homebrew paths in `PATH` so `python3` resolves to a `tomllib`-capable version (prevents incorrect UI state / toggles doing nothing).
- SwiftBar: Added **Cancel Recording** menu item; fixed short-lived flag timing (cancel/processed) and “Clear Error” action.
- `dictate inline`: Better diagnostics + stable inline logs (`/tmp/whisper-dictate-inline.record.log`, `/tmp/whisper-dictate-inline.transcribe.log`).
- `dictate inline` + Raycast inline: Use `System Events` process frontmost activation (fixes apps like `wezterm-gui` where process name ≠ app name).
- SwiftBar: Reduced refresh interval to `0.2s` (`dictate-status.0.2s.sh`), added config/mode caching and avoided `osascript` except when needed (auto mode + ready state).
- Raycast inline: Reduced “ffmpeg alive” startup delay (faster start sound / less waiting before you speak).
- SwiftBar: Processing icon now tracks real work more closely by treating `/tmp/dictate-processing/*` markers as pid-aware and auto-cleaning stale markers left behind by early exits/crashes.
- SwiftBar: Raycast actions now trigger immediate SwiftBar refresh via `swiftbar://refreshplugin` (icon updates no longer wait for the next tick); SwiftBar cache moved to `$SWIFTBAR_PLUGIN_CACHE_PATH` to avoid random `/tmp` cleanup causing choppy updates.
- SwiftBar: Inline processing icon is threshold-based (only shows if processing is still running after a short delay) and is inline-only.
- SwiftBar: “Just processed” no longer holds the ⏳ icon; it shows the Ready icon with a brief “Just processed” status instead (reduces post-send lag).
- Modes: Fixed mode prompts being overridden by overly-restrictive base rules (prose/email formatting now allowed when the selected mode asks for it).
- LLM: Increased Cerebras request timeout (default `DICTATE_LLM_TIMEOUT=20`) and max completion tokens; optional failure logging when `DICTATE_KEEP_LOGS=1`.
- LLM: Use `max_tokens` for Cerebras Chat Completions payload (improves compatibility vs `max_completion_tokens`).

## TODO

### Next queue (core product)

- [x] Add stage timings and a lightweight `tmux-whisper bench` summary (record stop -> transcribe -> clean -> postprocess -> paste).
- [x] Retire legacy whisper.cpp decode-default tuning from the active queue; the runtime is Parakeet-only now, so future tuning belongs in Swift Parakeet warmup/cache/latency work.
- [x] Add a `tmux-whisper bench-matrix` command (`model x postprocess x vocab_clean`) to compare speed + output quality on a fixed phrase set.
- [x] Add explicit `short` vs `long` postprocess profiles (mode-specific LLM/token/chunk defaults).
- [x] Evolve budget handling to `budget auto` (dynamic transcript-length-aware sizing for `max_tokens` / `chunk_words`), with `short` / `long` budget profiles kept as internal guardrails/presets.
- [x] Improve vocab workflow: bulk import/batch add and easier correction review from recent history.
- [x] Expand the operator CLI around history/logs/bench/config before any dashboard work: JSON parity, export/search/tail helpers, live text-first watch surfaces, filtered bench inspection, session summaries, command cross-links, and documented JSON contracts.
- [x] Package/install polish: bootstrap/update scripts + docs for reproducible setup across machines.
- [x] Add explicit SwiftBar integration on/off toggle (Tmux Whisper remains fully usable without SwiftBar).
- [ ] When `CHANGELOG.md` gets too long, archive older entries into a single `CHANGELOG.archive.md` (keep current/recent work in `CHANGELOG.md`).

### Future labs (deferred, separate projects)

- [ ] `voxtral-inline` exploration (API/realtime-first inline dictation tool), after core Dictate UX/reliability is stable.
- [ ] `faster-whisper-tool` exploration (batch/subtitle/offline utility), separate from tmux-first Dictate.
