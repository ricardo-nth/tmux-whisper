import Darwin
import Foundation
import Testing
@testable import LowkeyCore
import TmuxWhisperKit

struct AudioPrepTests {
  @Test func padsTheTailThenToOneSecond() {
    let pcm = [Int16](repeating: 7, count: 20_000)
    let padded = AudioPrep.padded(pcm, tailPadMs: 500)
    #expect(padded.count == 28_000)
    #expect(Array(padded.prefix(20_000)) == pcm)
    #expect(padded.suffix(8_000).allSatisfy { $0 == 0 })
    // New in 3b: sub-second takes reach FluidAudio's 1 s minimum.
    #expect(AudioPrep.padded([1, 2, 3], tailPadMs: 500).count == 16_000)
    #expect(AudioPrep.padded([1, 2, 3], tailPadMs: 0).count == 16_000)
    #expect(AudioPrep.padded(pcm, tailPadMs: 10).count == 20_160)
  }

  @Test func durationRoundsLikeFfprobeAndAwk() {
    // ffprobe prints 15.812500 for 253000 samples; awk "%.0f" rounds half to even.
    #expect(AudioPrep.ffprobeDurationMs(sampleCount: 253_000) == 15_812)
    #expect(AudioPrep.ffprobeDurationMs(sampleCount: 199_999) == 12_500)
    #expect(AudioPrep.ffprobeDurationMs(sampleCount: 248_008) == 15_500)
    #expect(AudioPrep.ffprobeDurationMs(sampleCount: 20_345) == 1_272)
  }

  @Test func tailRescueWindowFollowsTheCLI() {
    let settings = TranscriptionSettings(socketPath: "/s", modelPath: "/m")
    #expect(AudioPrep.tailRescueWindowMs(paddedSampleCount: 16 * 12_000, settings: settings) == 8_000)
    #expect(AudioPrep.tailRescueWindowMs(paddedSampleCount: 16 * 11_999, settings: settings) == nil)
    var off = settings
    off.tailRescue = false
    #expect(AudioPrep.tailRescueWindowMs(paddedSampleCount: 16 * 30_000, settings: off) == nil)
    var short = settings
    short.tailRescueMs = "200"   // raised to 1 s
    short.tailRescueMinMs = "1500"
    #expect(AudioPrep.tailRescueWindowMs(paddedSampleCount: 16 * 2_001, settings: short) == 1_000)
    #expect(AudioPrep.tailRescueWindowMs(paddedSampleCount: 16 * 2_000, settings: short) == nil)
    var wide = settings
    wide.tailRescueMs = "11500"  // duration must exceed window + 1 s
    #expect(AudioPrep.tailRescueWindowMs(paddedSampleCount: 16 * 12_500, settings: wide) == nil)
    #expect(AudioPrep.tail([1, 2, 3, 4], windowMs: 0).isEmpty)
    #expect(AudioPrep.tail(Array(repeating: 1, count: 40_000), windowMs: 1_000).count == 16_000)
  }
}

struct TranscriptionSettingsTests {
  @Test func parsesNumbersLikeBash() {
    #expect(TranscriptionSettings.bashInt("", default: 8000) == 8000)
    #expect(TranscriptionSettings.bashInt("abc", default: 8000) == 8000)
    #expect(TranscriptionSettings.bashInt("-5", default: 8000) == 8000)
    #expect(TranscriptionSettings.bashInt("0", default: 8000) == 0)
    #expect(TranscriptionSettings.bashInt("250", default: 8000) == 250)
    #expect(TranscriptionSettings.bashInt("010", default: 8000) == nil)  // octal in (( ))
    #expect(TranscriptionSettings.bashInt("99999999999999999999999", default: 1) == nil)
  }

  @Test func reportsWhyTheCLIIsNeeded() {
    let base = TranscriptionSettings(socketPath: "/s", modelPath: "/m")
    #expect(base.cliReason == nil)
    #expect(TranscriptionSettings(socketPath: "/s", modelPath: nil).cliReason != nil)
    var trimmed = base
    trimmed.silenceTrim = true
    #expect(trimmed.cliReason != nil)
    var octal = base
    octal.tailPadMs = "0500"
    #expect(octal.cliReason != nil)
    var keepLogs = base
    keepLogs.keepLogs = true
    #expect(keepLogs.cliReason == nil)  // inline record writes the debug archive
    var noFFmpeg = base
    noFFmpeg.ffmpeg = false
    #expect(noFFmpeg.cliReason != nil)
    var noPad = base
    noPad.tailPadMs = "0"
    #expect(noPad.cliReason == nil && noPad.tailPad == 0)
  }

  @Test func decodesTheAppConfigSections() throws {
    let json = #"""
    {"schema_version":1,"cli_version":"0.10.0-dev","hotkey":"ctrl+option+space","sounds":{},
     "inline":{"autosend":true,"send_mode":"enter","paste_target":"current","process_sound":true,"activate_delay_ms":90,"send_delay_ms":35},
     "cleanup":{"config_dir":"/c","clean":"0","repeats_level":"1","vocab_clean":"1","british_spelling":"1",
       "code_paragraph_min_words":"70","long_paragraph_min_words":"55","force_mode":null,"postprocess":false,
       "locale_ctype":"","locale_collate":""},
     "transcription":{"socket_path":"/s.sock","model_path":"/m","model_version":"v3","model_label":"m","language":"en",
       "tail_pad_ms":"500","tail_rescue":true,"tail_rescue_ms":"","tail_rescue_min_ms":"","chunking":false,
       "silence_trim":false,"keep_logs":false,"ffmpeg":true,"timeout_seconds":"600","processing_dir":"/p"},
     "pipeline":{"native":true,"verify":true}}
    """#
    var config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
    #expect(config.nativePipelineBlocker == nil)
    #expect(config.transcription?.socketPath == "/s.sock")
    #expect(config.delivery.sendDelayMs == 35)

    let disabled = json.replacingOccurrences(of: #""native":true"#, with: #""native":false"#)
    config = try JSONDecoder().decode(AppConfig.self, from: Data(disabled.utf8))
    #expect(config.nativePipelineBlocker == "[app] native_pipeline = false")

    let llm = json.replacingOccurrences(of: #""postprocess":false"#, with: #""postprocess":true"#)
    config = try JSONDecoder().decode(AppConfig.self, from: Data(llm.utf8))
    #expect(config.nativePipelineBlocker == "LLM post-processing is on")
  }

  @Test func olderCLIsKeepTheCLIPath() throws {
    let json = #"""
    {"schema_version":1,"cli_version":"0.9.0","hotkey":"ctrl+option+space","sounds":{},
     "inline":{"autosend":true,"send_mode":"enter","paste_target":"current","process_sound":true,"activate_delay_ms":90,"send_delay_ms":35}}
    """#
    let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
    #expect(config.nativePipelineBlocker != nil)
  }
}

/// Records what the fake daemon was asked to transcribe.
private final class CallLog: @unchecked Sendable {
  private let lock = NSLock()
  private var calls: [(flow: String, samples: [Int16])] = []

  func add(flow: String, samples: [Int16]) { lock.withLock { calls.append((flow, samples)) } }
  var all: [(flow: String, samples: [Int16])] { lock.withLock { calls } }
}

private func readPCM(_ url: URL) throws -> [Int16] {
  let data = try Data(contentsOf: url)
  return data.dropFirst(44).withUnsafeBytes { Array($0.bindMemory(to: Int16.self)) }
}

struct NativeTranscriberTests {
  private let settings = TranscriptionSettings(socketPath: "/s", modelPath: "/m")

  @Test func shortTakeIsPaddedAndTranscribedOnce() throws {
    let log = CallLog()
    let samples = [Float](repeating: 0.25, count: 32_000)
    let result = try NativeTranscriber(settings: settings).transcribe(samples: samples) { wav, flow in
      log.add(flow: flow, samples: try readPCM(wav))
      return "hello world\n\n"
    }
    #expect(result.transcript == "hello world")
    #expect(result.tailRescueMs == nil)
    #expect(log.all.map(\.flow) == ["inline"])
    #expect(log.all[0].samples.count == 40_000)
    #expect(log.all[0].samples.prefix(32_000).allSatisfy { $0 == 8192 })
    #expect(result.captureSamples == 32_000)
  }

  @Test func longTakeRescuesTheTail() throws {
    let log = CallLog()
    let samples = (0..<(16_000 * 13)).map { Float($0 % 100) / 100 }
    let result = try NativeTranscriber(settings: settings).transcribe(samples: samples) { wav, flow in
      log.add(flow: flow, samples: try readPCM(wav))
      return flow == "inline" ? "so the plan is to ship it" : "ship it today\nand test"
    }
    let calls = log.all
    #expect(calls.map(\.flow) == ["inline", "inline-tail"])
    #expect(calls[1].samples.count == 128_000)
    #expect(Array(calls[1].samples) == Array(calls[0].samples.suffix(128_000)))
    #expect(result.tailRescueMs == 8_000)
    #expect(result.transcript == "so the plan is to ship it today and test")
  }

  @Test func failedOrBlankTailKeepsTheFullTranscript() throws {
    let samples = [Float](repeating: 0, count: 16_000 * 13)
    let failing = try NativeTranscriber(settings: settings).transcribe(samples: samples) { _, flow in
      if flow == "inline-tail" { throw DaemonClient.ClientError.daemon(code: "x", message: "y") }
      return "full text"
    }
    #expect(failing.transcript == "full text" && failing.tailRescueFailed)
    let blank = try NativeTranscriber(settings: settings).transcribe(samples: samples) { _, flow in
      flow == "inline" ? "full text" : " \n "
    }
    #expect(blank.transcript == "full text" && !blank.tailRescueFailed)
  }

  @Test func keepsThePaddedWAVOnlyWhenAsked() throws {
    let kept = try NativeTranscriber(settings: settings, keepWAV: true).transcribe(samples: [0.1]) { _, _ in "x" }
    let url = try #require(kept.keptWAV)
    #expect(try readPCM(url).count == 16_000)
    try FileManager.default.removeItem(at: url)
    let dropped = try NativeTranscriber(settings: settings).transcribe(samples: [0.1]) { _, _ in "x" }
    #expect(dropped.keptWAV == nil)
  }

  @Test func fullTranscriptionErrorsPropagateWithTheKeptWAV() throws {
    do {
      _ = try NativeTranscriber(settings: settings).transcribe(samples: [0]) { _, _ in
        throw DaemonClient.ClientError.unreachable("x")
      }
      Issue.record("expected a failure")
    } catch let failure as NativeTranscriber.Failure {
      #expect(failure.underlying as? DaemonClient.ClientError == .unreachable("x"))
      #expect(failure.keptWAV == nil)
    }
    do {
      _ = try NativeTranscriber(settings: settings, keepWAV: true).transcribe(samples: [0]) { _, _ in
        throw DaemonClient.ClientError.timedOut(1)
      }
      Issue.record("expected a failure")
    } catch let failure as NativeTranscriber.Failure {
      let url = try #require(failure.keptWAV)
      #expect(FileManager.default.fileExists(atPath: url.path))
      try FileManager.default.removeItem(at: url)
    }
  }
}

/// Answers like tmux-whisperd without a model, recording requests.
private actor FakeDaemon: DaemonRequestHandling {
  var requests: [DaemonRequest] = []
  let delay: Duration

  init(delay: Duration = .zero) { self.delay = delay }

  func handle(_ request: DaemonRequest) async -> DaemonResponse {
    requests.append(request)
    switch request.op {
    case .ping:
      return DaemonResponse(id: request.id, ok: true, message: "ok", version: DaemonInfo.daemonVersion)
    case .transcribe:
      try? await Task.sleep(for: delay)
      if request.flow == "fail" {
        return .failure(id: request.id, code: "model_path_invalid", message: "bad model")
      }
      return DaemonResponse(id: request.id, ok: true, text: "café \u{1F600} transcript")
    case .warmup:
      return DaemonResponse(id: request.id, ok: true)
    }
  }
}

struct DaemonClientTests {
  private func socketPath() -> String {
    NSTemporaryDirectory() + "lk-\(UUID().uuidString.prefix(8)).sock"
  }

  @Test func talksToTheRealServer() async throws {
    let path = socketPath()
    let daemon = FakeDaemon()
    let server = UnixSocketServer(socketPath: path, handler: daemon)
    try server.start()
    defer { server.stop() }

    let client = DaemonClient(socketPath: path)
    #expect(client.ping() == DaemonInfo.daemonVersion)
    let text = try client.transcribe(
      wav: URL(fileURLWithPath: "/tmp/take.wav"), language: "en", flow: "inline",
      modelPath: "/models/parakeet", modelVersion: "v3", timeout: 5)
    #expect(Array(text.utf8) == Array("café \u{1F600} transcript".utf8))

    let request = try #require(await daemon.requests.last)
    #expect(request.op == .transcribe)
    #expect(request.wavPath == "/tmp/take.wav")
    #expect(request.flow == "inline")
    #expect(request.language == "en")
    #expect(request.modelPath == "/models/parakeet")
    #expect(request.modelVersion == "v3")

    #expect(throws: DaemonClient.ClientError.daemon(code: "model_path_invalid", message: "bad model")) {
      _ = try client.transcribe(wav: URL(fileURLWithPath: "/tmp/x.wav"), language: "en", flow: "fail",
                                modelPath: "/m", modelVersion: nil, timeout: 5)
    }
  }

  @Test func reportsAnUnreachableDaemonAfterOneRetry() {
    var client = DaemonClient(socketPath: socketPath())
    client.retryDelay = 0.01
    #expect(client.ping(timeout: 0.5) == nil)
    #expect {
      _ = try client.transcribe(wav: URL(fileURLWithPath: "/tmp/x.wav"), language: "en", flow: "inline",
                                modelPath: "/m", modelVersion: nil, timeout: 1)
    } throws: { error in
      if case DaemonClient.ClientError.unreachable = error { return true }
      return false
    }
  }

  @Test func timesOutOnASlowDaemon() throws {
    let path = socketPath()
    let server = UnixSocketServer(socketPath: path, handler: FakeDaemon(delay: .seconds(3)))
    try server.start()
    defer { server.stop() }
    let started = Date()
    #expect(throws: DaemonClient.ClientError.timedOut(0.3)) {
      _ = try DaemonClient(socketPath: path).transcribe(
        wav: URL(fileURLWithPath: "/tmp/x.wav"), language: "en", flow: "inline", modelPath: "/m",
        modelVersion: nil, timeout: 0.3)
    }
    #expect(Date().timeIntervalSince(started) < 2)
  }
}

struct TakeRecordTests {
  @Test func encodesTheInlineRecordPayload() throws {
    var record = TakeRecord(takeId: "t1", status: "ok", delivered: true)
    record.rawText = "open ai"
    record.text = "OpenAI"
    record.mode = "code"
    record.recordMs = 3000
    let object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as? [String: Any])
    #expect(object["take_id"] as? String == "t1")
    #expect(object["raw_text"] as? String == "open ai")
    #expect(object["record_ms"] as? Int == 3000)
    #expect(object["delivered"] as? Bool == true)
    #expect(object["startup_source"] as? String == "app:native")
  }

  @Test func processingMarkerLooksLikeTheCLIs() throws {
    let dir = NSTemporaryDirectory() + "lk-markers-\(UUID().uuidString)"
    defer { try? FileManager.default.removeItem(atPath: dir) }
    let marker = try #require(ProcessingMarker.create(directory: dir, takeId: "abc-123/../x", pid: 4242))
    #expect(marker.url.lastPathComponent == "inline-lowkey-abc-123x")
    let body = try String(contentsOf: marker.url, encoding: .utf8)
    #expect(body.hasPrefix("pid=4242\nkind=inline\n"))
    marker.remove()
    #expect(!FileManager.default.fileExists(atPath: marker.url.path))
  }
}
