import AppKit
import Foundation
import LowkeyCore

/// Menu-bar app: hotkey → chime + capture → CLI processing → paste/send.
final class AppController: NSObject, NSApplicationDelegate {
  private struct Take {
    let hotkeyAt: Double
    let startedAt: Double
    let startedEpochMs: Int
    let startupMs: Int
    let originalApp: NSRunningApplication?
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
        originalApp: original
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
    let appName = take.originalApp?.localizedName
    work.async { [weak self] in
      let wav = FileManager.default.temporaryDirectory.appendingPathComponent("lowkey-\(UUID().uuidString).wav")
      defer { try? FileManager.default.removeItem(at: wav) }
      let stopAt = monotonicMs()
      do {
        try WAVEncoder.encode(samples: samples).write(to: wav, options: [.atomic])
        chmod(wav.path, 0o600)
        let result = try cli.process(wav: wav, app: appName, recordMs: recordMs,
                                     startupMs: take.startupMs, startedAtEpochMs: take.startedEpochMs)
        let processedAt = monotonicMs()
        guard result.ok else {
          DispatchQueue.main.async {
            if result.status == "no_speech" {
              self?.finishProcessing(error: nil, note: "No speech detected")
            } else {
              self?.sounds.play(.error)
              self?.finishProcessing(error: result.message ?? result.status)
            }
          }
          return
        }
        let steps = DeliveryPlan.steps(text: result.text, delivery: result.delivery, hasOriginalApp: take.originalApp != nil)
        try Deliverer.perform(steps, originalApp: take.originalApp)
        Log.write(String(format: "done: stop→processed %.0fms, deliver %.0fms, transcribe %dms, mode=%@, chars=%d",
                         processedAt - stopAt, monotonicMs() - processedAt, result.timings["transcribe_ms"] ?? -1,
                         result.mode ?? "-", result.text.count))
        DispatchQueue.main.async {
          self?.sounds.play(.stop)
          self?.finishProcessing(error: nil)
        }
      } catch {
        DispatchQueue.main.async {
          self?.sounds.play(.error)
          self?.finishProcessing(error: error.localizedDescription)
        }
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
      Log.write("settings: hotkey \(spec.display), cli \(config.cliVersion)")
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
