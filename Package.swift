// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "MoviePilotCore",
  defaultLocalization: "zh-Hans",
  platforms: [.iOS(.v16), .macOS(.v14)],
  products: [.library(name: "MoviePilotCore", targets: ["MoviePilotCore"])],
  targets: [
    .target(name: "MoviePilotCore", resources: [.process("Resources")]),
    .testTarget(name: "MoviePilotCoreTests", dependencies: ["MoviePilotCore"]),
  ],
  swiftLanguageModes: [.v6]
)
