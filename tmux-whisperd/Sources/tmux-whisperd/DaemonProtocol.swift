import Foundation

enum DaemonOperation: String, Codable {
  case ping
  case warmup
  case transcribe
}

struct DaemonRequest: Codable {
  let id: String
  let op: DaemonOperation
  let wavPath: String?
  let language: String?
  let flow: String?
  let modelPath: String?
  let modelVersion: String?

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

struct DaemonResponse: Codable {
  let id: String
  let ok: Bool
  let text: String?
  let engine: String?
  let model: String?
  let durationMs: Int?
  let errorCode: String?
  let message: String?

  enum CodingKeys: String, CodingKey {
    case id
    case ok
    case text
    case engine
    case model
    case durationMs = "duration_ms"
    case errorCode = "error_code"
    case message
  }
}

enum DaemonServiceError: Error, LocalizedError {
  case invalidRequest(String)
  case unsupportedOperation(String)
  case modelPathMissing
  case modelPathInvalid(String)
  case wavPathMissing
  case wavPathInvalid(String)
  case unsupportedModelVersion(String)

  var errorDescription: String? {
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

  var errorCode: String {
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
