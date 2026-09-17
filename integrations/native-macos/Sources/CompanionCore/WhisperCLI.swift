import Darwin
import Foundation

public struct CommandOutput: Equatable, Sendable {
  public let exitCode: Int32
  public let standardOutput: Data
  public let standardError: Data

  public init(exitCode: Int32, standardOutput: Data, standardError: Data) {
    self.exitCode = exitCode
    self.standardOutput = standardOutput
    self.standardError = standardError
  }

  public var outputText: String { String(decoding: standardOutput, as: UTF8.self) }
  public var errorText: String { String(decoding: standardError, as: UTF8.self) }
}

public enum CommandError: Error, Equatable, LocalizedError, Sendable {
  case executableNotFound
  case launchFailed(String)
  case timedOut
  case nonZeroExit(Int32, String)

  public var errorDescription: String? {
    switch self {
    case .executableNotFound:
      return "tmux-whisper was not found. Install it, or set DICTATE_BIN to an absolute executable path."
    case .launchFailed(let message):
      return "Could not launch tmux-whisper: \(message)"
    case .timedOut:
      return "tmux-whisper did not finish before the companion timeout."
    case .nonZeroExit(let code, let stderr):
      let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
      return detail.isEmpty ? "tmux-whisper exited with status \(code)." : detail
    }
  }
}

public protocol CommandRunning: Sendable {
  func run(executable: URL, arguments: [String], environment: [String: String], timeout: TimeInterval) async throws -> CommandOutput
}

public struct ExecutableLocator: Sendable {
  public let environment: [String: String]
  public let homeDirectory: URL

  public init(environment: [String: String] = ProcessInfo.processInfo.environment, homeDirectory: URL? = nil) {
    self.environment = environment
    self.homeDirectory = homeDirectory ?? FileManager.default.homeDirectoryForCurrentUser
  }

  public func resolve() throws -> URL {
    if let override = environment["DICTATE_BIN"], !override.isEmpty {
      guard override.hasPrefix("/") else { throw CommandError.executableNotFound }
      let candidate = URL(fileURLWithPath: override)
      guard FileManager.default.isExecutableFile(atPath: candidate.path) else {
        throw CommandError.executableNotFound
      }
      return candidate
    }

    let fixedCandidates = [
      homeDirectory.appendingPathComponent(".local/bin/tmux-whisper"),
      URL(fileURLWithPath: "/opt/homebrew/bin/tmux-whisper"),
      URL(fileURLWithPath: "/usr/local/bin/tmux-whisper"),
    ]
    if let found = fixedCandidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) {
      return found
    }

    for directory in (environment["PATH"] ?? "").split(separator: ":") where !directory.isEmpty {
      let candidate = URL(fileURLWithPath: String(directory)).appendingPathComponent("tmux-whisper")
      if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
    }
    throw CommandError.executableNotFound
  }

  public func subprocessEnvironment() -> [String: String] {
    var result = environment
    let preferred = [
      homeDirectory.appendingPathComponent(".local/bin").path,
      "/opt/homebrew/bin",
      "/usr/local/bin",
    ]
    let existing = (environment["PATH"] ?? "/usr/bin:/bin").split(separator: ":").map(String.init)
    var orderedPath = [String]()
    for entry in preferred + existing where !entry.isEmpty {
      if !orderedPath.contains(entry) {
        orderedPath.append(entry)
      }
    }
    result["PATH"] = orderedPath.joined(separator: ":")
    return result
  }
}

public struct ProcessRunner: CommandRunning, Sendable {
  public init() {}

  public func run(executable: URL, arguments: [String], environment: [String: String], timeout: TimeInterval) async throws -> CommandOutput {
    try await withCheckedThrowingContinuation { continuation in
      DispatchQueue.global(qos: .utility).async {
        continuation.resume(with: Result {
          try Self.runBlocking(executable: executable, arguments: arguments, environment: environment, timeout: timeout)
        })
      }
    }
  }

  private static func runBlocking(executable: URL, arguments: [String], environment: [String: String], timeout: TimeInterval) throws -> CommandOutput {
    let process = Process()
    process.executableURL = executable
    process.arguments = arguments
    process.environment = environment

    let capture = try CaptureFiles()
    defer { capture.remove() }
    process.standardOutput = capture.standardOutput
    process.standardError = capture.standardError

    let completion = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in completion.signal() }
    do {
      try process.run()
    } catch {
      throw CommandError.launchFailed(error.localizedDescription)
    }

    if completion.wait(timeout: .now() + timeout) == .timedOut {
      kill(process.processIdentifier, SIGTERM)
      if completion.wait(timeout: .now() + 1) == .timedOut {
        kill(process.processIdentifier, SIGKILL)
        _ = completion.wait(timeout: .now() + 1)
      }
      throw CommandError.timedOut
    }

    capture.closeWriters()
    let collectedOutput = try capture.readStandardOutput()
    let collectedErrors = try capture.readStandardError()
    let result = CommandOutput(exitCode: process.terminationStatus, standardOutput: collectedOutput, standardError: collectedErrors)
    guard result.exitCode == 0 else {
      throw CommandError.nonZeroExit(result.exitCode, result.errorText)
    }
    return result
  }
}

public struct WhisperCLI: Sendable {
  public let locator: ExecutableLocator
  public let runner: any CommandRunning
  public let statusTimeout: TimeInterval
  public let commandTimeout: TimeInterval

  public init(
    locator: ExecutableLocator = ExecutableLocator(),
    runner: any CommandRunning = ProcessRunner(),
    statusTimeout: TimeInterval = 20,
    commandTimeout: TimeInterval = 20
  ) {
    self.locator = locator
    self.runner = runner
    self.statusTimeout = statusTimeout
    self.commandTimeout = commandTimeout
  }

  public func status() async throws -> CompanionStatus {
    let output = try await invoke(arguments: ["status", "--json"], timeout: statusTimeout)
    return try CompanionStatus.parse(json: output.standardOutput)
  }

  @discardableResult
  public func execute(_ command: WhisperCommand) async throws -> CommandOutput {
    try await invoke(arguments: command.arguments, timeout: commandTimeout)
  }

  /// Re-reads runtime state immediately before a control action, so a stale
  /// menu item cannot issue the global CLI cancel against another flow.
  @discardableResult
  public func executeIfPermitted(_ command: WhisperCommand) async throws -> CommandOutput {
    let current = try await status()
    guard current.policy.permits(command) else { throw ControlError.noLongerAvailable(command) }
    return try await execute(command)
  }

  private func invoke(arguments: [String], timeout: TimeInterval) async throws -> CommandOutput {
    let executable = try locator.resolve()
    return try await runner.run(
      executable: executable,
      arguments: arguments,
      environment: locator.subprocessEnvironment(),
      timeout: timeout
    )
  }
}

public enum ControlError: Error, Equatable, LocalizedError, Sendable {
  case noLongerAvailable(WhisperCommand)

  public var errorDescription: String? {
    return switch self {
    case .noLongerAvailable(let command): "\(command.rawValue) is no longer safe for the current dictation state."
    }
  }
}

private final class CaptureFiles: @unchecked Sendable {
  private let directory: URL
  private let outputURL: URL
  private let errorURL: URL
  let standardOutput: FileHandle
  let standardError: FileHandle
  private let byteLimit = 1_048_576

  init() throws {
    directory = FileManager.default.temporaryDirectory.appendingPathComponent("tmux-whisper-companion-\(UUID().uuidString)", isDirectory: true)
    outputURL = directory.appendingPathComponent("stdout")
    errorURL = directory.appendingPathComponent("stderr")
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
    FileManager.default.createFile(
      atPath: outputURL.path,
      contents: nil,
      attributes: [.posixPermissions: 0o600]
    )
    FileManager.default.createFile(
      atPath: errorURL.path,
      contents: nil,
      attributes: [.posixPermissions: 0o600]
    )
    standardOutput = try FileHandle(forWritingTo: outputURL)
    standardError = try FileHandle(forWritingTo: errorURL)
  }

  func closeWriters() {
    try? standardOutput.close()
    try? standardError.close()
  }

  func readStandardOutput() throws -> Data { try read(outputURL) }
  func readStandardError() throws -> Data { try read(errorURL) }

  private func read(_ url: URL) throws -> Data {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    return try handle.read(upToCount: byteLimit) ?? Data()
  }

  func remove() {
    closeWriters()
    try? FileManager.default.removeItem(at: directory)
  }
}
