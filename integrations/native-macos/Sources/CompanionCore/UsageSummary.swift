import Foundation

/// Read-only summary of the versioned `tmux-whisper usage --json` contract.
/// The companion intentionally leaves duration and typing estimates to the CLI;
/// it displays only the coverage boundary and the two observable totals below.
public struct UsageSummary: Equatable, Sendable {
  public struct Coverage: Equatable, Sendable {
    public let status: Status
    public let trackingStartedAt: String?

    public init(status: Status, trackingStartedAt: String?) {
      self.status = status
      self.trackingStartedAt = trackingStartedAt
    }
  }

  public enum Status: String, Equatable, Sendable {
    case notStarted = "not_started"
    case active
    case unknown
  }

  public let schemaVersion: Int
  public let coverage: Coverage
  public let deliveredCount: Int
  public let processedWords: Int

  public init(schemaVersion: Int, coverage: Coverage, deliveredCount: Int, processedWords: Int) {
    self.schemaVersion = schemaVersion
    self.coverage = coverage
    self.deliveredCount = deliveredCount
    self.processedWords = processedWords
  }

  public static func parse(json data: Data) throws -> UsageSummary {
    let object: [String: Any]
    do {
      object = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    } catch {
      throw UsageError.malformedJSON
    }

    guard object["command"] as? String == "usage" else { throw UsageError.notUsageResponse }
    let schemaVersion = try object.requiredCount("schema_version")
    guard schemaVersion == 1 else { throw UsageError.unsupportedSchema(schemaVersion) }

    let coverage = try object.requiredDictionary("coverage")
    let delivered = try object.requiredDictionary("delivered_dictations")
    return UsageSummary(
      schemaVersion: schemaVersion,
      coverage: Coverage(
        status: Status(rawValue: try coverage.requiredString("status")) ?? .unknown,
        trackingStartedAt: coverage.nullableString("tracking_started_at")
      ),
      deliveredCount: try delivered.requiredCount("count"),
      processedWords: try object.requiredCount("processed_words")
    )
  }
}

public enum UsageError: Error, Equatable, LocalizedError, Sendable {
  case malformedJSON
  case notUsageResponse
  case unsupportedSchema(Int)
  case missingRequiredField(String)

  public var errorDescription: String? {
    switch self {
    case .malformedJSON:
      return "tmux-whisper usage returned malformed JSON."
    case .notUsageResponse:
      return "tmux-whisper did not return a usage response."
    case .unsupportedSchema(let version):
      return "tmux-whisper usage schema v\(version) is not supported by this companion."
    case .missingRequiredField(let field):
      return "tmux-whisper usage omitted or changed required field: \(field)."
    }
  }
}

private extension Dictionary where Key == String, Value == Any {
  func requiredDictionary(_ key: String) throws -> [String: Any] {
    guard let value = self[key] as? [String: Any] else { throw UsageError.missingRequiredField(key) }
    return value
  }

  func requiredString(_ key: String) throws -> String {
    guard let value = self[key] as? String, !value.isEmpty else { throw UsageError.missingRequiredField(key) }
    return value
  }

  func nullableString(_ key: String) -> String? {
    guard let value = self[key] else { return nil }
    return value is NSNull ? nil : value as? String
  }

  func requiredCount(_ key: String) throws -> Int {
    guard let value = self[key] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() else {
      throw UsageError.missingRequiredField(key)
    }
    let numeric = value.doubleValue
    guard numeric.isFinite,
      numeric >= 0,
      numeric <= Double(Int.max),
      numeric.rounded(.towardZero) == numeric
    else {
      throw UsageError.missingRequiredField(key)
    }
    return value.intValue
  }
}
