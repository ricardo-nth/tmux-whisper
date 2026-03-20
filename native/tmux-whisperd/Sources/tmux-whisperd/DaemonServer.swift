import Darwin
import Foundation

actor TranscriptionService {
  private let adapter = FluidAudioAdapter()

  func handle(_ request: DaemonRequest) async -> DaemonResponse {
    do {
      switch request.op {
      case .ping:
        return DaemonResponse(
          id: request.id,
          ok: true,
          text: nil,
          engine: "swift_parakeet",
          model: nil,
          durationMs: 0,
          errorCode: nil,
          message: "ok"
        )

      case .transcribe:
        guard let wavPath = request.wavPath, !wavPath.isEmpty else {
          throw DaemonServiceError.wavPathMissing
        }
        guard let modelPath = request.modelPath, !modelPath.isEmpty else {
          throw DaemonServiceError.modelPathMissing
        }

        let wavURL = URL(fileURLWithPath: wavPath)
        let modelURL = URL(fileURLWithPath: modelPath, isDirectory: true)
        guard FileManager.default.fileExists(atPath: wavURL.path) else {
          throw DaemonServiceError.wavPathInvalid(wavURL.path)
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: modelURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
          throw DaemonServiceError.modelPathInvalid(modelURL.path)
        }

        let modelVersion = request.modelVersion ?? "v3"
        let result = try await adapter.transcribe(audioURL: wavURL, modelURL: modelURL, modelVersion: modelVersion)
        return DaemonResponse(
          id: request.id,
          ok: true,
          text: result.text,
          engine: "swift_parakeet",
          model: result.model,
          durationMs: result.durationMs,
          errorCode: nil,
          message: nil
        )
      }
    } catch let error as DaemonServiceError {
      return DaemonResponse(
        id: request.id,
        ok: false,
        text: nil,
        engine: "swift_parakeet",
        model: nil,
        durationMs: nil,
        errorCode: error.errorCode,
        message: error.localizedDescription
      )
    } catch {
      return DaemonResponse(
        id: request.id,
        ok: false,
        text: nil,
        engine: "swift_parakeet",
        model: nil,
        durationMs: nil,
        errorCode: "runtime_error",
        message: error.localizedDescription
      )
    }
  }
}

final class UnixSocketServer {
  private let socketPath: String
  private let service: TranscriptionService
  private var serverFD: Int32 = -1

  init(socketPath: String, service: TranscriptionService) {
    self.socketPath = socketPath
    self.service = service
  }

  deinit {
    if serverFD >= 0 {
      close(serverFD)
    }
    unlink(socketPath)
  }

  func run() async throws {
    try prepareSocketDirectory()
    unlink(socketPath)

    serverFD = socket(AF_UNIX, SOCK_STREAM, 0)
    guard serverFD >= 0 else {
      throw POSIXError(.EIO)
    }

    var value: Int32 = 1
    setsockopt(serverFD, SOL_SOCKET, SO_REUSEADDR, &value, socklen_t(MemoryLayout.size(ofValue: value)))

    var address = sockaddr_un()
    address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    address.sun_family = sa_family_t(AF_UNIX)

    let pathBytes = socketPath.utf8CString
    let pathCapacity = MemoryLayout.size(ofValue: address.sun_path)
    guard pathBytes.count <= pathCapacity else {
      throw DaemonServiceError.invalidRequest("socket path is too long: \(socketPath)")
    }

    withUnsafeMutableBytes(of: &address.sun_path) { buffer in
      buffer.initializeMemory(as: UInt8.self, repeating: 0)
      _ = pathBytes.withUnsafeBytes { src in
        memcpy(buffer.baseAddress!, src.baseAddress!, min(buffer.count, src.count))
      }
    }

    let bindResult = withUnsafePointer(to: &address) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { rebound in
        bind(serverFD, rebound, socklen_t(MemoryLayout<sockaddr_un>.size))
      }
    }
    guard bindResult == 0 else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }

    guard listen(serverFD, SOMAXCONN) == 0 else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }

    while true {
      let clientFD = accept(serverFD, nil, nil)
      if clientFD < 0 {
        if errno == EINTR {
          continue
        }
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
      }

      await Self.handleClient(fd: clientFD, service: service)
    }
  }

  private func prepareSocketDirectory() throws {
    let directory = URL(fileURLWithPath: socketPath).deletingLastPathComponent()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  private static func handleClient(fd: Int32, service: TranscriptionService) async {
    defer { close(fd) }

    do {
      let requestData = try readRequest(from: fd)
      let decoder = JSONDecoder()
      let request = try decoder.decode(DaemonRequest.self, from: requestData)
      let response = await service.handle(request)
      let encoder = JSONEncoder()
      let data = try encoder.encode(response) + Data([0x0A])
      try writeAll(fd: fd, data: data)
    } catch {
      let fallback = DaemonResponse(
        id: "unknown",
        ok: false,
        text: nil,
        engine: "swift_parakeet",
        model: nil,
        durationMs: nil,
        errorCode: "protocol_error",
        message: error.localizedDescription
      )
      if let data = try? JSONEncoder().encode(fallback) + Data([0x0A]) {
        try? writeAll(fd: fd, data: data)
      }
    }
  }

  private static func readRequest(from fd: Int32) throws -> Data {
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)

    while true {
      let readCount = recv(fd, &buffer, buffer.count, 0)
      if readCount < 0 {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
      }
      if readCount == 0 {
        break
      }
      data.append(buffer, count: readCount)
      if data.contains(0x0A) {
        break
      }
    }

    if let newline = data.firstIndex(of: 0x0A) {
      data = data.prefix(upTo: newline)
    }
    if data.isEmpty {
      throw DaemonServiceError.invalidRequest("empty request")
    }
    return data
  }

  private static func writeAll(fd: Int32, data: Data) throws {
    try data.withUnsafeBytes { rawBuffer in
      guard let base = rawBuffer.baseAddress else {
        return
      }
      var total = 0
      while total < rawBuffer.count {
        let written = send(fd, base.advanced(by: total), rawBuffer.count - total, 0)
        if written < 0 {
          throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        total += written
      }
    }
  }
}
