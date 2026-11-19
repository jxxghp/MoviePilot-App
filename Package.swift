// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "MoviePilotCore",
  defaultLocalization: "zh-Hans",
  platforms: [.iOS(.v16), .macOS(.v14)],
  products: [
    .library(name: "MoviePilotCore", targets: ["MoviePilotCore"]),
    .library(name: "MoviePilotAPI", targets: ["MoviePilotAPI"]),
    .library(name: "MoviePilotSession", targets: ["MoviePilotSession"]),
    .library(name: "MoviePilotPluginUI", targets: ["MoviePilotPluginUI"]),
  ],
  targets: [
    .target(name: "MoviePilotCore", resources: [.process("Resources")]),
    .target(name: "MoviePilotAPI", dependencies: ["MoviePilotCore"]),
    .target(name: "MoviePilotSession", dependencies: ["MoviePilotAPI", "MoviePilotCore"]),
    .target(name: "MoviePilotPluginUI"),
    .testTarget(name: "MoviePilotCoreTests", dependencies: ["MoviePilotCore"]),
    .testTarget(name: "MoviePilotAPITests", dependencies: ["MoviePilotAPI", "MoviePilotCore"]),
    .testTarget(
      name: "MoviePilotSessionTests",
      dependencies: ["MoviePilotSession", "MoviePilotAPI", "MoviePilotCore"]),
    .testTarget(
      name: "MoviePilotPluginUITests", dependencies: ["MoviePilotPluginUI"],
      resources: [.copy("Fixtures")]),
  ],
  swiftLanguageModes: [.v6]
)
