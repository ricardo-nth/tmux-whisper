import Foundation

/// Encodes mono Float32 samples (-1...1) as 16-bit PCM WAV, the format the
/// CLI's transcription pipeline expects from its own ffmpeg capture.
public enum WAVEncoder {
  public static func encode(samples: [Float], sampleRate: Int = 16_000) -> Data {
    let channels = 1
    let bitsPerSample = 16
    let byteRate = sampleRate * channels * bitsPerSample / 8
    let blockAlign = channels * bitsPerSample / 8
    let dataSize = samples.count * blockAlign

    var data = Data(capacity: 44 + dataSize)
    data.append(contentsOf: Array("RIFF".utf8))
    data.appendLE(UInt32(36 + dataSize))
    data.append(contentsOf: Array("WAVE".utf8))
    data.append(contentsOf: Array("fmt ".utf8))
    data.appendLE(UInt32(16))              // fmt chunk size
    data.appendLE(UInt16(1))               // PCM
    data.appendLE(UInt16(channels))
    data.appendLE(UInt32(sampleRate))
    data.appendLE(UInt32(byteRate))
    data.appendLE(UInt16(blockAlign))
    data.appendLE(UInt16(bitsPerSample))
    data.append(contentsOf: Array("data".utf8))
    data.appendLE(UInt32(dataSize))

    var pcm = [Int16](repeating: 0, count: samples.count)
    for (index, sample) in samples.enumerated() {
      let clamped = max(-1, min(1, sample.isFinite ? sample : 0))
      pcm[index] = Int16((clamped * 32767).rounded())
    }
    pcm.withUnsafeBufferPointer { buffer in
      // WAV is little-endian, like every Apple Silicon/Intel Mac.
      data.append(UnsafeBufferPointer(start: UnsafeRawPointer(buffer.baseAddress!)
        .assumingMemoryBound(to: UInt8.self), count: buffer.count * 2))
    }
    return data
  }
}

extension Data {
  mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
    var little = value.littleEndian
    Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
  }
}
