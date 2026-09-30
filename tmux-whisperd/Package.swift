// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "tmux-whisperd",
  platforms: [
    .macOS(.v14),
  ],
  products: [
    .executable(
      name: "tmux-whisperd",
      targets: ["tmux-whisperd"]
    ),
    // Shared engine, protocol, and socket server for the daemon and the
    // future native macOS app.
    .library(
      name: "TmuxWhisperKit",
      targets: ["TmuxWhisperKit"]
    ),
  ],
  dependencies: [
    .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.12.4"),
  ],
  targets: [
    .target(
      name: "TmuxWhisperKit",
      dependencies: [
        .product(name: "FluidAudio", package: "FluidAudio"),
      ],
      path: "Sources/TmuxWhisperKit"
    ),
    .executableTarget(
      name: "tmux-whisperd",
      dependencies: ["TmuxWhisperKit"],
      path: "Sources/tmux-whisperd"
    ),
    .testTarget(
      name: "TmuxWhisperKitTests",
      dependencies: ["TmuxWhisperKit"],
      path: "Tests/TmuxWhisperKitTests"
    ),
  ]
)
