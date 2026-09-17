// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "TmuxWhisperCompanion",
  platforms: [.macOS(.v13)],
  products: [
    .library(name: "CompanionCore", targets: ["CompanionCore"]),
    .executable(name: "WhisperCompanion", targets: ["WhisperCompanion"]),
  ],
  targets: [
    .target(name: "CompanionCore"),
    .executableTarget(name: "WhisperCompanion", dependencies: ["CompanionCore"]),
    .executableTarget(
      name: "CompanionCoreRegression",
      dependencies: ["CompanionCore"],
      path: "Tests/CompanionCoreTests"
    ),
  ]
)
