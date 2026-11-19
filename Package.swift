// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "MoviePilotCore",
  defaultLocalization: "zh-Hans",
  platforms: [.iOS(.v16), .macOS(.v14)],
  products: [
    .library(name: "MoviePilotCore", targets: ["MoviePilotCore"]),
    .library(name: "MoviePilotAPI", targets: ["MoviePilotAPI"]),
  ],
  targets: [
    .target(name: "MoviePilotCore", resources: [.process("Resources")]),
    .target(name: "MoviePilotAPI", dependencies: ["MoviePilotCore"]),
    .testTarget(name: "MoviePilotCoreTests", dependencies: ["MoviePilotCore"]),
    .testTarget(name: "MoviePilotAPITests", dependencies: ["MoviePilotAPI", "MoviePilotCore"]),
  ],
  swiftLanguageModes: [.v6]
)
