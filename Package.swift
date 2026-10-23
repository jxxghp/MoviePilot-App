// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "MoviePilotCore",
  platforms: [.iOS(.v17), .macOS(.v14)],
  products: [.library(name: "MoviePilotCore", targets: ["MoviePilotCore"])],
  targets: [
    .target(name: "MoviePilotCore"),
    .testTarget(name: "MoviePilotCoreTests", dependencies: ["MoviePilotCore"]),
  ],
  swiftLanguageModes: [.v6]
)
