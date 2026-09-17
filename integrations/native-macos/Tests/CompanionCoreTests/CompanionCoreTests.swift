import Foundation
import CompanionCore

@main
enum CompanionCoreRegression {
  static func main() async {
    do {
      try testParsesDocumentedFieldsAndIgnoresAdditions()
      try testUnknownValuesAreToleratedAndMalformedResponsesAreRejected()
      try testMissingOrInvalidCountsFailClosed()
      try testUsageSummarySupportsV1AndAdditiveFields()
      try testUsageSummaryRejectsUnknownSchema()
      try testControlPolicyIsConservativeForGlobalCancel()
      try testCommandsUseOnlyInlineControlsAndGlobalCancel()
      try await testProcessRunnerReportsNonZeroExitAndTimeout()
      try testLocatorUsesAbsoluteOverrideAndSuppliesPath()
      try await testExecuteIfPermittedRechecksFreshStatusBeforeRunningControl()
      try await testExecuteIfPermittedDoesNotRunUnsafeControlAfterFreshRead()
      print("CompanionCore regression checks passed")
    } catch {
      fputs("CompanionCore regression check failed: \(error)\n", stderr)
      Foundation.exit(1)
    }
  }

  static func testParsesDocumentedFieldsAndIgnoresAdditions() throws {
    let status = try CompanionStatus.parse(json: fixture(
      state: "recording", inlineState: "active", tmuxState: "idle", processing: 0, queue: 0,
      extra: "\"future_field\": {\"can_change\": true}"
    ))

    try expect(status.summary.state == .recording)
    try expect(status.summary.headline == "Current headline")
    try expect(status.summary.nextAction == "Current next action")
    try expect(status.summary.activeFlow == .inline)
    try expect(status.runtime.inline.isActive)
    try expect(status.policy.canStopInline)
    try expect(status.policy.canCancelInline)
  }

  static func testUnknownValuesAreToleratedAndMalformedResponsesAreRejected() throws {
    let unknown = try CompanionStatus.parse(json: fixture(
      state: "future", inlineState: "future", tmuxState: "idle", processing: 0, queue: 0
    ))
    try expect(unknown.summary.state == .unknown)
    try expect(unknown.runtime.inline.state == .unknown)
    try expectThrows { _ = try CompanionStatus.parse(json: Data("{not json".utf8)) }
    try expectThrows { _ = try CompanionStatus.parse(json: Data("{\"command\":\"doctor\"}".utf8)) }
  }

  static func testMissingOrInvalidCountsFailClosed() throws {
    let missingCounts = Data(
      """
      {"command":"status","summary":{"state":"ready","headline":"h","next_action":"n"},"runtime":{"inline":{"state":"idle","stale":false},"tmux":{"state":"idle","stale":false},"processing_markers":{"total":0,"live":0},"tmux_queue":{"total":0,"recording":0,"processing":0}}}
      """.utf8
    )
    try expectThrows { _ = try CompanionStatus.parse(json: missingCounts) }

    let fractionalCount = Data(
      """
      {"command":"status","summary":{"state":"ready","headline":"h","next_action":"n"},"runtime":{"inline":{"state":"idle","stale":false},"tmux":{"state":"idle","stale":false},"processing_markers":{"total":0.5,"live":0,"stale":0},"tmux_queue":{"total":0,"recording":0,"processing":0}}}
      """.utf8
    )
    try expectThrows { _ = try CompanionStatus.parse(json: fractionalCount) }
  }

  static func testUsageSummarySupportsV1AndAdditiveFields() throws {
    let unstarted = try UsageSummary.parse(json: usageFixture(
      coverageStatus: "not_started", trackingStartedAt: "null", deliveredCount: 0, processedWords: 0
    ))
    try expect(unstarted.schemaVersion == 1)
    try expect(unstarted.coverage.status == .notStarted)
    try expect(unstarted.coverage.trackingStartedAt == nil)
    try expect(unstarted.deliveredCount == 0)
    try expect(unstarted.processedWords == 0)

    let active = try UsageSummary.parse(json: usageFixture(
      coverageStatus: "active", trackingStartedAt: "\"2026-09-17T12:00:00Z\"", deliveredCount: 8, processedWords: 321,
      extra: "\"future_addition\": {\"safe\": true}"
    ))
    try expect(active.coverage.status == .active)
    try expect(active.coverage.trackingStartedAt == "2026-09-17T12:00:00Z")
    try expect(active.deliveredCount == 8)
    try expect(active.processedWords == 321)
  }

  static func testUsageSummaryRejectsUnknownSchema() throws {
    try expectThrows {
      _ = try UsageSummary.parse(json: usageFixture(
        schemaVersion: 2, coverageStatus: "active", trackingStartedAt: "null", deliveredCount: 1, processedWords: 2
      ))
    }
  }

  static func testControlPolicyIsConservativeForGlobalCancel() throws {
    let idle = try CompanionStatus.parse(json: fixture(state: "ready", inlineState: "idle", tmuxState: "idle", processing: 0, queue: 0))
    try expect(idle.policy.canStartInline)
    try expect(!idle.policy.canCancelInline)

    let tmuxActive = try CompanionStatus.parse(json: fixture(state: "recording", inlineState: "active", tmuxState: "active", processing: 0, queue: 0))
    try expect(!tmuxActive.policy.canStopInline)
    try expect(!tmuxActive.policy.canCancelInline)

    let processing = try CompanionStatus.parse(json: fixture(state: "recording", inlineState: "active", tmuxState: "idle", processing: 1, queue: 0))
    try expect(!processing.policy.canCancelInline)

    let queued = try CompanionStatus.parse(json: fixture(state: "recording", inlineState: "active", tmuxState: "idle", processing: 0, queue: 1))
    try expect(!queued.policy.canCancelInline)

    let notReady = try CompanionStatus.parse(json: fixture(state: "not_ready", inlineState: "idle", tmuxState: "idle", processing: 0, queue: 0))
    try expect(!notReady.policy.canStartInline)

    let staleInline = try CompanionStatus.parse(json: fixture(state: "ready", inlineState: "stale", tmuxState: "idle", processing: 0, queue: 0))
    try expect(!staleInline.policy.canStartInline)
  }

  static func testCommandsUseOnlyInlineControlsAndGlobalCancel() throws {
    try expect(WhisperCommand.startInline.arguments == ["inline", "start"])
    try expect(WhisperCommand.stopInline.arguments == ["inline", "stop"])
    try expect(WhisperCommand.cancelInline.arguments == ["cancel"])
  }

  static func testProcessRunnerReportsNonZeroExitAndTimeout() async throws {
    let runner = ProcessRunner()
    let environment = ["PATH": "/usr/bin:/bin"]
    do {
      _ = try await runner.run(executable: URL(fileURLWithPath: "/usr/bin/false"), arguments: [], environment: environment, timeout: 1)
      throw RegressionFailure("Expected non-zero exit")
    } catch let error as CommandError {
      guard case .nonZeroExit = error else { throw RegressionFailure("Unexpected error: \(error)") }
    }

    do {
      _ = try await runner.run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["2"], environment: environment, timeout: 0.05)
      throw RegressionFailure("Expected timeout")
    } catch let error as CommandError {
      try expect(error == .timedOut)
    }
  }

  static func testLocatorUsesAbsoluteOverrideAndSuppliesPath() throws {
    let locator = ExecutableLocator(
      environment: ["DICTATE_BIN": "/usr/bin/false", "PATH": "/custom/bin"],
      homeDirectory: URL(fileURLWithPath: "/nonexistent-home")
    )
    try expect(try locator.resolve().path == "/usr/bin/false")
    try expect(locator.subprocessEnvironment()["PATH", default: ""].contains("/opt/homebrew/bin"))

    let relativeOverride = ExecutableLocator(
      environment: ["DICTATE_BIN": "tmux-whisper"], homeDirectory: URL(fileURLWithPath: "/nonexistent-home")
    )
    try expectThrows { _ = try relativeOverride.resolve() }
  }

  static func testExecuteIfPermittedRechecksFreshStatusBeforeRunningControl() async throws {
    let runner = ScriptedRunner(outputs: [
      CommandOutput(exitCode: 0, standardOutput: fixture(state: "ready", inlineState: "idle", tmuxState: "idle", processing: 0, queue: 0), standardError: Data()),
      CommandOutput(exitCode: 0, standardOutput: Data(), standardError: Data()),
    ])
    let cli = WhisperCLI(locator: testLocator(), runner: runner)
    _ = try await cli.executeIfPermitted(.startInline)
    let calls = await runner.arguments
    try expect(calls == [["status", "--json"], ["inline", "start"]])
  }

  static func testExecuteIfPermittedDoesNotRunUnsafeControlAfterFreshRead() async throws {
    let runner = ScriptedRunner(outputs: [
      CommandOutput(exitCode: 0, standardOutput: fixture(state: "processing", inlineState: "active", tmuxState: "idle", processing: 1, queue: 0), standardError: Data()),
    ])
    let cli = WhisperCLI(locator: testLocator(), runner: runner)
    do {
      _ = try await cli.executeIfPermitted(.cancelInline)
      throw RegressionFailure("Expected a fresh-state policy error")
    } catch let error as ControlError {
      try expect(error == .noLongerAvailable(.cancelInline))
    }
    let calls = await runner.arguments
    try expect(calls == [["status", "--json"]])
  }

  static func fixture(state: String, inlineState: String, tmuxState: String, processing: Int, queue: Int, extra: String = "") -> Data {
    Data(
      """
      {
        "command": "status",
        "summary": {"state": "\(state)", "headline": "Current headline", "next_action": "Current next action", "active_flow": "inline"},
        "runtime": {
          "inline": {"state": "\(inlineState)", "stale": false},
          "tmux": {"state": "\(tmuxState)", "stale": false},
          "processing_markers": {"total": \(processing), "live": \(processing), "stale": 0},
          "tmux_queue": {"total": \(queue), "recording": 0, "processing": 0}
        }\(extra.isEmpty ? "" : ", \(extra)")
      }
      """.utf8
    )
  }

  static func usageFixture(
    schemaVersion: Int = 1,
    coverageStatus: String,
    trackingStartedAt: String,
    deliveredCount: Int,
    processedWords: Int,
    extra: String = ""
  ) -> Data {
    Data(
      """
      {
        "command": "usage",
        "schema_version": \(schemaVersion),
        "coverage": {"status": "\(coverageStatus)", "tracking_started_at": \(trackingStartedAt)},
        "delivered_dictations": {"count": \(deliveredCount), "by_flow": {"inline": \(deliveredCount)}},
        "processed_words": \(processedWords),
        "recording_duration_ms": 0,
        "full_elapsed_duration_ms": 0,
        "typing_assumption": {"wpm": 40},
        "typing_equivalent_duration_ms": 0,
        "estimated_time_difference_ms": 0\(extra.isEmpty ? "" : ", \(extra)")
      }
      """.utf8
    )
  }

  static func testLocator() -> ExecutableLocator {
    ExecutableLocator(
      environment: ["DICTATE_BIN": "/usr/bin/false", "PATH": "/usr/bin:/bin"],
      homeDirectory: URL(fileURLWithPath: "/nonexistent-home")
    )
  }

  static func expect(_ condition: @autoclosure () throws -> Bool, file: StaticString = #filePath, line: UInt = #line) throws {
    guard try condition() else { throw RegressionFailure("Expectation failed at \(file):\(line)") }
  }

  static func expectThrows(_ body: () throws -> Void, file: StaticString = #filePath, line: UInt = #line) throws {
    do {
      try body()
      throw RegressionFailure("Expected an error at \(file):\(line)")
    } catch let error as RegressionFailure {
      throw error
    } catch {
      return
    }
  }
}

private struct RegressionFailure: Error, CustomStringConvertible {
  let description: String
  init(_ description: String) { self.description = description }
}

private actor ScriptedRunner: CommandRunning {
  private var remaining: [CommandOutput]
  private var capturedArguments = [[String]]()

  init(outputs: [CommandOutput]) { remaining = outputs }

  var arguments: [[String]] { capturedArguments }

  func run(executable: URL, arguments: [String], environment: [String: String], timeout: TimeInterval) async throws -> CommandOutput {
    capturedArguments.append(arguments)
    guard !remaining.isEmpty else { throw CommandError.launchFailed("No scripted output") }
    return remaining.removeFirst()
  }
}
