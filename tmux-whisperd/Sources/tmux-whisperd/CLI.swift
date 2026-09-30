import Foundation
import TmuxWhisperKit

enum CLIError: Error, LocalizedError {
  case usage(String)

  var errorDescription: String? {
    switch self {
    case .usage(let message):
      return message
    }
  }
}

@main
enum TmuxWhisperdMain {
  static func main() async {
    do {
      try await run()
    } catch {
      fputs("tmux-whisperd: \(error.localizedDescription)\n", stderr)
      exit(2)
    }
  }

  private static func run() async throws {
    var arguments = Array(CommandLine.arguments.dropFirst())
    let command = arguments.first ?? "help"
    if !arguments.isEmpty {
      arguments.removeFirst()
    }

    switch command {
    case "serve":
      let socketPath = try parseSocketPath(arguments)
      let server = UnixSocketServer(socketPath: socketPath, handler: TranscriptionService())
      let signalSources = installShutdownHandlers(server: server)
      defer { signalSources.forEach { $0.cancel() } }
      try await server.run()
    case "version", "--version":
      print("tmux-whisperd \(DaemonInfo.daemonVersion)")
    case "help", "-h", "--help":
      printUsage()
    default:
      throw CLIError.usage("unknown command: \(command)")
    }
  }

  /// Stop cleanly on SIGTERM/SIGINT so the socket file is removed.
  private static func installShutdownHandlers(server: UnixSocketServer) -> [DispatchSourceSignal] {
    [SIGTERM, SIGINT].map { signalNumber in
      signal(signalNumber, SIG_IGN)
      let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
      source.setEventHandler {
        server.stop()
        exit(0)
      }
      source.resume()
      return source
    }
  }

  private static func parseSocketPath(_ arguments: [String]) throws -> String {
    var iterator = arguments.makeIterator()
    var socketPath: String?

    while let argument = iterator.next() {
      switch argument {
      case "--socket":
        socketPath = iterator.next()
      default:
        throw CLIError.usage("unknown argument: \(argument)")
      }
    }

    guard let socketPath, !socketPath.isEmpty else {
      throw CLIError.usage("serve requires --socket <path>")
    }
    return socketPath
  }

  private static func printUsage() {
    print(
      """
      tmux-whisperd: persistent local transcription daemon for tmux-whisper.

      Usage:
        tmux-whisperd serve --socket /path/to/tmux-whisperd.sock
        tmux-whisperd version
      """
    )
  }
}
