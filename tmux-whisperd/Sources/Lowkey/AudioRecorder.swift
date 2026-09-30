import AVFoundation
import Foundation

/// Captures the default input device with AVAudioEngine and converts it to
/// 16 kHz mono Float32 in memory.
///
/// The engine is prepared at launch and started per take, so the macOS
/// mic-in-use indicator is only on while recording.
final class AudioRecorder {
  private let engine = AVAudioEngine()
  private let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
  private let lock = NSLock()
  private var samples: [Float] = []
  private var converter: AVAudioConverter?
  private var firstBufferAt: Double?
  private(set) var isRecording = false
  /// Called on the main queue when the input device changes mid-take.
  var onConfigurationChange: (() -> Void)?

  init() {
    NotificationCenter.default.addObserver(
      forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
    ) { [weak self] _ in
      guard let self else { return }
      Log.write("audio: input configuration changed (device switch)")
      self.onConfigurationChange?()
    }
  }

  static func requestPermission(_ completion: @escaping (Bool) -> Void) {
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized:
      completion(true)
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .audio) { granted in
        DispatchQueue.main.async { completion(granted) }
      }
    default:
      completion(false)
    }
  }

  func prepare() {
    _ = engine.inputNode // instantiate the input graph early
    engine.prepare()
  }

  /// Starts capture. Returns how long engine start took, in ms.
  @discardableResult
  func start() throws -> Double {
    guard !isRecording else { return 0 }
    let input = engine.inputNode
    let inputFormat = input.outputFormat(forBus: 0)
    guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
      throw NSError(domain: "Lowkey", code: 1, userInfo: [NSLocalizedDescriptionKey: "no input device available"])
    }
    converter = AVAudioConverter(from: inputFormat, to: targetFormat)
    lock.withLock {
      samples.removeAll(keepingCapacity: true)
      firstBufferAt = nil
    }

    input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
      self?.append(buffer)
    }
    let started = monotonicMs()
    do {
      try engine.start()
    } catch {
      input.removeTap(onBus: 0)
      throw error
    }
    isRecording = true
    return monotonicMs() - started
  }

  /// Stops capture and returns the take.
  func stop() -> [Float] {
    guard isRecording else { return [] }
    engine.inputNode.removeTap(onBus: 0)
    engine.stop()
    isRecording = false
    return lock.withLock {
      let take = samples
      samples.removeAll(keepingCapacity: false)
      return take
    }
  }

  /// Monotonic time at which the first audio buffer arrived, if any.
  var firstBufferTime: Double? {
    lock.withLock { firstBufferAt }
  }

  private func append(_ buffer: AVAudioPCMBuffer) {
    guard let converter else { return }
    let ratio = targetFormat.sampleRate / buffer.format.sampleRate
    let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
    guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

    var supplied = false
    var error: NSError?
    converter.convert(to: output, error: &error) { _, status in
      if supplied {
        status.pointee = .noDataNow
        return nil
      }
      supplied = true
      status.pointee = .haveData
      return buffer
    }
    guard error == nil, let channel = output.floatChannelData?[0] else { return }
    let count = Int(output.frameLength)
    lock.withLock {
      if firstBufferAt == nil { firstBufferAt = monotonicMs() }
      samples.append(contentsOf: UnsafeBufferPointer(start: channel, count: count))
    }
  }
}
