import AppKit
import Foundation
import LowkeyCore

/// Menu-bar app: hotkey → chime + capture → transcription and cleanup →
/// paste/send. Takes go through the native pipeline (daemon socket + Swift
/// cleanup) unless the settings need the CLI's `inline process`.
final class AppController: NSObject, NSApplicationDelegate {
  private struct Take {
    let hotkeyAt: Double
    let startedAt: Double
    let startedEpochMs: Int
    let startupMs: Int
    let originalApp: NSRunningApplication?
    /// Settings read while recording, so each take uses what the CLI would
    /// use now (e.g. after `tmux-whisper autosend off`), not launch-time values.
    let settings: SettingsFetch?
  }

  /// `tmux-whisper app-config --json`, fetched in the background.
  final class SettingsFetch: @unchecked Sendable {
    private let done = DispatchGroup()
    private var config: AppConfig?
    private var failure: String?

    init(cli: CLIBridge, queue: DispatchQueue) {
      done.enter()
      queue.async {
        do {
          self.config = try cli.appConfig()
        } catch {
          self.failure = error.localizedDescription
        }
        self.done.leave()
      }
    }

    /// The fresh settings, or nil (with a reason) if they could not be read in time.
    func wait(timeout: TimeInterval) -> (AppConfig?, String?) {
      guard done.wait(timeout: .now() + timeout) == .success else { return (nil, "timed out reading settings") }
      return (config, failure)
    }
  }

  private enum Phase {
    case ready, recording, processing, error(String)
  }

  private var statusItem: NSStatusItem!
  private let statusLine = NSMenuItem(title: "Starting…", action: nil, keyEquivalent: "")
  private let hotkeyLine = NSMenuItem(title: "Hotkey: –", action: nil, keyEquivalent: "")
  private let cancelItem = NSMenuItem(title: "Cancel Recording", action: #selector(cancelRecording), keyEquivalent: "")

  private let recorder = AudioRecorder()
  private let sounds = SoundPlayer()
  private lazy var hotkey = HotkeyMonitor { [weak self] in self?.toggle() }
  private var cli: CLIBridge?
  private var config: AppConfig?
  private var take: Take?
  private var processing = 0
  private var phase: Phase = .ready { didSet { refreshStatus() } }
  private let work = DispatchQueue(label: "lowkey.work", qos: .userInitiated)
  /// `inline record` runs here, after delivery, one take at a time.
  private let persistQueue = DispatchQueue(label: "lowkey.persist", qos: .utility)
  private let verifyQueue = DispatchQueue(label: "lowkey.verify", qos: .utility)
  private let settingsQueue = DispatchQueue(label: "lowkey.settings", qos: .userInitiated, attributes: .concurrent)

  func applicationDidFinishLaunching(_ notification: Notification) {
    buildMenu()
    Log.write("launch: Lowkey \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")")

    recorder.prepare()
    recorder.onConfigurationChange = { [weak self] in self?.handleDeviceChange() }
    AudioRecorder.requestPermission { granted in
      if !granted { Log.write("permission: microphone denied") }
    }
    if !Deliverer.isTrusted(prompt: true) {
      Log.write("permission: accessibility not granted yet (prompted)")
    }

    guard let cli = CLIBridge.locate() else {
      phase = .error("tmux-whisper CLI not found")
      return
    }
    self.cli = cli
    reloadSettings()
  }

  /// Quit waits for the take in progress and its queued persistence, so a
  /// delivered dictation is never left out of history, bench and usage.
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    let replied = DispatchSemaphore(value: 1)
    let reply = {
      guard replied.wait(timeout: .now()) == .success else { return }
      DispatchQueue.main.async { NSApp.reply(toApplicationShouldTerminate: true) }
    }
    work.async { [persistQueue] in
      persistQueue.async { reply() }
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
      Log.write("quit: pending work did not finish within 20s; quitting anyway")
      reply()
    }
    return .terminateLater
  }

  // MARK: - Recording

  private func toggle() {
    let hotkeyAt = monotonicMs()
    if take == nil {
      startRecording(hotkeyAt: hotkeyAt)
    } else {
      stopRecording()
    }
  }

  private func startRecording(hotkeyAt: Double) {
    // Chime first: it's the cue to speak. It plays on its own queue, so the
    // microphone starts in parallel instead of waiting for the audio device.
    sounds.play(.start) { playMs in
      Log.write(String(format: "start: chime play() %.1fms (hotkey→chime ≈ %.1fms)", playMs, monotonicMs() - hotkeyAt))
    }
    let original = NSWorkspace.shared.frontmostApplication
    do {
      let engineMs = try recorder.start()
      let startedAt = monotonicMs()
      take = Take(
        hotkeyAt: hotkeyAt,
        startedAt: startedAt,
        startedEpochMs: Int(Date().timeIntervalSince1970 * 1000),
        startupMs: Int((startedAt - hotkeyAt).rounded()),
        originalApp: original,
        settings: cli.map { SettingsFetch(cli: $0, queue: settingsQueue) }
      )
      phase = .recording
      Log.write(String(format: "start: engine.start %.1fms, hotkey→capturing %.1fms, app=%@",
                       engineMs, startedAt - hotkeyAt, original?.localizedName ?? "-"))
    } catch {
      sounds.play(.error)
      fail("could not start recording: \(error.localizedDescription)")
    }
  }

  private func stopRecording() {
    guard let take else { return }
    let firstBuffer = recorder.firstBufferTime
    let samples = recorder.stop()
    self.take = nil
    let recordMs = Int((monotonicMs() - take.startedAt).rounded())
    if let firstBuffer {
      Log.write(String(format: "stop: record %dms, hotkey→first audio %.1fms, samples %d", recordMs, firstBuffer - take.hotkeyAt, samples.count))
    }
    guard !samples.isEmpty else {
      sounds.play(.error)
      fail("no audio captured (microphone permission?)")
      return
    }
    if config?.inline.processSound ?? true {
      sounds.play(.process)
    }
    processing += 1
    phase = .processing
    process(samples: samples, take: take, recordMs: recordMs)
  }

  @objc private func cancelRecording() {
    guard take != nil else { return }
    _ = recorder.stop()
    take = nil
    sounds.play(.cancel)
    phase = processing > 0 ? .processing : .ready
    Log.write("cancel: recording discarded")
  }

  private func handleDeviceChange() {
    guard take != nil else { return }
    // The engine stops on a device switch; keep what was captured so far.
    Log.write("audio: device changed mid-recording; stopping the take")
    stopRecording()
  }

  // MARK: - Processing and delivery

  private func process(samples: [Float], take: Take, recordMs: Int) {
    guard let cli else {
      finishProcessing(error: "tmux-whisper CLI not found")
      return
    }
    let frontmostAtStop = NSWorkspace.shared.frontmostApplication?.localizedName
    let cachedConfig = self.config
    let stopAt = monotonicMs()
    work.async { [weak self] in
      guard let self else { return }
      // Settings fetched during the recording; usually ready long before
      // stop. Without them, the CLI path reads its own fresh settings.
      let (fresh, problem) = take.settings?.wait(timeout: 5) ?? (nil, "no settings fetch")
      if let fresh, fresh != cachedConfig {
        DispatchQueue.main.async { self.adopt(fresh) }
      }
      let config = fresh ?? cachedConfig
      // Match the CLI: "restore" uses the app from recording start; "current"
      // uses whatever is frontmost when processing begins (for mode detection).
      let appName = config?.inline.pasteTarget == "restore" ? take.originalApp?.localizedName : frontmostAtStop
      if let fresh {
        if fresh.nativePipelineBlocker == nil,
           self.processNatively(samples: samples, take: take, recordMs: recordMs, appName: appName,
                                config: fresh, cli: cli, stopAt: stopAt) {
          return
        }
      } else {
        Log.write("pipeline: CLI path (\(problem ?? "settings unavailable"))")
      }
      self.processWithCLI(samples: samples, take: take, recordMs: recordMs, appName: appName, cli: cli, stopAt: stopAt)
    }
  }

  /// Takes on settings read for a take: everything except re-registering an
  /// unchanged hotkey, which could drop a press while recording.
  private func adopt(_ fresh: AppConfig) {
    if fresh.hotkey != config?.hotkey {
      apply(fresh)
      return
    }
    let pipelineChanged = fresh.nativePipelineBlocker != config?.nativePipelineBlocker
    config = fresh
    sounds.load(from: fresh)
    if pipelineChanged {
      Log.write("settings: pipeline " + (fresh.nativePipelineBlocker.map { "CLI (\($0))" } ?? "native"))
    }
  }

  /// Phase 3b: transcribe through the daemon socket, clean up in Swift,
  /// deliver, then persist in the background. Returns false (having done
  /// nothing visible) when the take should go through the CLI instead.
  private func processNatively(samples: [Float], take: Take, recordMs: Int, appName: String?,
                               config: AppConfig, cli: CLIBridge, stopAt: Double) -> Bool {
    guard let transcription = config.transcription, let cleanup = config.cleanup,
          let modelPath = transcription.modelPath else { return false }
    let takeId = UUID().uuidString.lowercased()
    let startedAt = monotonicMs()
    let marker = ProcessingMarker.create(directory: transcription.processingDir, takeId: takeId)
    defer { marker?.remove() }

    let client = DaemonClient(socketPath: transcription.socketPath)
    // Parakeet runs far faster than real time; allow a cold model load.
    let timeout = min(transcription.maxTimeout, 30 + 2 * Double(samples.count) / Double(AudioPrep.sampleRate))
    var record = TakeRecord(takeId: takeId, status: "ok", delivered: false)
    record.app = appName
    record.model = transcription.modelLabel
    record.recordMs = recordMs
    record.startupMs = take.startupMs
    record.startedAtMs = take.startedEpochMs
    record.captureWavMs = AudioPrep.ffprobeDurationMs(sampleCount: samples.count)
    record.captureWavBytes = 44 + 2 * samples.count

    let transcribed: NativeTranscriber.Result
    do {
      transcribed = try NativeTranscriber(settings: transcription, keepWAV: transcription.keepLogs)
        .transcribe(samples: samples) { wav, flow in
        try client.transcribe(wav: wav, language: transcription.language, flow: flow, modelPath: modelPath,
                              modelVersion: transcription.modelVersion, timeout: timeout)
      }
    } catch let failure as NativeTranscriber.Failure {
      if case DaemonClient.ClientError.timedOut(let seconds) = failure.underlying {
        // Re-running through the CLI would wait on the same daemon again.
        record.status = "transcribe_failed"
        record.wavPath = failure.keptWAV?.path
        record.transcribeMs = Int(monotonicMs() - startedAt)
        record.totalMs = recordMs + Int(monotonicMs() - stopAt)
        persist(record, cli: cli)
        DispatchQueue.main.async {
          self.sounds.play(.error)
          self.finishProcessing(error: "transcription timed out after \(Int(seconds))s")
        }
        return true
      }
      if let kept = failure.keptWAV { try? FileManager.default.removeItem(at: kept) }
      Log.write("pipeline: native transcription unavailable (\(failure.underlying.localizedDescription)); using the CLI path")
      return false
    } catch {
      Log.write("pipeline: native transcription unavailable (\(error.localizedDescription)); using the CLI path")
      return false
    }
    let transcribedAt = monotonicMs()
    record.transcribeMs = Int(transcribedAt - startedAt)
    record.wavPath = transcribed.keptWAV?.path
    if transcribed.tailRescueFailed {
      Log.write("pipeline: tail rescue pass failed; kept the full transcript (as the CLI does)")
    }

    let outcome = TextPipeline(settings: cleanup).process(transcript: transcribed.transcript, app: appName)
    let cleanedAt = monotonicMs()
    record.cleanMs = Int(cleanedAt - transcribedAt)
    // Started only after delivery, so its CLI process never competes with it.
    let verifyAfterDelivery = { [self] in
      if config.pipeline?.verify ?? false {
        verify(outcome: outcome, transcript: transcribed.transcript, app: appName, takeId: takeId,
               settings: cleanup, cli: cli)
      }
    }

    switch outcome {
    case .needsCLI:
      if let kept = transcribed.keptWAV { try? FileManager.default.removeItem(at: kept) }
      return false
    case .noSpeech:
      record.status = "no_speech"
      record.totalMs = recordMs + Int(monotonicMs() - stopAt)
      persist(record, cli: cli)
      verifyAfterDelivery()
      DispatchQueue.main.async { self.finishProcessing(error: nil, note: "No speech detected") }
      return true
    case .text(let raw, let text, let mode):
      record.rawText = raw
      record.text = text
      record.mode = mode
      let steps = DeliveryPlan.steps(text: text, delivery: config.delivery, hasOriginalApp: take.originalApp != nil)
      do {
        try Deliverer.perform(steps, originalApp: take.originalApp)
      } catch {
        record.status = "paste_failed"
        record.pasteMs = Int(monotonicMs() - cleanedAt)
        record.totalMs = recordMs + Int(monotonicMs() - stopAt)
        persist(record, cli: cli)
        verifyAfterDelivery()
        DispatchQueue.main.async {
          self.sounds.play(.error)
          self.finishProcessing(error: error.localizedDescription)
        }
        return true
      }
      let deliveredAt = monotonicMs()
      record.delivered = true
      record.deliveredAtMs = Int(Date().timeIntervalSince1970 * 1000)
      record.pasteMs = Int(deliveredAt - cleanedAt)
      record.totalMs = recordMs + Int(deliveredAt - stopAt)
      persist(record, cli: cli)
      verifyAfterDelivery()
      let rescue = transcribed.tailRescueMs.map { " (tail rescue \($0)ms)" } ?? ""
      Log.write(String(format: "done(native): stop→delivered %.0fms: queue %.0f, asr %.0f%@, clean %.1f, deliver %.0f; mode=%@, chars=%d",
                       deliveredAt - stopAt, startedAt - stopAt, transcribedAt - startedAt, rescue,
                       cleanedAt - transcribedAt, deliveredAt - cleanedAt, mode, text.count))
      DispatchQueue.main.async {
        self.sounds.play(.stop)
        self.finishProcessing(error: nil)
      }
      return true
    }
  }

  /// History, bench and usage, one take at a time, after delivery.
  private func persist(_ record: TakeRecord, cli: CLIBridge) {
    persistQueue.async {
      do {
        let result = try cli.record(record)
        let wantsUsage = record.status == "ok" && record.delivered
        if wantsUsage && !(result.usageRecorded && result.historySaved) {
          // No retry: usage may already be counted, and takes aren't deduplicated.
          Log.write("persist: take \(record.takeId) partly recorded (usage \(result.usageRecorded), history \(result.historySaved))")
        }
      } catch {
        Log.write("persist: take \(record.takeId) not recorded: \(error.localizedDescription)")
        if let wav = record.wavPath { try? FileManager.default.removeItem(atPath: wav) }
      }
    }
  }

  /// `[app] verify_pipeline`: compare the native cleanup with the CLI's on
  /// the same raw transcript, off the delivery path.
  private func verify(outcome: CleanupOutcome, transcript: String, app: String?, takeId: String,
                      settings: CleanupSettings, cli: CLIBridge) {
    verifyQueue.async {
      do {
        let reference = try cli.cleanup(transcript: transcript, app: app)
        if reference.cleanup != settings {
          Log.write("verify: take \(takeId) skipped: cleanup settings changed since the take")
        } else if let mismatch = ShadowCompare.mismatch(native: outcome, cli: reference) {
          Log.write("verify: take \(takeId) \(mismatch) transcript=\(transcript.debugDescription)")
        } else {
          Log.write("verify: take \(takeId) matches the CLI")
        }
      } catch {
        Log.write("verify: take \(takeId) could not run the CLI cleanup: \(error.localizedDescription)")
      }
    }
  }

  /// Phase 2 path: `tmux-whisper inline process` transcribes, cleans up and
  /// records; the app delivers.
  private func processWithCLI(samples: [Float], take: Take, recordMs: Int, appName: String?, cli: CLIBridge, stopAt: Double) {
    let wav = FileManager.default.temporaryDirectory.appendingPathComponent("lowkey-\(UUID().uuidString).wav")
    defer { try? FileManager.default.removeItem(at: wav) }
    let startedAt = monotonicMs()
    do {
      try WAVEncoder.encode(samples: samples).write(to: wav, options: [.atomic])
      chmod(wav.path, 0o600)
      let result = try cli.process(wav: wav, app: appName, recordMs: recordMs,
                                   startupMs: take.startupMs, startedAtEpochMs: take.startedEpochMs)
      let processedAt = monotonicMs()
      guard result.ok else {
        DispatchQueue.main.async {
          if result.status == "no_speech" {
            self.finishProcessing(error: nil, note: "No speech detected")
          } else {
            self.sounds.play(.error)
            self.finishProcessing(error: result.message ?? result.status)
          }
        }
        return
      }
      let steps = DeliveryPlan.steps(text: result.text, delivery: result.delivery, hasOriginalApp: take.originalApp != nil)
      try Deliverer.perform(steps, originalApp: take.originalApp)
      Log.write(String(format: "done(cli): stop→processed %.0fms (queue %.0f), deliver %.0fms, transcribe %dms, mode=%@, chars=%d",
                       processedAt - stopAt, startedAt - stopAt, monotonicMs() - processedAt,
                       result.timings["transcribe_ms"] ?? -1, result.mode ?? "-", result.text.count))
      DispatchQueue.main.async {
        self.sounds.play(.stop)
        self.finishProcessing(error: nil)
      }
    } catch {
      DispatchQueue.main.async {
        self.sounds.play(.error)
        self.finishProcessing(error: error.localizedDescription)
      }
    }
  }

  private func finishProcessing(error: String?, note: String? = nil) {
    processing = max(0, processing - 1)
    if let error {
      fail(error)
      return
    }
    if let note { Log.write("note: \(note)") }
    if take != nil {
      phase = .recording
    } else {
      phase = processing > 0 ? .processing : .ready
    }
  }

  private func fail(_ message: String) {
    Log.write("error: \(message)")
    phase = .error(message)
  }

  // MARK: - Settings

  @objc private func reloadSettings() {
    guard let cli else { return }
    work.async { [weak self] in
      do {
        let config = try cli.appConfig()
        DispatchQueue.main.async { self?.apply(config) }
      } catch {
        DispatchQueue.main.async { self?.fail("cannot read settings: \(error.localizedDescription)") }
      }
    }
  }

  private func apply(_ config: AppConfig) {
    self.config = config
    sounds.load(from: config)
    do {
      let spec = try HotkeySpec.parse(config.hotkey)
      try hotkey.register(spec)
      hotkeyLine.title = "Hotkey: \(spec.display)"
      Log.write("settings: hotkey \(spec.display), cli \(config.cliVersion), pipeline "
                + (config.nativePipelineBlocker.map { "CLI (\($0))" } ?? "native"
                   + ((config.pipeline?.verify ?? false) ? " + verify" : "")))
      if case .error = phase { phase = .ready } else { refreshStatus() }
    } catch {
      hotkeyLine.title = "Hotkey: invalid (\(config.hotkey))"
      fail("hotkey \"\(config.hotkey)\": \(error)")
    }
  }

  // MARK: - Menu

  private func buildMenu() {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    let menu = NSMenu()
    statusLine.isEnabled = false
    hotkeyLine.isEnabled = false
    cancelItem.target = self
    menu.addItem(statusLine)
    menu.addItem(hotkeyLine)
    menu.addItem(.separator())
    menu.addItem(cancelItem)
    let reload = NSMenuItem(title: "Reload Settings", action: #selector(reloadSettings), keyEquivalent: "r")
    reload.target = self
    menu.addItem(reload)
    let log = NSMenuItem(title: "Open Log", action: #selector(openLog), keyEquivalent: "l")
    log.target = self
    menu.addItem(log)
    menu.addItem(.separator())
    menu.addItem(NSMenuItem(title: "Quit Lowkey", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    statusItem.menu = menu
    refreshStatus()
  }

  @objc private func openLog() {
    NSWorkspace.shared.open(Log.fileURL)
  }

  private func refreshStatus() {
    let symbol: String
    switch phase {
    case .ready:
      symbol = "mic"
      statusLine.title = "Ready"
    case .recording:
      symbol = "mic.fill"
      statusLine.title = "Recording…"
    case .processing:
      symbol = "waveform"
      statusLine.title = processing > 1 ? "Processing (\(processing))…" : "Processing…"
    case .error(let message):
      symbol = "exclamationmark.triangle"
      statusLine.title = "Error: \(message)"
    }
    cancelItem.isHidden = take == nil
    let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Lowkey")
    image?.isTemplate = true
    statusItem?.button?.image = image
  }
}
