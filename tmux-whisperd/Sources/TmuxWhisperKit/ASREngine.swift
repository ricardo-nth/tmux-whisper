import Foundation
@preconcurrency import FluidAudio

private struct LoadedModelKey: Equatable {
  let path: String
  let version: String
}

public struct TranscriptionResult: Sendable {
  public let text: String
  public let model: String
  public let durationMs: Int
}

/// Serializes async critical sections. Actor methods are reentrant at `await`
/// points, so actor isolation alone does not stop two callers from
/// interleaving inside FluidAudio.
actor SerialGate {
  private var busy = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  func acquire() async {
    if !busy {
      busy = true
      return
    }
    await withCheckedContinuation { waiters.append($0) }
  }

  func release() {
    if waiters.isEmpty {
      busy = false
    } else {
      // Ownership passes straight to the next waiter; `busy` stays true.
      waiters.removeFirst().resume()
    }
  }

  func withExclusiveAccess<T: Sendable>(_ body: @Sendable () async throws -> T) async rethrows -> T {
    await acquire()
    do {
      let value = try await body()
      release()
      return value
    } catch {
      release()
      throw error
    }
  }
}

/// Parakeet (FluidAudio) speech recognition with a warm, reusable model.
///
/// FluidAudio's `AsrManager` is a non-thread-safe class with per-stream decoder
/// state, so model loading and transcription run one at a time through a gate.
public actor ASREngine {
  private var currentKey: LoadedModelKey?
  private var manager: AsrManager?
  private let gate = SerialGate()

  public init() {}

  public func warmup(modelURL: URL, modelVersion: String) async throws -> (model: String, durationMs: Int) {
    let version = try Self.parseModelVersion(modelVersion)
    return try await gate.withExclusiveAccess {
      let started = ContinuousClock.now
      try await self.ensureInitialized(modelURL: modelURL, version: version, versionLabel: modelVersion)
      return (modelURL.lastPathComponent, Self.elapsedMs(since: started))
    }
  }

  public func transcribe(audioURL: URL, modelURL: URL, modelVersion: String) async throws -> TranscriptionResult {
    let version = try Self.parseModelVersion(modelVersion)
    return try await gate.withExclusiveAccess {
      try await self.runTranscription(audioURL: audioURL, modelURL: modelURL, version: version, versionLabel: modelVersion)
    }
  }

  // Runs on the actor so the non-Sendable AsrManager never leaves it.
  private func runTranscription(
    audioURL: URL,
    modelURL: URL,
    version: AsrModelVersion,
    versionLabel: String
  ) async throws -> TranscriptionResult {
    try await ensureInitialized(modelURL: modelURL, version: version, versionLabel: versionLabel)
    guard let manager else {
      throw DaemonServiceError.invalidRequest("ASR manager was not initialized")
    }

    let started = ContinuousClock.now
    // FluidAudio's nonisolated async API on a non-Sendable class makes Swift
    // warn about "sending 'manager'". Exclusive use is guaranteed by `gate`:
    // no other task touches this manager until this call returns.
    let result = try await manager.transcribe(audioURL, source: .system)
    return TranscriptionResult(
      text: result.text,
      model: modelURL.lastPathComponent,
      durationMs: Self.elapsedMs(since: started)
    )
  }

  private func ensureInitialized(modelURL: URL, version: AsrModelVersion, versionLabel: String) async throws {
    let key = LoadedModelKey(path: modelURL.path, version: versionLabel)
    if currentKey == key, manager != nil {
      return
    }

    guard AsrModels.modelsExist(at: modelURL) else {
      throw DaemonServiceError.modelPathInvalid(modelURL.path)
    }

    let configuration = AsrModels.defaultConfiguration()
    let models = try await AsrModels.load(
      from: modelURL,
      configuration: configuration,
      version: version
    )

    let newManager = AsrManager()
    try await newManager.initialize(models: models)
    manager = newManager
    currentKey = key
  }

  static func parseModelVersion(_ raw: String) throws -> AsrModelVersion {
    switch raw.lowercased() {
    case "v2":
      return .v2
    case "v3":
      return .v3
    default:
      throw DaemonServiceError.unsupportedModelVersion(raw)
    }
  }

  private static func elapsedMs(since start: ContinuousClock.Instant) -> Int {
    let elapsed = start.duration(to: ContinuousClock.now)
    let millis = Int(elapsed.components.seconds * 1000) + Int(elapsed.components.attoseconds / 1_000_000_000_000_000)
    return max(0, millis)
  }
}
