import Foundation

/// Version reported by `tmux-whisperd version` and in ping responses.
public enum DaemonInfo {
  public static let daemonVersion = "0.2.0"
  public static let engineName = "swift_parakeet"
}

public enum DaemonOperation: String, Codable, Sendable {
  case ping
  case warmup
  case transcribe
}

/// One newline-terminated JSON request per connection.
public struct DaemonRequest: Codable, Sendable {
  public let id: String
  public let op: DaemonOperation
  public let wavPath: String?
  public let language: String?
  public let flow: String?
  public let modelPath: String?
  public let modelVersion: String?

  public init(
    id: String,
    op: DaemonOperation,
    wavPath: String? = nil,
    language: String? = nil,
    flow: String? = nil,
    modelPath: String? = nil,
    modelVersion: String? = nil
  ) {
    self.id = id
    self.op = op
    self.wavPath = wavPath
    self.language = language
    self.flow = flow
    self.modelPath = modelPath
    self.modelVersion = modelVersion
  }

  enum CodingKeys: String, CodingKey {
    case id
    case op
    case wavPath = "wav_path"
    case language
    case flow
    case modelPath = "model_path"
    case modelVersion = "model_version"
  }
}

/// One newline-terminated JSON response. Optional fields are omitted when nil,
/// so additions stay compatible with existing clients.
public struct DaemonResponse: Codable, Sendable, Equatable {
  public let id: String
  public let ok: Bool
  public let text: String?
  public let engine: String?
  public let model: String?
  public let durationMs: Int?
  public let errorCode: String?
  public let message: String?
  /// Daemon version (ping only).
  public let version: String?
  /// Warmup/transcribe requests in flight, excluding this one (ping only).
  public let activeRequests: Int?

  public init(
    id: String,
    ok: Bool,
    text: String? = nil,
    engine: String? = DaemonInfo.engineName,
    model: String? = nil,
    durationMs: Int? = nil,
    errorCode: String? = nil,
    message: String? = nil,
    version: String? = nil,
    activeRequests: Int? = nil
  ) {
    self.id = id
    self.ok = ok
    self.text = text
    self.engine = engine
    self.model = model
    self.durationMs = durationMs
    self.errorCode = errorCode
    self.message = message
    self.version = version
    self.activeRequests = activeRequests
  }

  public static func failure(id: String, code: String, message: String) -> DaemonResponse {
    DaemonResponse(id: id, ok: false, errorCode: code, message: message)
  }

  enum CodingKeys: String, CodingKey {
    case id
    case ok
    case text
    case engine
    case model
    case durationMs = "duration_ms"
    case errorCode = "error_code"
    case message
    case version
    case activeRequests = "active_requests"
  }
}

public enum DaemonServiceError: Error, LocalizedError, Sendable {
  case invalidRequest(String)
  case unsupportedOperation(String)
  case modelPathMissing
  case modelPathInvalid(String)
  case wavPathMissing
  case wavPathInvalid(String)
  case unsupportedModelVersion(String)

  public var errorDescription: String? {
    switch self {
    case .invalidRequest(let message):
      return message
    case .unsupportedOperation(let operation):
      return "unsupported operation: \(operation)"
    case .modelPathMissing:
      return "swift_parakeet model path is missing"
    case .modelPathInvalid(let path):
      return "swift_parakeet model path is invalid: \(path)"
    case .wavPathMissing:
      return "missing wav_path"
    case .wavPathInvalid(let path):
      return "wav_path is invalid: \(path)"
    case .unsupportedModelVersion(let version):
      return "unsupported model version: \(version)"
    }
  }

  public var errorCode: String {
    switch self {
    case .invalidRequest:
      return "invalid_request"
    case .unsupportedOperation:
      return "unsupported_operation"
    case .modelPathMissing:
      return "model_path_missing"
    case .modelPathInvalid:
      return "model_path_invalid"
    case .wavPathMissing:
      return "wav_path_missing"
    case .wavPathInvalid:
      return "wav_path_invalid"
    case .unsupportedModelVersion:
      return "unsupported_model_version"
    }
  }
}
