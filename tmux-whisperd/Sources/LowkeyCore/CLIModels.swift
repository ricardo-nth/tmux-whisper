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

  enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case cliVersion = "cli_version"
    case hotkey
    case sounds
    case inline
    case cleanup
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
