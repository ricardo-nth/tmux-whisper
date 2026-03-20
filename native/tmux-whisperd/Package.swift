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
  ],
  dependencies: [
    .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.12.4"),
  ],
  targets: [
    .executableTarget(
      name: "tmux-whisperd",
      dependencies: [
        .product(name: "FluidAudio", package: "FluidAudio"),
      ],
      path: "Sources/tmux-whisperd"
    ),
  ]
)
