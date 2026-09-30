import Darwin
import Foundation

/// Line-delimited JSON server on a Unix domain socket.
///
/// `accept` runs on a dedicated thread and every client gets its own thread,
/// so blocking socket calls never occupy the Swift concurrency pool and a quick
/// `ping` is answered while a long transcription is in progress.
public final class UnixSocketServer: @unchecked Sendable {
  public struct Limits: Sendable {
    /// Largest accepted request line, in bytes.
    public var maxRequestBytes: Int
    /// How long a client may take to send its request line.
    public var readTimeout: TimeInterval
    /// How long a response write may block on a stalled client.
    public var writeTimeout: TimeInterval

    public init(maxRequestBytes: Int = 1 << 20, readTimeout: TimeInterval = 10, writeTimeout: TimeInterval = 30) {
      self.maxRequestBytes = maxRequestBytes
      self.readTimeout = readTimeout
      self.writeTimeout = writeTimeout
    }
  }

  public enum ServerError: Error, LocalizedError {
    case socketPathTooLong(String)
    case socketPathOccupied(String)
    case posix(String, Int32)

    public var errorDescription: String? {
      switch self {
      case .socketPathTooLong(let path):
        return "socket path is too long: \(path)"
      case .socketPathOccupied(let path):
        return "refusing to replace a non-socket file at \(path)"
      case .posix(let call, let code):
        return "\(call) failed: \(String(cString: strerror(code)))"
      }
    }
  }

  private let socketPath: String
  private let handler: any DaemonRequestHandling
  private let limits: Limits
  private let lock = NSLock()
  private var serverFD: Int32 = -1
  private var stopped = false

  public init(socketPath: String, handler: any DaemonRequestHandling, limits: Limits = Limits()) {
    self.socketPath = socketPath
    self.handler = handler
    self.limits = limits
  }

  deinit {
    stop()
  }

  /// Binds and starts accepting in the background. Returns once the socket is
  /// listening.
  public func start() throws {
    try prepareSocketPath()

    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else {
      throw ServerError.posix("socket", errno)
    }

    do {
      var address = try Self.socketAddress(for: socketPath)
      let bindResult = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { rebound in
          bind(fd, rebound, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
      }
      guard bindResult == 0 else {
        throw ServerError.posix("bind", errno)
      }
      // Only this user may talk to the daemon (it reads arbitrary paths).
      guard chmod(socketPath, 0o600) == 0 else {
        throw ServerError.posix("chmod", errno)
      }
      guard listen(fd, SOMAXCONN) == 0 else {
        throw ServerError.posix("listen", errno)
      }
    } catch {
      close(fd)
      throw error
    }

    lock.withLock {
      serverFD = fd
      stopped = false
    }

    let thread = Thread { [self] in acceptLoop(fd: fd) }
    thread.name = "tmux-whisperd.accept"
    thread.start()
  }

  /// Starts the server and suspends forever. Used by `tmux-whisperd serve`.
  public func run() async throws {
    try start()
    while true {
      try await Task.sleep(for: .seconds(3600))
    }
  }

  /// Stops accepting and removes the socket file. In-flight clients finish.
  public func stop() {
    let fd: Int32 = lock.withLock {
      guard !stopped else { return -1 }
      stopped = true
      let fd = serverFD
      serverFD = -1
      return fd
    }
    guard fd >= 0 else { return }
    // close() does not reliably wake a thread blocked in accept() on Darwin;
    // a throwaway connection does, and the loop then sees `stopped`.
    Self.wakeAcceptor(socketPath: socketPath)
    close(fd)
    Self.unlinkIfSocket(socketPath)
  }

  private var isStopped: Bool {
    lock.withLock { stopped }
  }

  private func acceptLoop(fd: Int32) {
    while !isStopped {
      let clientFD = accept(fd, nil, nil)
      if clientFD < 0 {
        if errno == EINTR || errno == ECONNABORTED {
          continue
        }
        if isStopped {
          return
        }
        // Transient failures (e.g. EMFILE) must not kill the daemon.
        usleep(50_000)
        continue
      }
      if isStopped {
        close(clientFD)
        return
      }

      configureClient(clientFD)
      let handler = self.handler
      let limits = self.limits
      let thread = Thread {
        Self.serveClient(fd: clientFD, handler: handler, limits: limits)
      }
      thread.name = "tmux-whisperd.client"
      thread.start()
    }
  }

  private func configureClient(_ fd: Int32) {
    var one: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
    var readTimeout = Self.timeval(from: limits.readTimeout)
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &readTimeout, socklen_t(MemoryLayout<timeval>.size))
    var writeTimeout = Self.timeval(from: limits.writeTimeout)
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &writeTimeout, socklen_t(MemoryLayout<timeval>.size))
  }

  private static func serveClient(fd: Int32, handler: any DaemonRequestHandling, limits: Limits) {
    defer { close(fd) }

    let response: DaemonResponse
    do {
      let line = try readRequestLine(from: fd, maxBytes: limits.maxRequestBytes)
      let request = try JSONDecoder().decode(DaemonRequest.self, from: line)
      response = awaitResponse(handler: handler, request: request)
    } catch {
      response = .failure(id: "unknown", code: "protocol_error", message: error.localizedDescription)
    }

    guard let data = try? JSONEncoder().encode(response) else { return }
    try? writeAll(fd: fd, data: data + Data([0x0A]))
  }

  /// Bridges the async handler onto this client's dedicated thread.
  private static func awaitResponse(handler: any DaemonRequestHandling, request: DaemonRequest) -> DaemonResponse {
    final class Box: @unchecked Sendable {
      var response: DaemonResponse?
    }
    let box = Box()
    let done = DispatchSemaphore(value: 0)
    Task {
      box.response = await handler.handle(request)
      done.signal()
    }
    done.wait()
    return box.response ?? .failure(id: request.id, code: "runtime_error", message: "no response")
  }

  static func readRequestLine(from fd: Int32, maxBytes: Int) throws -> Data {
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)

    while true {
      let readCount = recv(fd, &buffer, buffer.count, 0)
      if readCount < 0 {
        if errno == EINTR {
          continue
        }
        if errno == EAGAIN || errno == EWOULDBLOCK {
          throw DaemonServiceError.invalidRequest("timed out waiting for request")
        }
        throw ServerError.posix("recv", errno)
      }
      if readCount == 0 {
        break
      }
      data.append(buffer, count: readCount)
      if let newline = data.firstIndex(of: 0x0A) {
        data = data.prefix(upTo: newline)
        break
      }
      if data.count > maxBytes {
        throw DaemonServiceError.invalidRequest("request exceeds \(maxBytes) bytes")
      }
    }

    if data.count > maxBytes {
      throw DaemonServiceError.invalidRequest("request exceeds \(maxBytes) bytes")
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
          if errno == EINTR {
            continue
          }
          throw ServerError.posix("send", errno)
        }
        total += written
      }
    }
  }

  private func prepareSocketPath() throws {
    let directory = URL(fileURLWithPath: socketPath).deletingLastPathComponent()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    var info = stat()
    if lstat(socketPath, &info) == 0 {
      guard (info.st_mode & S_IFMT) == S_IFSOCK else {
        throw ServerError.socketPathOccupied(socketPath)
      }
      unlink(socketPath)
    }
  }

  private static func unlinkIfSocket(_ path: String) {
    var info = stat()
    if lstat(path, &info) == 0, (info.st_mode & S_IFMT) == S_IFSOCK {
      unlink(path)
    }
  }

  private static func wakeAcceptor(socketPath: String) {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return }
    defer { close(fd) }
    guard var address = try? socketAddress(for: socketPath) else { return }
    _ = withUnsafePointer(to: &address) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { rebound in
        connect(fd, rebound, socklen_t(MemoryLayout<sockaddr_un>.size))
      }
    }
  }

  static func socketAddress(for path: String) throws -> sockaddr_un {
    var address = sockaddr_un()
    address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    address.sun_family = sa_family_t(AF_UNIX)

    let pathBytes = path.utf8CString
    let pathCapacity = MemoryLayout.size(ofValue: address.sun_path)
    guard pathBytes.count <= pathCapacity else {
      throw ServerError.socketPathTooLong(path)
    }

    withUnsafeMutableBytes(of: &address.sun_path) { buffer in
      buffer.initializeMemory(as: UInt8.self, repeating: 0)
      _ = pathBytes.withUnsafeBytes { src in
        memcpy(buffer.baseAddress!, src.baseAddress!, min(buffer.count, src.count))
      }
    }
    return address
  }

  private static func timeval(from seconds: TimeInterval) -> Darwin.timeval {
    let whole = max(0, Int(seconds))
    let micros = Int32(max(0, (seconds - Double(whole)) * 1_000_000))
    return Darwin.timeval(tv_sec: whole, tv_usec: micros)
  }
}
