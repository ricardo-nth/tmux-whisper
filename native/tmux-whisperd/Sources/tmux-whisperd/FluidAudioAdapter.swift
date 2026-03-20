import Foundation
@preconcurrency import FluidAudio

private struct LoadedModelKey: Equatable {
  let path: String
  let version: String
}

struct AdapterResult {
  let text: String
  let model: String
  let durationMs: Int
}

actor FluidAudioAdapter {
  private var currentKey: LoadedModelKey?
  private var manager: AsrManager?

  func transcribe(audioURL: URL, modelURL: URL, modelVersion: String) async throws -> AdapterResult {
    let version = try parseModelVersion(modelVersion)
    try await ensureInitialized(modelURL: modelURL, version: version, versionLabel: modelVersion)

    guard let manager else {
      throw DaemonServiceError.invalidRequest("ASR manager was not initialized")
    }

    let started = ContinuousClock.now
    let result = try await manager.transcribe(audioURL, source: .system)
    let elapsed = started.duration(to: ContinuousClock.now)
    let millis = Int(elapsed.components.seconds * 1000) + Int(elapsed.components.attoseconds / 1_000_000_000_000_000)

    return AdapterResult(
      text: result.text,
      model: modelURL.lastPathComponent,
      durationMs: max(0, millis)
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

  private func parseModelVersion(_ raw: String) throws -> AsrModelVersion {
    switch raw.lowercased() {
    case "v2":
      return .v2
    case "v3":
      return .v3
    default:
      throw DaemonServiceError.unsupportedModelVersion(raw)
    }
  }
}
