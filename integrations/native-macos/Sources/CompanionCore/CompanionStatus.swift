import Foundation

/// The small, forward-compatible part of `tmux-whisper status --json` used by
/// the experimental menu bar companion. Unknown fields are deliberately ignored.
public struct CompanionStatus: Equatable, Sendable {
  public struct Summary: Equatable, Sendable {
    public let state: State
    public let headline: String
    public let nextAction: String
    public let activeFlow: Flow?

    public init(state: State, headline: String, nextAction: String, activeFlow: Flow?) {
      self.state = state
      self.headline = headline
      self.nextAction = nextAction
      self.activeFlow = activeFlow
    }
  }

  public struct Runtime: Equatable, Sendable {
    public let tmux: Session
    public let inline: Session
    public let processingMarkers: ActivityCount
    public let tmuxQueue: QueueCount

    public init(tmux: Session, inline: Session, processingMarkers: ActivityCount, tmuxQueue: QueueCount) {
      self.tmux = tmux
      self.inline = inline
      self.processingMarkers = processingMarkers
      self.tmuxQueue = tmuxQueue
    }
  }

  public struct Session: Equatable, Sendable {
    public let state: SessionState
    public let isStale: Bool

    public init(state: SessionState, isStale: Bool) {
      self.state = state
      self.isStale = isStale
    }

    public var isActive: Bool { state == .active }
  }

  public struct ActivityCount: Equatable, Sendable {
    public let total: Int
    public let live: Int
    public let stale: Int

    public init(total: Int, live: Int, stale: Int) {
      self.total = total
      self.live = live
      self.stale = stale
    }
  }

  public struct QueueCount: Equatable, Sendable {
    public let total: Int
    public let recording: Int
    public let processing: Int

    public init(total: Int, recording: Int, processing: Int) {
      self.total = total
      self.recording = recording
      self.processing = processing
    }
  }

  public enum State: String, Equatable, Sendable {
    case ready
    case recording
    case processing
    case attention
    case notReady = "not_ready"
    case unknown
  }

  public enum SessionState: String, Equatable, Sendable {
    case idle
    case active
    case stale
    case unknown
  }

  public enum Flow: String, Equatable, Sendable {
    case inline
    case tmux
  }

  public let summary: Summary
  public let runtime: Runtime

  public init(summary: Summary, runtime: Runtime) {
    self.summary = summary
    self.runtime = runtime
  }

  public var policy: ControlPolicy { ControlPolicy(status: self) }

  public static func parse(json data: Data) throws -> CompanionStatus {
    let object: [String: Any]
    do {
      object = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    } catch {
      throw StatusError.malformedJSON
    }
    guard object["command"] as? String == "status" else {
      throw StatusError.notStatusResponse
    }

    let summaryObject = try object.requiredDictionary("summary")
    let runtimeObject = try object.requiredDictionary("runtime")
    let summary = Summary(
      state: State(rawValue: try summaryObject.requiredString("state")) ?? .unknown,
      headline: try summaryObject.requiredString("headline"),
      nextAction: try summaryObject.requiredString("next_action"),
      activeFlow: Flow(rawValue: summaryObject.string("active_flow") ?? "")
    )
    let processing = try runtimeObject.requiredDictionary("processing_markers")
    let queue = try runtimeObject.requiredDictionary("tmux_queue")
    return CompanionStatus(
      summary: summary,
      runtime: Runtime(
        tmux: try Self.session(from: runtimeObject.requiredDictionary("tmux")),
        inline: try Self.session(from: runtimeObject.requiredDictionary("inline")),
        processingMarkers: ActivityCount(
          total: try processing.requiredCount("total"),
          live: try processing.requiredCount("live"),
          stale: try processing.requiredCount("stale")
        ),
        tmuxQueue: QueueCount(
          total: try queue.requiredCount("total"),
          recording: try queue.requiredCount("recording"),
          processing: try queue.requiredCount("processing")
        )
      )
    )
  }

  private static func session(from object: [String: Any]) throws -> Session {
    let state = SessionState(rawValue: try object.requiredString("state")) ?? .unknown
    return Session(state: state, isStale: try object.requiredBool("stale") || state == .stale)
  }
}

public enum StatusError: Error, Equatable, LocalizedError, Sendable {
  case malformedJSON
  case notStatusResponse
  case missingRequiredField(String)

  public var errorDescription: String? {
    return switch self {
    case .malformedJSON: "tmux-whisper status returned malformed JSON."
    case .notStatusResponse: "tmux-whisper did not return a status response."
    case .missingRequiredField(let field): "tmux-whisper status omitted or changed required field: \(field)."
    }
  }
}

public struct ControlPolicy: Equatable, Sendable {
  public let startInline: Bool
  public let stopInline: Bool
  public let cancelInline: Bool

  public var canStartInline: Bool { startInline }
  public var canStopInline: Bool { stopInline }
  public var canCancelInline: Bool { cancelInline }

  public init(status: CompanionStatus) {
    let runtime = status.runtime
    let runtimeIsQuiet = runtime.processingMarkers.total == 0
      && runtime.processingMarkers.live == 0
      && runtime.processingMarkers.stale == 0
      && runtime.tmuxQueue.total == 0
      && runtime.tmuxQueue.recording == 0
      && runtime.tmuxQueue.processing == 0
    let noTmuxRun = runtime.tmux.state == .idle && !runtime.tmux.isStale
    let safeInline = !runtime.inline.isStale
    startInline = status.summary.state == .ready
      && runtime.inline.state == .idle
      && safeInline
      && noTmuxRun
      && runtimeIsQuiet
    stopInline = status.summary.state == .recording
      && status.summary.activeFlow == .inline
      && runtime.inline.isActive
      && safeInline
      && noTmuxRun
      && runtimeIsQuiet
    // `cancel` checks tmux before inline and clears all processing markers.
    // Offer it only for a fresh, exclusively inline recording.
    cancelInline = status.summary.state == .recording
      && status.summary.activeFlow == .inline
      && runtime.inline.isActive
      && safeInline
      && noTmuxRun
      && runtimeIsQuiet
  }

  public func permits(_ command: WhisperCommand) -> Bool {
    switch command {
    case .startInline: startInline
    case .stopInline: stopInline
    case .cancelInline: cancelInline
    }
  }
}

public enum WhisperCommand: String, CaseIterable, Sendable {
  case startInline
  case stopInline
  case cancelInline

  public var arguments: [String] {
    switch self {
    case .startInline: ["inline", "start"]
    case .stopInline: ["inline", "stop"]
    case .cancelInline: ["cancel"]
    }
  }
}

private extension Dictionary where Key == String, Value == Any {
  func string(_ key: String) -> String? { self[key] as? String }
  func requiredDictionary(_ key: String) throws -> [String: Any] {
    guard let value = self[key] as? [String: Any] else { throw StatusError.missingRequiredField(key) }
    return value
  }
  func requiredString(_ key: String) throws -> String {
    guard let value = string(key), !value.isEmpty else { throw StatusError.missingRequiredField(key) }
    return value
  }
  func requiredBool(_ key: String) throws -> Bool {
    guard let value = self[key] as? Bool else { throw StatusError.missingRequiredField(key) }
    return value
  }
  func requiredCount(_ key: String) throws -> Int {
    guard let value = self[key] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() else {
      throw StatusError.missingRequiredField(key)
    }
    // Preserve integer precision: Double(Int.max) rounds upward to 2^63.
    // Decimal normalizes integral JSON exponent/decimal forms before Int's
    // exact, range-checked conversion, without a floating-point boundary.
    guard let decimal = Decimal(string: value.stringValue, locale: Locale(identifier: "en_US_POSIX")),
      let count = Int(NSDecimalNumber(decimal: decimal).stringValue), count >= 0
    else {
      throw StatusError.missingRequiredField(key)
    }
    return count
  }
}
