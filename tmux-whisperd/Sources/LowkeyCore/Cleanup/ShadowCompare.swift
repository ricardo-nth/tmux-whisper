import Foundation

/// Shadow comparison for the 3b rollout (`[app] verify_pipeline`): after the
/// native result is delivered, the CLI processes the same take in the
/// background and any difference is logged with both texts.
public enum ShadowCompare {
  /// nil when the native and CLI results agree (byte-identical text, raw
  /// text and mode, or both found no speech), else a one-line description
  /// for app.log. A native `.needsCLI` is never compared.
  public static func mismatch(
    native: CleanupOutcome, cliStatus: String, cliRawText: String, cliText: String, cliMode: String?
  ) -> String? {
    switch (native, cliStatus) {
    case (.needsCLI, _), (.noSpeech, "no_speech"):
      return nil
    case (.text(let raw, let text, let mode), "ok"):
      var diffs: [String] = []
      if mode != cliMode { diffs.append("mode native=\(mode.debugDescription) cli=\((cliMode ?? "").debugDescription)") }
      if !sameBytes(raw, cliRawText) {
        diffs.append("raw native=\(raw.debugDescription) cli=\(cliRawText.debugDescription)")
      }
      if !sameBytes(text, cliText) {
        diffs.append("text native=\(text.debugDescription) cli=\(cliText.debugDescription)")
      }
      return diffs.isEmpty ? nil : "pipeline mismatch: " + diffs.joined(separator: "; ")
    case (.noSpeech, _):
      return "pipeline mismatch: native=no_speech cli=\(cliStatus) text=\(cliText.debugDescription)"
    case (.text(_, let text, _), _):
      return "pipeline mismatch: native=ok cli=\(cliStatus) text=\(text.debugDescription)"
    }
  }

  /// Against `inline process --json` (whole take: transcription + cleanup).
  public static func mismatch(native: CleanupOutcome, cli: ProcessResult) -> String? {
    mismatch(native: native, cliStatus: cli.status, cliRawText: cli.rawText, cliText: cli.text, cliMode: cli.mode)
  }

  /// Against `inline cleanup --json` on the same raw transcript (text only).
  public static func mismatch(native: CleanupOutcome, cli: CleanupResult) -> String? {
    mismatch(native: native, cliStatus: cli.status, cliRawText: cli.rawText, cliText: cli.text, cliMode: cli.mode)
  }

  /// UTF-8 byte equality; String == accepts canonically equivalent text.
  static func sameBytes(_ a: String, _ b: String) -> Bool {
    a.utf8.elementsEqual(b.utf8)
  }
}
