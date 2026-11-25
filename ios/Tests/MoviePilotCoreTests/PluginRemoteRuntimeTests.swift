import XCTest
@testable import MoviePilotCore

final class PluginRemoteRuntimeTests: XCTestCase {
  func testValidateAPIPathAllowsRelativeMoviePilotPathsAndRejectsUnsafeInputs() throws {
    XCTAssertEqual(
      try PluginRemoteRuntime.validateAPIPath("plugin/Demo/status?page=1"),
      "/api/v1/plugin/Demo/status?page=1"
    )
    XCTAssertEqual(
      try PluginRemoteRuntime.validateAPIPath("/api/v1/plugin/Demo/config"),
      "/api/v1/plugin/Demo/config"
    )

    let invalid = [
      "",
      "https://evil.example/api/v1/plugin/x",
      "//evil.example/api/v1/plugin/x",
      "/api/v1/plugin/../system/env",
      "/api/v1/plugin/%2e%2e/secret",
      "/api/v1/plugin/demo\\secret",
      "javascript:alert(1)",
    ]
    for path in invalid {
      XCTAssertThrowsError(try PluginRemoteRuntime.validateAPIPath(path), "Should reject \(path)")
    }
  }

  func testNormalizeRemoteEntryAndResolveUpstreamRoundtrip() throws {
    let plan = try PluginRemoteRuntime.normalizeRemoteEntry(
      pluginId: "VueCompatDemo",
      versionOrHash: "1.2.0",
      rawRemoteURL: "/api/v1/plugin/file/vuecompatdemo/dist/assets/remoteEntry.js?v=1.2.0"
    )
    XCTAssertEqual(plan.pluginId, "vuecompatdemo")
    XCTAssertEqual(plan.versionTag, "1.2.0")
    XCTAssertEqual(
      plan.virtualEntryPath,
      "/plugin-remote/vuecompatdemo/1.2.0/dist/assets/remoteEntry.js"
    )
    XCTAssertEqual(
      plan.upstreamFilePath,
      "/api/v1/plugin/file/vuecompatdemo/dist/assets/remoteEntry.js"
    )

    let target = try PluginRemoteRuntime.resolveUpstreamPath(
      "/plugin-remote/vuecompatdemo/1.2.0/dist/assets/chunk-abc.js?t=1"
    )
    XCTAssertEqual(target.pluginId, "vuecompatdemo")
    XCTAssertEqual(target.versionTag, "1.2.0")
    XCTAssertEqual(target.assetRelPath, "dist/assets/chunk-abc.js")
    XCTAssertEqual(
      target.upstreamApiPath,
      "/api/v1/plugin/file/vuecompatdemo/dist/assets/chunk-abc.js"
    )

    XCTAssertThrowsError(
      try PluginRemoteRuntime.resolveUpstreamPath("/plugin-remote/demo/1.0/../../etc/passwd")
    )
    XCTAssertThrowsError(
      try PluginRemoteRuntime.validateShellAssetPath("/shell/../secret.txt")
    )
    XCTAssertEqual(
      try PluginRemoteRuntime.validateShellAssetPath("/shell/assets/plugin-shell.js"),
      "assets/plugin-shell.js"
    )
  }

  func testBuildCacheKeyIsolatesInstancesDeterministically() {
    let a = PluginRemoteRuntime.buildCacheKey(
      instanceOrigin: "https://mp-a.example.com/",
      pluginId: "MyPlugin",
      versionOrHash: "2.0.1"
    )
    let b = PluginRemoteRuntime.buildCacheKey(
      instanceOrigin: "https://mp-b.example.com",
      pluginId: "MyPlugin",
      versionOrHash: "2.0.1"
    )
    XCTAssertNotEqual(a.instanceHash, b.instanceHash)
    XCTAssertEqual(a.pluginIdLower, "myplugin")
    XCTAssertEqual(a.versionSegment, "2.0.1")
    XCTAssertEqual(a.relativeDir, "\(a.instanceHash)/myplugin/2.0.1")
  }
}
