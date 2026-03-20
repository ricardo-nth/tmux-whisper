import Foundation

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
      let server = UnixSocketServer(socketPath: socketPath, service: TranscriptionService())
      try await server.run()
    case "version", "--version":
      print("tmux-whisperd 0.1.0")
    case "help", "-h", "--help":
      printUsage()
    default:
      throw CLIError.usage("unknown command: \(command)")
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
