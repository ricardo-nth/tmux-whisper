import Foundation

/// The CLI's inline transcription (`transcribe_audio` →
/// `transcribe_swift_parakeet_tail_rescue_cli`) without the CLI: pad, write a
/// 16-bit WAV, transcribe, and for long takes re-transcribe the last 8 s and
/// merge. Text goes through the same `$(...)` captures as in bash, so the
/// result is what `process_inline_recording` would hand to cleanup.
public struct NativeTranscriber: Sendable {
  /// Transcribes one WAV for a flow ("inline" or "inline-tail").
  public typealias Transcribe = @Sendable (_ wav: URL, _ flow: String) throws -> String

  public struct Result: Equatable, Sendable {
    public let transcript: String
    /// Sample count of the capture as recorded (before padding).
    public let captureSamples: Int
    public let paddedSamples: Int
    /// The tail window that was re-transcribed and merged, if any.
    public let tailRescueMs: Int?
    public let tailRescueFailed: Bool
    /// The padded WAV, kept only when `keepWAV` is set (for the CLI's debug
    /// archive); the caller owns and removes it.
    public var keptWAV: URL? = nil
  }

  public let settings: TranscriptionSettings
  public let directory: URL
  /// Keep the padded WAV for `[debug] keep_logs` instead of deleting it.
  public var keepWAV: Bool

  public init(
    settings: TranscriptionSettings, directory: URL = FileManager.default.temporaryDirectory, keepWAV: Bool = false
  ) {
    self.settings = settings
    self.directory = directory
    self.keepWAV = keepWAV
  }

  public func transcribe(samples: [Float], using transcribe: Transcribe) throws -> Result {
    let pcm = WAVEncoder.pcm16(samples)
    let padded = AudioPrep.padded(pcm, tailPadMs: settings.tailPad ?? 0)
    let stem = "lowkey-\(UUID().uuidString)"
    let fullURL = directory.appendingPathComponent("\(stem).wav")
    try writeWAV(padded, to: fullURL)
    var succeeded = false
    defer {
      if !(keepWAV && succeeded) { try? FileManager.default.removeItem(at: fullURL) }
    }
    let kept = keepWAV ? fullURL : nil

    let full = PerlText.bashCapture(try transcribe(fullURL, "inline"))
    succeeded = true
    guard let window = AudioPrep.tailRescueWindowMs(paddedSampleCount: padded.count, settings: settings) else {
      return Result(transcript: full, captureSamples: pcm.count, paddedSamples: padded.count,
                    tailRescueMs: nil, tailRescueFailed: false, keptWAV: kept)
    }

    let tailURL = directory.appendingPathComponent("\(stem)-tail.wav")
    defer { try? FileManager.default.removeItem(at: tailURL) }
    var tailText: String?
    do {
      try writeWAV(AudioPrep.tail(padded, windowMs: window), to: tailURL)
      tailText = PerlText.bashCapture(try transcribe(tailURL, "inline-tail"))
    } catch {
      // The CLI keeps the full transcript when the tail pass fails.
      tailText = nil
    }
    guard let tail = tailText else {
      return Result(transcript: full, captureSamples: pcm.count, paddedSamples: padded.count,
                    tailRescueMs: window, tailRescueFailed: true, keptWAV: kept)
    }
    let spaced = String(String.UnicodeScalarView(tail.unicodeScalars.map { $0 == "\n" ? " " : $0 }))
    let transcript = PerlText.isBlank(spaced)
      ? full
      : PerlText.bashCapture(TranscriptMerge.mergeTailRescue(full: full, tail: spaced))
    return Result(transcript: transcript, captureSamples: pcm.count, paddedSamples: padded.count,
                  tailRescueMs: window, tailRescueFailed: false, keptWAV: kept)
  }

  private func writeWAV(_ pcm: [Int16], to url: URL) throws {
    let data = WAVEncoder.encode(pcm: pcm)
    guard FileManager.default.createFile(atPath: url.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
      throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
    }
  }
}
