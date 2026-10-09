import Foundation

/// `tmux-whisper app-config --json`
public struct AppConfig: Decodable, Equatable, Sendable {
  public struct Sound: Decodable, Equatable, Sendable {
    public let enabled: Bool
    public let path: String?
  }

  public struct Inline: Decodable, Equatable, Sendable {
    public let autosend: Bool
    public let sendMode: String
    public let pasteTarget: String
    public let processSound: Bool
    public let activateDelayMs: Int
    public let sendDelayMs: Int

    enum CodingKeys: String, CodingKey {
      case autosend
      case sendMode = "send_mode"
      case pasteTarget = "paste_target"
      case processSound = "process_sound"
      case activateDelayMs = "activate_delay_ms"
      case sendDelayMs = "send_delay_ms"
    }
  }

  public let schemaVersion: Int
  public let cliVersion: String
  public let hotkey: String
  public let sounds: [String: Sound]
  public let inline: Inline
  /// Text cleanup settings for the native TextPipeline. Absent from CLIs
  /// older than 0.10.
  public let cleanup: CleanupSettings?
  /// Transcription settings for the native path (0.10+).
  public let transcription: TranscriptionSettings?
  /// `[app] native_pipeline` / `verify_pipeline` (0.10+).
  public let pipeline: Pipeline?

  public struct Pipeline: Decodable, Equatable, Sendable {
    public let native: Bool
    public let verify: Bool
  }

  enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case cliVersion = "cli_version"
    case hotkey
    case sounds
    case inline
    case cleanup
    case transcription
    case pipeline
  }

  /// The delivery settings as `inline process` reports them.
  public var delivery: Delivery {
    Delivery(autosend: inline.autosend, sendMode: inline.sendMode, pasteTarget: inline.pasteTarget,
             activateDelayMs: inline.activateDelayMs, sendDelayMs: inline.sendDelayMs)
  }

  /// Why a take must go through `inline process` instead of the native
  /// pipeline, or nil if the native path reproduces the CLI.
  public var nativePipelineBlocker: String? {
    guard pipeline?.native ?? false else { return pipeline == nil ? "CLI too old for the native path" : "[app] native_pipeline = false" }
    guard let cleanup else { return "no cleanup settings" }
    if cleanup.postprocess { return "LLM post-processing is on" }
    if cleanup.requiresCLI { return "CLI locale is not C (\(cleanup.localeCtype ?? "")/\(cleanup.localeCollate ?? ""))" }
    guard let transcription else { return "no transcription settings" }
    return transcription.cliReason
  }
}

/// `tmux-whisper inline cleanup --app NAME --json` (transcript on stdin).
public struct CleanupResult: Decodable, Equatable, Sendable {
  public let ok: Bool
  public let status: String
  public let rawText: String
  public let text: String
  public let mode: String?
  public let cleanup: CleanupSettings

  enum CodingKeys: String, CodingKey {
    case ok, status, text, mode, cleanup
    case rawText = "raw_text"
  }
}

/// `tmux-whisper inline process <wav> --json`
public struct ProcessResult: Decodable, Equatable, Sendable {
  public let ok: Bool
  public let status: String
  public let text: String
  public let rawText: String
  public let mode: String?
  public let message: String?
  public let delivery: Delivery
  public let timings: [String: Int]

  enum CodingKeys: String, CodingKey {
    case ok, status, text, mode, message, delivery, timings
    case rawText = "raw_text"
  }
}

public struct Delivery: Decodable, Equatable, Sendable {
  public let autosend: Bool
  public let sendMode: String
  public let pasteTarget: String
  public let activateDelayMs: Int
  public let sendDelayMs: Int

  public init(autosend: Bool, sendMode: String, pasteTarget: String, activateDelayMs: Int, sendDelayMs: Int) {
    self.autosend = autosend
    self.sendMode = sendMode
    self.pasteTarget = pasteTarget
    self.activateDelayMs = activateDelayMs
    self.sendDelayMs = sendDelayMs
  }

  enum CodingKeys: String, CodingKey {
    case autosend
    case sendMode = "send_mode"
    case pasteTarget = "paste_target"
    case activateDelayMs = "activate_delay_ms"
    case sendDelayMs = "send_delay_ms"
  }
}
