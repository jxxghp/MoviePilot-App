import CryptoKit
import Foundation

/// Vue 联邦插件本地预热运行时（Route A）纯 Swift 路径安全、缓存键派生与虚拟源路由引擎。
/// 与 Rust `mp_core_plugin::remote_runtime` 保持 1:1 契约一致。
public enum PluginRemoteRuntimeError: Error, Equatable, Sendable {
  case invalidAPIPath
  case invalidShellAssetPath
  case invalidRemoteEntryURL
  case invalidVirtualRemotePath
}

public struct PluginRemoteCacheKey: Codable, Equatable, Sendable {
  public let instanceHash: String
  public let pluginIdLower: String
  public let versionSegment: String
  public let relativeDir: String

  enum CodingKeys: String, CodingKey {
    case instanceHash = "instance_hash"
    case pluginIdLower = "plugin_id_lower"
    case versionSegment = "version_segment"
    case relativeDir = "relative_dir"
  }

  public init(
    instanceHash: String,
    pluginIdLower: String,
    versionSegment: String,
    relativeDir: String
  ) {
    self.instanceHash = instanceHash
    self.pluginIdLower = pluginIdLower
    self.versionSegment = versionSegment
    self.relativeDir = relativeDir
  }
}

public struct PluginRemoteEntryPlan: Codable, Equatable, Sendable {
  public let pluginId: String
  public let versionTag: String
  public let virtualEntryPath: String
  public let upstreamFilePath: String

  enum CodingKeys: String, CodingKey {
    case pluginId = "plugin_id"
    case versionTag = "version_tag"
    case virtualEntryPath = "virtual_entry_path"
    case upstreamFilePath = "upstream_file_path"
  }

  public init(
    pluginId: String,
    versionTag: String,
    virtualEntryPath: String,
    upstreamFilePath: String
  ) {
    self.pluginId = pluginId
    self.versionTag = versionTag
    self.virtualEntryPath = virtualEntryPath
    self.upstreamFilePath = upstreamFilePath
  }
}

public struct PluginRemoteUpstreamTarget: Codable, Equatable, Sendable {
  public let pluginId: String
  public let versionTag: String
  public let assetRelPath: String
  public let upstreamApiPath: String

  enum CodingKeys: String, CodingKey {
    case pluginId = "plugin_id"
    case versionTag = "version_tag"
    case assetRelPath = "asset_rel_path"
    case upstreamApiPath = "upstream_api_path"
  }

  public init(
    pluginId: String,
    versionTag: String,
    assetRelPath: String,
    upstreamApiPath: String
  ) {
    self.pluginId = pluginId
    self.versionTag = versionTag
    self.assetRelPath = assetRelPath
    self.upstreamApiPath = upstreamApiPath
  }
}

public enum PluginRemoteRuntime {
  /// 校验并规范化插件 Bridge 请求的 `/api/v1/...` 路径，拒绝外部主机、协议前缀、路径穿越与控制字符。
  public static func validateAPIPath(_ rawPath: String) throws -> String {
    let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, !hasControlOrBackslash(trimmed) else {
      throw PluginRemoteRuntimeError.invalidAPIPath
    }
    let lower = trimmed.lowercased()
    if lower.contains("://")
      || lower.hasPrefix("//")
      || lower.hasPrefix("http:")
      || lower.hasPrefix("https:")
      || lower.hasPrefix("javascript:")
      || lower.hasPrefix("data:")
      || lower.hasPrefix("file:")
    {
      throw PluginRemoteRuntimeError.invalidAPIPath
    }

    let withoutFragment = String(trimmed.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0])
    let parts = withoutFragment.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
    let rawPathPart = String(parts[0])
    let queryPart: String? = parts.count > 1 ? String(parts[1]) : nil

    let stripped = trimLeadingSlashes(rawPathPart)
    let relative: String
    if stripped.hasPrefix("api/v1/") {
      relative = String(stripped.dropFirst("api/v1/".count))
    } else if stripped == "api/v1" {
      relative = ""
    } else {
      relative = stripped
    }

    guard let segments = validateSafeRelativeSegments(relative) else {
      throw PluginRemoteRuntimeError.invalidAPIPath
    }
    let normalized = "/api/v1/" + segments.joined(separator: "/")
    if let queryPart {
      guard !hasControlOrBackslash(queryPart) else {
        throw PluginRemoteRuntimeError.invalidAPIPath
      }
      return "\(normalized)?\(queryPart)"
    }
    return normalized
  }

  /// 校验虚拟壳 `/shell/...` 资产路径并返回安全的包内相对路径。
  public static func validateShellAssetPath(_ virtualPath: String) throws -> String {
    let trimmed = virtualPath.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, !hasControlOrBackslash(trimmed) else {
      throw PluginRemoteRuntimeError.invalidShellAssetPath
    }
    let clean = stripQueryAndFragment(trimmed)
    let stripped = trimLeadingSlashes(clean)
    let rel = stripped.hasPrefix("shell/") ? String(stripped.dropFirst("shell/".count)) : stripped
    guard let segments = validateSafeRelativeSegments(rel) else {
      throw PluginRemoteRuntimeError.invalidShellAssetPath
    }
    return segments.joined(separator: "/")
  }

  /// 将任意字符串清洗为文件系统安全单段标识（与 Rust 侧 1:1 对齐）。
  public static func sanitizeCacheSegment(_ raw: String, fallback: String) -> String {
    var out = ""
    for ch in raw.trimmingCharacters(in: .whitespacesAndNewlines) {
      if out.count >= 64 { break }
      if ch.isASCII && (ch.isLetter || ch.isNumber || ch == "-" || ch == "_" || ch == ".") {
        out.append(ch)
      } else {
        out.append("_")
      }
    }
    let trimSet = CharacterSet(charactersIn: "._")
    let cleaned = out.trimmingCharacters(in: trimSet)
    if cleaned.isEmpty || cleaned == "." || cleaned == ".." || cleaned.contains("..") {
      return fallback
    }
    return cleaned
  }

  /// 派生按实例源 SHA-256、插件 ID 与版本/产物哈希隔离的磁盘缓存键。
  public static func buildCacheKey(
    instanceOrigin: String,
    pluginId: String,
    versionOrHash: String
  ) -> PluginRemoteCacheKey {
    let normalizedOrigin =
      instanceOrigin
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
      .lowercased()
    let digest = SHA256.hash(data: Data(normalizedOrigin.utf8))
    let fullHex = digest.map { String(format: "%02x", $0) }.joined()
    let instanceHash = String(fullHex.prefix(16))
    let pluginIdLower = sanitizeCacheSegment(pluginId.lowercased(), fallback: "plugin")
    let versionSegment = sanitizeCacheSegment(versionOrHash, fallback: "default")
    return PluginRemoteCacheKey(
      instanceHash: instanceHash,
      pluginIdLower: pluginIdLower,
      versionSegment: versionSegment,
      relativeDir: "\(instanceHash)/\(pluginIdLower)/\(versionSegment)"
    )
  }

  /// 将后端 `/api/v1/plugin/remotes` 返回的入口规划为虚拟源入口与上游文件路径。
  public static func normalizeRemoteEntry(
    pluginId: String,
    versionOrHash: String,
    rawRemoteURL: String
  ) throws -> PluginRemoteEntryPlan {
    let trimmed = rawRemoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, !hasControlOrBackslash(trimmed) else {
      throw PluginRemoteRuntimeError.invalidRemoteEntryURL
    }
    let withoutFragment = String(trimmed.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0])
    let parts = withoutFragment.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
    let pathOrURL = String(parts[0])
    let queryPart = parts.count > 1 ? String(parts[1]) : ""

    let pathOnly: String
    if let schemeRange = pathOrURL.range(of: "://") {
      let afterScheme = pathOrURL[schemeRange.upperBound...]
      guard let slashIdx = afterScheme.firstIndex(of: "/") else {
        throw PluginRemoteRuntimeError.invalidRemoteEntryURL
      }
      pathOnly = String(afterScheme[slashIdx...])
    } else {
      pathOnly = pathOrURL
    }

    let lowerPath = pathOnly.lowercased()
    guard let markerRange = lowerPath.range(of: "plugin/file/") else {
      throw PluginRemoteRuntimeError.invalidRemoteEntryURL
    }
    let offset = lowerPath.distance(from: lowerPath.startIndex, to: markerRange.upperBound)
    let afterMarker = String(pathOnly[pathOnly.index(pathOnly.startIndex, offsetBy: offset)...])

    guard let segments = validateSafeRelativeSegments(afterMarker), segments.count >= 2 else {
      throw PluginRemoteRuntimeError.invalidRemoteEntryURL
    }
    let filePluginId = segments[0]
    guard isValidPluginIdSegment(filePluginId) else {
      throw PluginRemoteRuntimeError.invalidRemoteEntryURL
    }
    let assetRelPath = segments.dropFirst().joined(separator: "/")

    let versionSource: String
    if !versionOrHash.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      versionSource = versionOrHash.trimmingCharacters(in: .whitespacesAndNewlines)
    } else if let queryVersion = extractQueryParam(queryPart, key: "v") {
      versionSource = queryVersion
    } else {
      versionSource = "default"
    }
    let versionTag = sanitizeCacheSegment(versionSource, fallback: "default")

    return PluginRemoteEntryPlan(
      pluginId: filePluginId,
      versionTag: versionTag,
      virtualEntryPath: "/plugin-remote/\(filePluginId)/\(versionTag)/\(assetRelPath)",
      upstreamFilePath: "/api/v1/plugin/file/\(filePluginId)/\(assetRelPath)"
    )
  }

  /// 将 WebView 发往 `/plugin-remote/{pluginId}/{version}/{assetRelPath}` 的请求还原为上游 API 路径。
  public static func resolveUpstreamPath(_ virtualPath: String) throws -> PluginRemoteUpstreamTarget {
    let trimmed = virtualPath.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, !hasControlOrBackslash(trimmed) else {
      throw PluginRemoteRuntimeError.invalidVirtualRemotePath
    }
    let clean = stripQueryAndFragment(trimmed)
    let stripped = trimLeadingSlashes(clean)
    guard stripped.hasPrefix("plugin-remote/") else {
      throw PluginRemoteRuntimeError.invalidVirtualRemotePath
    }
    let rest = String(stripped.dropFirst("plugin-remote/".count))
    guard let segments = validateSafeRelativeSegments(rest), segments.count >= 3 else {
      throw PluginRemoteRuntimeError.invalidVirtualRemotePath
    }
    let pluginId = segments[0]
    guard isValidPluginIdSegment(pluginId) else {
      throw PluginRemoteRuntimeError.invalidVirtualRemotePath
    }
    let versionTag = sanitizeCacheSegment(segments[1], fallback: "default")
    let assetRelPath = segments.dropFirst(2).joined(separator: "/")
    return PluginRemoteUpstreamTarget(
      pluginId: pluginId,
      versionTag: versionTag,
      assetRelPath: assetRelPath,
      upstreamApiPath: "/api/v1/plugin/file/\(pluginId)/\(assetRelPath)"
    )
  }

  /// 根据文件扩展名返回标准 MIME 类型。
  public static func mimeType(forPath path: String) -> String {
    let ext = (stripQueryAndFragment(path) as NSString).pathExtension.lowercased()
    switch ext {
    case "html", "htm": return "text/html; charset=utf-8"
    case "js", "mjs", "cjs": return "application/javascript; charset=utf-8"
    case "css": return "text/css; charset=utf-8"
    case "json", "map": return "application/json; charset=utf-8"
    case "svg": return "image/svg+xml"
    case "png": return "image/png"
    case "jpg", "jpeg": return "image/jpeg"
    case "webp": return "image/webp"
    case "gif": return "image/gif"
    case "ico": return "image/x-icon"
    case "woff": return "font/woff"
    case "woff2": return "font/woff2"
    case "ttf": return "font/ttf"
    case "wasm": return "application/wasm"
    default: return "application/octet-stream"
    }
  }

  private static func hasControlOrBackslash(_ s: String) -> Bool {
    s.utf8.contains { $0 < 0x20 || $0 == 0x7f || $0 == UInt8(ascii: "\\") }
  }

  private static func trimLeadingSlashes(_ s: String) -> String {
    var idx = s.startIndex
    while idx < s.endIndex && s[idx] == "/" {
      idx = s.index(after: idx)
    }
    return String(s[idx...])
  }

  private static func stripQueryAndFragment(_ s: String) -> String {
    let withoutFrag = String(s.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0])
    return String(withoutFrag.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)[0])
  }

  private static func isValidPluginIdSegment(_ segment: String) -> Bool {
    guard !segment.isEmpty, segment.count <= 128, !segment.hasPrefix("."), !segment.contains("..") else {
      return false
    }
    return segment.utf8.allSatisfy { b in
      (b >= UInt8(ascii: "a") && b <= UInt8(ascii: "z"))
        || (b >= UInt8(ascii: "A") && b <= UInt8(ascii: "Z"))
        || (b >= UInt8(ascii: "0") && b <= UInt8(ascii: "9"))
        || b == UInt8(ascii: "_")
        || b == UInt8(ascii: "-")
        || b == UInt8(ascii: ".")
    }
  }

  private static func validateSafeRelativeSegments(_ raw: String) -> [String]? {
    let trimmed = raw.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    guard !trimmed.isEmpty else { return nil }
    var result: [String] = []
    for rawSeg in trimmed.split(separator: "/", omittingEmptySubsequences: false) {
      let seg = String(rawSeg)
      if seg.isEmpty || seg == "." || seg == ".." {
        return nil
      }
      let decoded = (seg.removingPercentEncoding ?? seg).lowercased()
      if decoded == "."
        || decoded == ".."
        || decoded.contains("..")
        || decoded.contains("/")
        || decoded.contains("\\")
        || decoded.contains("\0")
      {
        return nil
      }
      result.append(seg)
    }
    return result
  }

  private static func extractQueryParam(_ query: String, key: String) -> String? {
    for pair in query.split(separator: "&") {
      let kv = pair.split(separator: "=", maxSplits: 1)
      if kv.count == 2 && kv[0] == key {
        let val = String(kv[1]).trimmingCharacters(in: .whitespacesAndNewlines)
        if !val.isEmpty { return val }
      }
    }
    return nil
  }
}
